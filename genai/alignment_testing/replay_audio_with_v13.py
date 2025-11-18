#!/usr/bin/env python3
"""
Replay an audio file through the V13 Sherpa-Anchored VAD tracker to emulate the
Flutter app’s logic. Useful for reproducing in-app behavior (e.g., “You are
Adalyn” jumping ahead) entirely in Python.
"""

from __future__ import annotations

import argparse
import json
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

import numpy as np
import sherpa_onnx

from v13_sherpa_anchored_vad import V13SherpaAnchoredVAD

PROJECT_ROOT = Path("/Users/michaelholloway/dev/xen-words")
DEFAULT_AUDIO = PROJECT_ROOT / "test_audio/clean_recording.wav"
DEFAULT_GT = PROJECT_ROOT / "genai/alignment_testing/clean_recording_gt.json"
DEFAULT_SCRIPT = PROJECT_ROOT / "genai/alignment_testing/scripts/adalyn_story.txt"
DEFAULT_MODEL_DIR = PROJECT_ROOT / "genai/alignment_testing/sherpa-onnx-streaming-zipformer-en-2023-06-26"


@dataclass
class TrackingSample:
    audio_time: float
    word_index: int
    true_word_index: int
    drift: int
    source: str
    confidence: float
    sherpa_text: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replay audio into V13 tracker to mimic Dart behavior.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--audio", type=Path, default=DEFAULT_AUDIO,
                        help="Path to WAV file (16 kHz mono preferred).")
    parser.add_argument("--ground-truth", type=Path, default=DEFAULT_GT,
                        help="Ground-truth JSON with word timings.")
    parser.add_argument("--script", type=Path, default=DEFAULT_SCRIPT,
                        help="Script text file (falls back to GT transcript if missing).")
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR,
                        help="Directory containing sherpa-onnx Zipformer model files.")
    parser.add_argument("--chunk-ms", type=float, default=16.0,
                        help="Frame length to feed the tracker (ms).")
    parser.add_argument("--quiet", action="store_true",
                        help="Reduce tracker debug logs.")
    parser.add_argument("--save-events", type=Path,
                        help="Optional path to dump tracking samples JSON.")
    return parser.parse_args()


def main():
    args = parse_args()
    audio_path = args.audio.expanduser()
    gt_path = args.ground_truth.expanduser()
    script_path = args.script.expanduser()
    model_dir = args.model_dir.expanduser()

    if not audio_path.exists():
        raise FileNotFoundError(audio_path)
    if not gt_path.exists():
        raise FileNotFoundError(gt_path)
    if not model_dir.exists():
        raise FileNotFoundError(model_dir)

    gt_data = load_ground_truth(gt_path)
    word_timings = extract_word_timings(gt_data)
    script_text = load_script_text(script_path, gt_data)

    print("🎯 Replaying audio with V13 tracker")
    print(f"   Audio:  {audio_path}")
    print(f"   Script: {script_path if script_path.exists() else 'from ground truth'}")
    print(f"   Words:  {len(word_timings)} timings / {len(script_text.split())} script tokens")

    tracker = V13SherpaAnchoredVAD(word_timings, script_text, debug=not args.quiet)
    recognizer, stream = build_recognizer(model_dir)

    samples = stream_audio(
        tracker=tracker,
        recognizer=recognizer,
        stream=stream,
        audio_path=audio_path,
        word_timings=word_timings,
        chunk_ms=args.chunk_ms,
    )

    summarize(samples, tracker)

    if args.save_events:
        save_path = args.save_events.expanduser()
        save_path.parent.mkdir(parents=True, exist_ok=True)
        with save_path.open("w") as f:
            json.dump([s.__dict__ for s in samples], f, indent=2)
        print(f"\n💾 Saved events to {save_path}")


def load_ground_truth(path: Path) -> Dict:
    with path.open() as f:
        return json.load(f)


def extract_word_timings(data: Dict) -> List[Dict]:
    key = 'word_timings' if 'word_timings' in data else 'words'
    if key not in data:
        raise ValueError("Ground-truth JSON must contain 'word_timings' or 'words'.")

    word_entries = data[key]
    timings = []
    for entry in word_entries:
        timings.append({
            "word": entry.get("word") or entry.get("text") or "",
            "start": float(entry.get("start", entry.get("begin", 0.0))),
            "end": float(entry.get("end", entry.get("finish", entry.get("stop", 0.0)))),
        })
    return timings


def load_script_text(script_path: Path, data: Dict) -> str:
    if script_path.exists():
        return script_path.read_text().strip()
    if "text" in data and data["text"].strip():
        return data["text"].strip()
    return " ".join(entry["word"] for entry in data.get("words", []))


def build_recognizer(model_dir: Path):
    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=str(model_dir / "tokens.txt"),
        encoder=str(model_dir / "encoder-epoch-99-avg-1-chunk-16-left-128.onnx"),
        decoder=str(model_dir / "decoder-epoch-99-avg-1-chunk-16-left-128.onnx"),
        joiner=str(model_dir / "joiner-epoch-99-avg-1-chunk-16-left-128.onnx"),
        num_threads=4,
        sample_rate=16000,
        feature_dim=80,
        decoding_method="greedy_search",
    )
    return recognizer, recognizer.create_stream()


def stream_audio(
    tracker: V13SherpaAnchoredVAD,
    recognizer,
    stream,
    audio_path: Path,
    word_timings: List[Dict],
    chunk_ms: float,
) -> List[TrackingSample]:
    samples: List[TrackingSample] = []
    with wave.open(str(audio_path), 'rb') as wf:
        sample_rate = wf.getframerate()
        chunk_size = max(1, int(sample_rate * (chunk_ms / 1000.0)))
        audio_time = 0.0
        frame_duration = chunk_size / sample_rate
        frame_idx = 0

        print(f"\n🎧 Streaming audio ({sample_rate} Hz, chunk {chunk_size} samples)")

        while True:
            frames = wf.readframes(chunk_size)
            if not frames:
                break

            audio_chunk = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
            stream.accept_waveform(sample_rate, audio_chunk)

            while recognizer.is_ready(stream):
                recognizer.decode_stream(stream)

            result = recognizer.get_result(stream)
            sherpa_text = extract_result_text(result)

            est_time, word_idx, _, source, confidence = tracker.update(
                audio_chunk, audio_time, sherpa_text
            )
            true_word_idx = find_true_word_index(word_timings, audio_time)
            drift = word_idx - true_word_idx

            samples.append(TrackingSample(
                audio_time=audio_time,
                word_index=word_idx,
                true_word_index=true_word_idx,
                drift=drift,
                source=source,
                confidence=confidence,
                sherpa_text=sherpa_text,
            ))

            if source != 'hold':
                print(f"[{audio_time:6.2f}s] {source:>18} → idx {word_idx:02d} "
                      f"(true {true_word_idx:02d}, drift {drift:+d}) "
                      f"| sherpa='{sherpa_text}'")

            audio_time += frame_duration
            frame_idx += 1

        stream.input_finished()
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)

    return samples


def extract_result_text(result) -> str:
    if not result:
        return ""
    if isinstance(result, str):
        return result.strip()
    if hasattr(result, "text"):
        return result.text.strip()
    return str(result).strip()


def find_true_word_index(word_timings: List[Dict], audio_time: float) -> int:
    if not word_timings:
        return 0

    # Direct containment check
    for idx, timing in enumerate(word_timings):
        start = timing["start"]
        end = timing["end"]
        if start <= audio_time <= end:
            return idx
        if audio_time < start:
            return max(0, idx - 1)

    # Past last word → clamp to final index
    return len(word_timings) - 1


def summarize(samples: List[TrackingSample], tracker: V13SherpaAnchoredVAD):
    if not samples:
        print("⚠️  No samples captured.")
        return

    max_drift_sample: Optional[TrackingSample] = max(
        samples, key=lambda s: abs(s.drift), default=None
    )

    print("\n📊 Summary")
    print("──────────")
    print(f"Total frames:        {len(samples)}")
    print(f"Final word index:    {samples[-1].word_index}")
    print(f"Sherpa anchors:      {tracker.sherpa_anchors}")
    print(f"Sherpa corrections:  {tracker.sherpa_corrections}")
    print(f"VAD predictions:     {tracker.vad_predictions}")

    if max_drift_sample:
        print(f"Max drift:           {max_drift_sample.drift:+d} words "
              f"at {max_drift_sample.audio_time:.2f}s "
              f"(source={max_drift_sample.source})")


if __name__ == "__main__":
    main()

