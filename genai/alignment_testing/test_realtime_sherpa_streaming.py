#!/usr/bin/env python3
"""
Real-Time Sherpa-ONNX Streaming Test

Tests phoneme-level alignment EXACTLY as it will run in the app:
1. Uses the SAME Sherpa model (sherpa-onnx-streaming-zipformer-en-2023-06-26)
2. Streams audio in real-time chunks (simulating live microphone input)
3. Processes partial results as they arrive
4. Runs phoneme alignment on each partial
5. Measures real-time latency and accuracy
"""

import sherpa_onnx
import numpy as np
import wave
import json
import time
from pathlib import Path
from typing import List, Tuple, Dict
import sys

sys.path.append('.')
from test_phonetic_matching import word_to_phonemes, VOWELS

# ============================================================
# CONFIGURATION (Match your Flutter app)
# ============================================================

SHERPA_MODEL_DIR = "sherpa-onnx-streaming-zipformer-en-2023-06-26"
SAMPLE_RATE = 16000
CHUNK_DURATION_MS = 100  # 100ms chunks (matches typical streaming)
CHUNK_SIZE = int(SAMPLE_RATE * CHUNK_DURATION_MS / 1000)  # 1600 samples

# ============================================================
# PHONEME ALIGNMENT (Same as validated algorithm)
# ============================================================

def text_to_phonemes(text: str):
    """Convert text to phonemes with word boundaries."""
    words = text.lower().split()
    phonemes = []
    boundaries = [0]
    
    for word in words:
        ph = word_to_phonemes(word)
        phonemes.extend(ph)
        boundaries.append(len(phonemes))
    
    return phonemes, boundaries[:-1], words

def phoneme_similarity(p1: str, p2: str) -> float:
    """Phoneme similarity score."""
    if p1 == p2:
        return 1.0
    
    vowels = set(VOWELS)
    
    # Voiced/voiceless pairs
    if (p1, p2) in [('P','B'), ('B','P'), ('T','D'), ('D','T'), 
                     ('K','G'), ('G','K'), ('F','V'), ('V','F'),
                     ('S','Z'), ('Z','S'), ('TH','DH'), ('DH','TH')]:
        return 0.9
    
    # Same class
    if p1 in vowels and p2 in vowels:
        return 0.75
    
    return 0.3

def align_phonemes(detected: List[str], script: List[str], boundaries: List[int]) -> Tuple[int, float]:
    """Fuzzy phoneme alignment (sliding window)."""
    if not detected:
        return 0, 0.0
    
    recent = detected[-15:]  # Last 15 phonemes
    best_word, best_score = 0, 0.0
    
    for w_idx in range(len(boundaries)):
        start = boundaries[w_idx]
        score, end_ph = score_match(recent, script, start)
        
        if score > best_score:
            best_score = score
            for i in range(len(boundaries) - 1, -1, -1):
                if end_ph >= boundaries[i]:
                    best_word = i
                    break
    
    return best_word, best_score

def score_match(detected: List[str], script: List[str], start: int) -> Tuple[float, int]:
    """Score alignment at position."""
    total, d_idx, s_idx, last_s = 0.0, 0, start, start
    
    while d_idx < len(detected) and s_idx < len(script):
        sim = phoneme_similarity(detected[d_idx], script[s_idx])
        
        if sim > 0.7:
            total += sim
            last_s = s_idx
            d_idx += 1
            s_idx += 1
        elif sim > 0.5:
            total += sim * 0.8
            last_s = s_idx
            d_idx += 1
            s_idx += 1
        else:
            d_idx += 1
    
    return (total / len(detected)) if detected else 0.0, last_s

# ============================================================
# SHERPA-ONNX STREAMING RECOGNIZER
# ============================================================

def create_sherpa_recognizer(model_dir: str):
    """
    Create Sherpa-ONNX recognizer with the SAME model as Flutter app.
    
    Model: sherpa-onnx-streaming-zipformer-en-2023-06-26
    """
    if not Path(model_dir).exists():
        print(f"❌ Model not found: {model_dir}")
        print(f"\n📥 Please download the model:")
        print(f"   wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/{model_dir}.tar.bz2")
        print(f"   tar -xf {model_dir}.tar.bz2")
        return None
    
    model_path = Path(model_dir)
    
    config = sherpa_onnx.OnlineRecognizerConfig(
        model_config=sherpa_onnx.OnlineModelConfig(
            transducer=sherpa_onnx.OnlineTransducerModelConfig(
                encoder=str(model_path / "encoder-epoch-99-avg-1.onnx"),
                decoder=str(model_path / "decoder-epoch-99-avg-1.onnx"),
                joiner=str(model_path / "joiner-epoch-99-avg-1.onnx"),
            ),
            tokens=str(model_path / "tokens.txt"),
            num_threads=4,
        ),
        decoding_method="greedy_search",
        max_active_paths=4,
    )
    
    return sherpa_onnx.OnlineRecognizer(config)

# ============================================================
# REAL-TIME STREAMING SIMULATION
# ============================================================

class RealtimeStreamingTest:
    """Simulates real-time audio streaming as in the Flutter app."""
    
    def __init__(self, recognizer, script_text: str):
        self.recognizer = recognizer
        self.script_text = script_text
        
        # Prepare script
        self.script_phonemes, self.word_boundaries, self.script_words = text_to_phonemes(script_text)
        
        # State
        self.cumulative_phonemes = []
        self.current_word_idx = 0
        self.events = []  # Track all events with timestamps
        
    def stream_audio_file(self, audio_path: str, ground_truth_path: str = None):
        """
        Stream audio file in real-time chunks, exactly as app would do.
        
        Returns: Test results with timing and accuracy
        """
        print(f"\n{'='*60}")
        print(f"🎤 STREAMING: {Path(audio_path).name}")
        print(f"{'='*60}\n")
        
        # Load ground truth for comparison
        ground_truth = None
        if ground_truth_path and Path(ground_truth_path).exists():
            with open(ground_truth_path) as f:
                ground_truth = json.load(f)
            print(f"✅ Loaded ground truth: {len(ground_truth['words'])} words")
        
        print(f"📜 Script: {len(self.script_words)} words")
        print(f"   \"{self.script_text[:80]}...\"")
        
        # Load audio
        with wave.open(audio_path, 'rb') as wf:
            assert wf.getnchannels() == 1, "Audio must be mono"
            assert wf.getsampwidth() == 2, "Audio must be 16-bit"
            sample_rate = wf.getframerate()
            
            if sample_rate != SAMPLE_RATE:
                print(f"⚠️  Sample rate {sample_rate} != {SAMPLE_RATE}, may need resampling")
            
            audio_data = wf.readframes(wf.getnframes())
            samples = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
        
        total_duration = len(samples) / sample_rate
        print(f"⏱️  Duration: {total_duration:.2f}s")
        
        # Create stream
        stream = self.recognizer.create_stream()
        
        print(f"\n🎯 Starting real-time streaming...")
        print(f"   Chunk size: {CHUNK_DURATION_MS}ms ({CHUNK_SIZE} samples)")
        
        start_time = time.time()
        last_text = ""
        chunk_count = 0
        
        # Stream in chunks (simulating real-time microphone input)
        for i in range(0, len(samples), CHUNK_SIZE):
            chunk = samples[i:i+CHUNK_SIZE]
            
            # Feed to Sherpa (as app does)
            stream.accept_waveform(SAMPLE_RATE, chunk)
            
            # Get partial result (as app does)
            while self.recognizer.is_ready(stream):
                self.recognizer.decode_stream(stream)
            
            current_text = self.recognizer.get_result(stream).text.strip()
            
            # Only process when text changes (as app does)
            if current_text != last_text and current_text:
                processing_start = time.time()
                
                # Phonemize the new text
                detected_phonemes, _, _ = text_to_phonemes(current_text)
                self.cumulative_phonemes = detected_phonemes  # Update cumulative
                
                # Align to script
                predicted_word_idx, confidence = align_phonemes(
                    self.cumulative_phonemes,
                    self.script_phonemes,
                    self.word_boundaries
                )
                
                processing_time = (time.time() - processing_start) * 1000  # ms
                audio_time = i / sample_rate  # Time in audio when this chunk was processed
                
                # Record event
                event = {
                    'chunk': chunk_count,
                    'audio_time': audio_time,
                    'wall_time': time.time() - start_time,
                    'sherpa_text': current_text,
                    'predicted_word_idx': predicted_word_idx,
                    'predicted_word': self.script_words[predicted_word_idx] if predicted_word_idx < len(self.script_words) else '?',
                    'confidence': confidence,
                    'processing_ms': processing_time,
                    'phonemes_detected': len(detected_phonemes)
                }
                
                self.events.append(event)
                
                # Print update
                print(f"   [{audio_time:5.2f}s] \"{current_text[:40]}...\" "
                      f"→ word {predicted_word_idx} (\"{event['predicted_word']}\") "
                      f"[{processing_time:.1f}ms]")
                
                last_text = current_text
                chunk_count += 1
        
        # Final result
        stream.input_finished()
        while self.recognizer.is_ready(stream):
            self.recognizer.decode_stream(stream)
        
        final_text = self.recognizer.get_result(stream).text.strip()
        
        total_time = time.time() - start_time
        
        print(f"\n✅ Streaming complete")
        print(f"   Total time: {total_time:.2f}s (audio: {total_duration:.2f}s)")
        print(f"   Realtime factor: {total_duration/total_time:.2f}x")
        print(f"   Updates: {len(self.events)}")
        
        # Analyze results
        return self.analyze_results(ground_truth, final_text)
    
    def analyze_results(self, ground_truth: Dict, final_sherpa_text: str):
        """Analyze streaming results vs ground truth."""
        print(f"\n{'='*60}")
        print(f"📊 ANALYSIS")
        print(f"{'='*60}\n")
        
        print(f"🎤 Final Sherpa Output:")
        print(f"   \"{final_sherpa_text}\"")
        
        if ground_truth:
            gt_text = ' '.join([w['word'] for w in ground_truth['words']])
            print(f"\n✅ Ground Truth (Whisper):")
            print(f"   \"{gt_text}\"")
            
            # Compare
            sherpa_words = final_sherpa_text.lower().split()
            gt_words = [w['word'].lower() for w in ground_truth['words']]
            
            print(f"\n📈 Transcription Quality:")
            print(f"   Sherpa words: {len(sherpa_words)}")
            print(f"   Ground truth words: {len(gt_words)}")
            
            # Word Error Rate (WER)
            # Simple approximation: count differences
            matches = sum(1 for s, g in zip(sherpa_words, gt_words) if s == g)
            wer = 1 - (matches / max(len(sherpa_words), len(gt_words)))
            print(f"   Word match: {matches}/{len(gt_words)} ({100*(1-wer):.1f}%)")
            print(f"   WER: {100*wer:.1f}%")
        
        # Alignment performance
        print(f"\n📈 Alignment Performance:")
        print(f"   Total updates: {len(self.events)}")
        
        if self.events:
            processing_times = [e['processing_ms'] for e in self.events]
            print(f"   Processing latency:")
            print(f"     Mean: {np.mean(processing_times):.1f}ms")
            print(f"     Median: {np.median(processing_times):.1f}ms")
            print(f"     95th percentile: {np.percentile(processing_times, 95):.1f}ms")
            print(f"     Max: {np.max(processing_times):.1f}ms")
            
            confidences = [e['confidence'] for e in self.events]
            print(f"   Confidence:")
            print(f"     Mean: {np.mean(confidences):.2f}")
            print(f"     Min: {np.min(confidences):.2f}")
            
            # Check if we stayed under 120ms target
            over_120ms = sum(1 for t in processing_times if t > 120)
            print(f"\n⏱️  Latency target (<120ms):")
            if over_120ms == 0:
                print(f"   ✅ ALL updates under 120ms!")
            else:
                print(f"   ⚠️  {over_120ms}/{len(processing_times)} updates over 120ms ({100*over_120ms/len(processing_times):.1f}%)")
        
        # Position accuracy (if we have ground truth with timings)
        if ground_truth and 'word_timings' in ground_truth:
            print(f"\n📈 Position Accuracy:")
            self.analyze_position_accuracy(ground_truth)
        
        # Show progression
        print(f"\n📋 Word Tracking Progression:")
        for i, e in enumerate(self.events[:10]):
            print(f"   Update {i+1}: [{e['audio_time']:.2f}s] word {e['predicted_word_idx']} (\"{e['predicted_word']}\")")
        if len(self.events) > 10:
            print(f"   ... and {len(self.events) - 10} more updates")
        
        return {
            'events': self.events,
            'final_text': final_sherpa_text,
            'mean_latency_ms': np.mean(processing_times) if self.events else 0,
            'max_latency_ms': np.max(processing_times) if self.events else 0,
            'mean_confidence': np.mean(confidences) if self.events else 0,
        }
    
    def analyze_position_accuracy(self, ground_truth: Dict):
        """Analyze how accurately we tracked word positions over time."""
        # For each ground truth word, find when we predicted it
        # and compare to when it was actually spoken
        
        gt_words = [w['word'].lower() for w in ground_truth['word_timings']]
        
        # Build a map of when each script word should appear
        word_appear_times = {}
        for i, gt_word in enumerate(gt_words):
            # Find this word in script
            for script_idx, script_word in enumerate(self.script_words):
                if script_word.lower() == gt_word:
                    if script_idx not in word_appear_times:
                        word_appear_times[script_idx] = ground_truth['word_timings'][i]['start']
                    break
        
        # For each event, check if prediction was correct at that time
        correct_predictions = 0
        close_predictions = 0  # Within ±1 word
        
        for event in self.events:
            audio_time = event['audio_time']
            predicted_idx = event['predicted_word_idx']
            
            # What SHOULD we be highlighting at this audio time?
            expected_idx = 0
            for idx, appear_time in word_appear_times.items():
                if appear_time <= audio_time:
                    expected_idx = idx
            
            if predicted_idx == expected_idx:
                correct_predictions += 1
                close_predictions += 1
            elif abs(predicted_idx - expected_idx) <= 1:
                close_predictions += 1
        
        if self.events:
            accuracy = 100 * correct_predictions / len(self.events)
            close_accuracy = 100 * close_predictions / len(self.events)
            
            print(f"   Exact match: {correct_predictions}/{len(self.events)} ({accuracy:.1f}%)")
            print(f"   Within ±1 word: {close_predictions}/{len(self.events)} ({close_accuracy:.1f}%)")
            
            if close_accuracy >= 90:
                print(f"   ✅ EXCELLENT accuracy!")
            elif close_accuracy >= 80:
                print(f"   ⚠️  GOOD accuracy")
            else:
                print(f"   ❌ Needs improvement")

# ============================================================
# MAIN TEST
# ============================================================

def main():
    print("="*60)
    print("🧪 REAL-TIME SHERPA-ONNX STREAMING TEST")
    print("="*60)
    print("\nThis test simulates EXACTLY how alignment runs in your app:")
    print("- Same Sherpa model (streaming-zipformer-en-2023-06-26)")
    print("- Real-time streaming (100ms chunks)")
    print("- Partial results processing")
    print("- Phoneme alignment on each update")
    print("- Latency measurement")
    
    # Create recognizer
    print(f"\n📥 Loading Sherpa-ONNX model...")
    recognizer = create_sherpa_recognizer(SHERPA_MODEL_DIR)
    
    if not recognizer:
        print(f"\n❌ Cannot proceed without Sherpa model")
        print(f"\nTo download:")
        print(f"  cd genai/alignment_testing")
        print(f"  wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/{SHERPA_MODEL_DIR}.tar.bz2")
        print(f"  tar -xf {SHERPA_MODEL_DIR}.tar.bz2")
        return
    
    print(f"✅ Model loaded")
    
    # Test 1: Clean recording
    print(f"\n{'='*60}")
    print(f"TEST 1: CLEAN RECORDING")
    print(f"{'='*60}")
    
    script_path = "scripts/adalyn_story.txt"
    with open(script_path) as f:
        script = ' '.join(f.read().strip().split())
    
    audio_path = "../../test_audio/clean_recording.wav"
    gt_path = "clean_recording_gt.json"
    
    if not Path(audio_path).exists():
        print(f"⚠️  Audio file not found: {audio_path}")
        print(f"   Converting from M4A...")
        # TODO: Convert
    
    tester = RealtimeStreamingTest(recognizer, script)
    results_clean = tester.stream_audio_file(audio_path, gt_path)
    
    # Test 2: Noisy recording (if available)
    noisy_path = "../../test_audio/reading_with_noise.wav"
    if Path(noisy_path).exists():
        print(f"\n{'='*60}")
        print(f"TEST 2: NOISY RECORDING")
        print(f"{'='*60}")
        
        tester2 = RealtimeStreamingTest(recognizer, script)
        results_noisy = tester2.stream_audio_file(noisy_path)
    
    # Final verdict
    print(f"\n{'='*60}")
    print(f"🎯 FINAL VERDICT")
    print(f"{'='*60}\n")
    
    print(f"Clean Recording:")
    print(f"  Mean latency: {results_clean['mean_latency_ms']:.1f}ms")
    print(f"  Max latency: {results_clean['max_latency_ms']:.1f}ms")
    print(f"  Mean confidence: {results_clean['mean_confidence']:.2f}")
    
    if results_clean['max_latency_ms'] < 120:
        print(f"  ✅ Latency under 120ms target!")
    else:
        print(f"  ⚠️  Latency over 120ms target")
    
    print(f"\n💡 Next Steps:")
    if results_clean['max_latency_ms'] < 120 and results_clean['mean_confidence'] > 0.7:
        print(f"  ✅ Ready to port to Dart!")
        print(f"  → Implement PhonemeAligner class")
        print(f"  → Integrate with existing Sherpa service")
        print(f"  → Test in story reader")
    else:
        print(f"  ⚠️  Tune parameters first")
        print(f"  → Adjust phoneme similarity weights")
        print(f"  → Optimize window size")
        print(f"  → Re-test")

if __name__ == "__main__":
    main()

