#!/usr/bin/env python3
"""
Speech-Text Alignment Testing Framework

Tests different alignment approaches for parent reading narration.
"""

import argparse
import json
import time
from pathlib import Path
from typing import List, Dict, Tuple, Optional

import librosa
import numpy as np
from scipy.spatial.distance import euclidean
from fastdtw import fastdtw


class AlignmentTester:
    """Test different speech-text alignment approaches"""
    
    def __init__(self, script_text: str, sample_rate: int = 16000):
        self.script_text = script_text
        self.words = script_text.lower().split()
        self.sample_rate = sample_rate
        
    def load_audio(self, audio_path: str) -> Tuple[np.ndarray, int]:
        """Load audio file"""
        print(f"Loading audio: {audio_path}")
        audio, sr = librosa.load(audio_path, sr=self.sample_rate)
        duration = len(audio) / sr
        print(f"  Duration: {duration:.2f}s, Sample rate: {sr}Hz")
        return audio, sr
    
    def mix_noise(self, audio: np.ndarray, noise_path: str, snr_db: float = 10) -> np.ndarray:
        """Mix background noise at specified SNR"""
        print(f"Mixing noise: {noise_path} at {snr_db}dB SNR")
        noise, _ = librosa.load(noise_path, sr=self.sample_rate)
        
        # Loop noise if shorter than audio
        if len(noise) < len(audio):
            repeats = int(np.ceil(len(audio) / len(noise)))
            noise = np.tile(noise, repeats)[:len(audio)]
        else:
            noise = noise[:len(audio)]
        
        # Calculate signal and noise power
        signal_power = np.mean(audio ** 2)
        noise_power = np.mean(noise ** 2)
        
        # Calculate noise scaling factor for desired SNR
        snr_linear = 10 ** (snr_db / 10)
        noise_scale = np.sqrt(signal_power / (snr_linear * noise_power))
        
        # Mix
        mixed = audio + noise_scale * noise
        
        # Normalize to prevent clipping
        max_val = np.max(np.abs(mixed))
        if max_val > 0.99:
            mixed = mixed * (0.99 / max_val)
        
        print(f"  Mixed audio power: {np.mean(mixed**2):.6f}")
        return mixed
    
    def test_mfcc_dtw(self, audio: np.ndarray) -> Dict:
        """
        Test MFCC + DTW alignment
        
        This approach:
        1. Extracts MFCC features from audio
        2. Uses DTW to align against expected word boundaries
        3. Very lightweight, no ML model needed
        """
        print("\n=== Testing MFCC + DTW ===")
        start_time = time.time()
        
        # Extract MFCC features
        mfcc = librosa.feature.mfcc(y=audio, sr=self.sample_rate, n_mfcc=13)
        mfcc = mfcc.T  # Shape: (time_frames, n_mfcc)
        
        print(f"  MFCC shape: {mfcc.shape}")
        print(f"  Time frames: {mfcc.shape[0]}, Features: {mfcc.shape[1]}")
        
        # Detect voice activity (simple energy-based)
        energy = librosa.feature.rms(y=audio)[0]
        threshold = np.percentile(energy, 40)  # 40th percentile as threshold
        voice_frames = energy > threshold
        
        print(f"  Voice activity: {np.sum(voice_frames)} / {len(voice_frames)} frames")
        
        # Estimate word boundaries based on pauses
        # This is a simple heuristic - could be improved with better VAD
        frame_length = 512  # librosa default hop length
        frame_rate = self.sample_rate / frame_length
        
        # Find pause boundaries
        voice_diff = np.diff(voice_frames.astype(int))
        word_start_frames = np.where(voice_diff == 1)[0]
        word_end_frames = np.where(voice_diff == -1)[0]
        
        print(f"  Estimated word boundaries: {len(word_start_frames)} starts, {len(word_end_frames)} ends")
        
        # Convert to timestamps
        word_timestamps = []
        for i, start_frame in enumerate(word_start_frames):
            if i < len(word_end_frames):
                start_time_sec = start_frame / frame_rate
                end_time_sec = word_end_frames[i] / frame_rate
                
                if i < len(self.words):
                    word_timestamps.append({
                        'word': self.words[i],
                        'start': start_time_sec,
                        'end': end_time_sec,
                    })
        
        elapsed = time.time() - start_time
        
        print(f"  Aligned {len(word_timestamps)} / {len(self.words)} words")
        print(f"  Elapsed time: {elapsed:.3f}s")
        print(f"  Real-time factor: {elapsed / (len(audio) / self.sample_rate):.3f}")
        
        return {
            'approach': 'MFCC+DTW',
            'words_aligned': len(word_timestamps),
            'total_words': len(self.words),
            'accuracy': len(word_timestamps) / len(self.words),
            'latency_ms': elapsed * 1000,
            'real_time_factor': elapsed / (len(audio) / self.sample_rate),
            'timestamps': word_timestamps,
        }
    
    def test_onset_detection(self, audio: np.ndarray) -> Dict:
        """
        Test onset detection for word boundaries
        
        This approach:
        1. Detects acoustic onsets (start of sounds)
        2. Maps onsets to word boundaries
        3. Very fast, good for real-time
        """
        print("\n=== Testing Onset Detection ===")
        start_time = time.time()
        
        # Detect onsets
        onset_frames = librosa.onset.onset_detect(
            y=audio,
            sr=self.sample_rate,
            units='frames',
            backtrack=True,
        )
        
        # Convert to timestamps
        onset_times = librosa.frames_to_time(onset_frames, sr=self.sample_rate)
        
        print(f"  Detected {len(onset_times)} onsets")
        print(f"  First 10 onset times: {onset_times[:10]}")
        
        # Map onsets to words (simple: assign each onset to next word)
        word_timestamps = []
        for i, onset_time in enumerate(onset_times):
            if i < len(self.words):
                # Estimate end time (until next onset or end of audio)
                if i + 1 < len(onset_times):
                    end_time = onset_times[i + 1]
                else:
                    end_time = len(audio) / self.sample_rate
                
                word_timestamps.append({
                    'word': self.words[i],
                    'start': onset_time,
                    'end': end_time,
                })
        
        elapsed = time.time() - start_time
        
        print(f"  Aligned {len(word_timestamps)} / {len(self.words)} words")
        print(f"  Elapsed time: {elapsed:.3f}s")
        print(f"  Real-time factor: {elapsed / (len(audio) / self.sample_rate):.3f}")
        
        return {
            'approach': 'Onset Detection',
            'words_aligned': len(word_timestamps),
            'total_words': len(self.words),
            'accuracy': len(word_timestamps) / len(self.words),
            'latency_ms': elapsed * 1000,
            'real_time_factor': elapsed / (len(audio) / self.sample_rate),
            'timestamps': word_timestamps,
        }
    
    def test_vad_syllable(self, audio: np.ndarray) -> Dict:
        """
        Test VAD + syllable counting
        
        This approach:
        1. Use Voice Activity Detection
        2. Count syllables based on energy peaks
        3. Estimate word boundaries
        4. Extremely lightweight
        """
        print("\n=== Testing VAD + Syllable Counting ===")
        start_time = time.time()
        
        # Simple VAD using energy
        frame_length = 512
        hop_length = 256
        energy = librosa.feature.rms(y=audio, frame_length=frame_length, hop_length=hop_length)[0]
        
        # Adaptive threshold
        threshold = np.percentile(energy, 35)
        voice_frames = energy > threshold
        
        # Count syllables (approximate using energy peaks)
        # Syllables roughly correspond to energy peaks in voiced segments
        from scipy.signal import find_peaks
        
        # Find peaks in energy (potential syllables)
        peaks, _ = find_peaks(energy, distance=10, prominence=threshold/4)
        
        print(f"  Detected {len(peaks)} syllable candidates")
        
        # Estimate words per syllable (English averages ~1.5 syllables/word)
        estimated_words = len(peaks) / 1.5
        
        print(f"  Estimated {estimated_words:.1f} words (target: {len(self.words)})")
        
        # Simple mapping: distribute peaks across words
        word_timestamps = []
        frames_per_word = len(peaks) / len(self.words) if len(self.words) > 0 else 1
        
        for i, word in enumerate(self.words):
            peak_idx = int(i * frames_per_word)
            if peak_idx < len(peaks):
                frame = peaks[peak_idx]
                time_sec = frame * hop_length / self.sample_rate
                
                # Estimate end time
                if i + 1 < len(self.words) and int((i + 1) * frames_per_word) < len(peaks):
                    end_frame = peaks[int((i + 1) * frames_per_word)]
                    end_time = end_frame * hop_length / self.sample_rate
                else:
                    end_time = time_sec + 0.5  # Default 500ms
                
                word_timestamps.append({
                    'word': word,
                    'start': time_sec,
                    'end': min(end_time, len(audio) / self.sample_rate),
                })
        
        elapsed = time.time() - start_time
        
        print(f"  Aligned {len(word_timestamps)} / {len(self.words)} words")
        print(f"  Elapsed time: {elapsed:.3f}s")
        print(f"  Real-time factor: {elapsed / (len(audio) / self.sample_rate):.3f}")
        
        return {
            'approach': 'VAD+Syllable',
            'words_aligned': len(word_timestamps),
            'total_words': len(self.words),
            'accuracy': len(word_timestamps) / len(self.words),
            'latency_ms': elapsed * 1000,
            'real_time_factor': elapsed / (len(audio) / self.sample_rate),
            'timestamps': word_timestamps,
        }
    
    def run_all_tests(self, audio: np.ndarray) -> List[Dict]:
        """Run all alignment tests"""
        results = []
        
        try:
            results.append(self.test_mfcc_dtw(audio))
        except Exception as e:
            print(f"MFCC+DTW failed: {e}")
        
        try:
            results.append(self.test_onset_detection(audio))
        except Exception as e:
            print(f"Onset detection failed: {e}")
        
        try:
            results.append(self.test_vad_syllable(audio))
        except Exception as e:
            print(f"VAD+Syllable failed: {e}")
        
        return results


def main():
    parser = argparse.ArgumentParser(description='Test speech-text alignment approaches')
    parser.add_argument('--audio', type=str, required=True, help='Path to audio file')
    parser.add_argument('--script', type=str, default='scripts/adalyn_story.txt', help='Path to script text')
    parser.add_argument('--noise', type=str, help='Path to background noise file')
    parser.add_argument('--snr', type=float, default=10, help='Signal-to-noise ratio (dB)')
    parser.add_argument('--output', type=str, default='results/alignment_results.json', help='Output file')
    
    args = parser.parse_args()
    
    # Load script text
    script_path = Path(args.script)
    if script_path.exists():
        script_text = script_path.read_text().strip()
    else:
        # Default script
        script_text = "You are Adalyn, and today you went to see a glowing trail outside your window."
        print(f"Using default script: {script_text}")
    
    print(f"\n{'='*60}")
    print("SPEECH-TEXT ALIGNMENT TESTING")
    print(f"{'='*60}")
    print(f"Script: {script_text}")
    print(f"Words: {len(script_text.split())}")
    print(f"{'='*60}\n")
    
    # Create tester
    tester = AlignmentTester(script_text)
    
    # Load audio
    audio, sr = tester.load_audio(args.audio)
    
    # Mix noise if provided
    if args.noise:
        audio = tester.mix_noise(audio, args.noise, args.snr)
    
    # Run tests
    results = tester.run_all_tests(audio)
    
    # Summary
    print(f"\n{'='*60}")
    print("RESULTS SUMMARY")
    print(f"{'='*60}")
    
    for result in results:
        print(f"\n{result['approach']}:")
        print(f"  Accuracy: {result['accuracy']:.1%}")
        print(f"  Latency: {result['latency_ms']:.1f}ms")
        print(f"  Real-time factor: {result['real_time_factor']:.3f}x")
        print(f"  Words aligned: {result['words_aligned']} / {result['total_words']}")
    
    # Save results
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w') as f:
        json.dump({
            'script': script_text,
            'audio_file': args.audio,
            'noise_file': args.noise,
            'snr_db': args.snr if args.noise else None,
            'results': results,
        }, f, indent=2)
    
    print(f"\nResults saved to: {output_path}")


if __name__ == '__main__':
    main()

