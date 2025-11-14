#!/usr/bin/env python3
"""
Analyze the audio to understand why VAD+Syllable is failing so badly.
"""

import json
import numpy as np
import librosa
import matplotlib.pyplot as plt


def analyze_audio():
    """Analyze audio characteristics."""
    print("=" * 60)
    print("🔬 AUDIO ANALYSIS")
    print("=" * 60)
    
    # Load audio
    audio_file = "audio/adalyn_reading_background.wav"
    audio, sr = librosa.load(audio_file, sr=16000)
    
    print(f"\n📊 Basic Info:")
    print(f"   Duration: {len(audio)/sr:.2f}s")
    print(f"   Sample rate: {sr} Hz")
    print(f"   Samples: {len(audio)}")
    
    # Load ground truth
    with open('ground_truth_timings.json', 'r') as f:
        gt = json.load(f)
    
    word_timings = gt['word_timings']
    script_words = gt['script_words']
    
    print(f"\n📝 Script Info:")
    print(f"   Words in script: {len(script_words)}")
    print(f"   Words detected: {len(word_timings)}")
    print(f"   Duration: {word_timings[-1]['end']:.2f}s")
    
    # Calculate actual syllables per word
    total_syllables = 0
    syllable_counts = []
    
    for wt in word_timings[:20]:
        if wt['script_word']:
            # Estimate syllables (simple vowel counting)
            word = wt['script_word']
            vowels = sum(1 for c in word if c in 'aeiouy')
            syllables = max(1, vowels)
            syllable_counts.append(syllables)
            total_syllables += syllables
    
    if syllable_counts:
        avg_syllables = total_syllables / len(syllable_counts)
        print(f"\n🔢 Syllable Analysis (first 20 words):")
        print(f"   Total syllables: {total_syllables}")
        print(f"   Words: {len(syllable_counts)}")
        print(f"   Avg syllables/word: {avg_syllables:.2f}")
    
    # Analyze pauses between words
    pauses = []
    for i in range(1, min(20, len(word_timings))):
        pause = word_timings[i]['start'] - word_timings[i-1]['end']
        pauses.append(pause)
    
    if pauses:
        print(f"\n⏸️  Pause Analysis (between first 20 words):")
        print(f"   Mean pause: {np.mean(pauses):.3f}s")
        print(f"   Median pause: {np.median(pauses):.3f}s")
        print(f"   Max pause: {np.max(pauses):.3f}s")
        print(f"   Min pause: {np.min(pauses):.3f}s")
    
    # Analyze word durations
    durations = [wt['duration'] for wt in word_timings[:20]]
    if durations:
        print(f"\n⏱️  Word Duration Analysis (first 20 words):")
        print(f"   Mean duration: {np.mean(durations):.3f}s")
        print(f"   Median duration: {np.median(durations):.3f}s")
        print(f"   Max duration: {np.max(durations):.3f}s")
        print(f"   Min duration: {np.min(durations):.3f}s")
    
    # Calculate energy distribution
    frame_size = int(sr * 0.032)  # 32ms frames
    energies = []
    
    for i in range(0, len(audio) - frame_size, frame_size):
        frame = audio[i:i + frame_size]
        energy = np.sqrt(np.mean(frame**2))
        energies.append(energy)
    
    print(f"\n⚡ Energy Analysis:")
    print(f"   Mean energy: {np.mean(energies):.4f}")
    print(f"   Median energy: {np.median(energies):.4f}")
    print(f"   Max energy: {np.max(energies):.4f}")
    print(f"   75th percentile: {np.percentile(energies, 75):.4f}")
    print(f"   90th percentile: {np.percentile(energies, 90):.4f}")
    
    # Count "syllable-like" peaks using VAD approach
    threshold = np.percentile(energies, 75) if len(energies) > 5 else 0.01
    peak_count = 0
    last_peak_frame = -1000
    min_peak_distance_frames = int(0.15 / 0.032)  # 0.15s in frames
    
    for i, energy in enumerate(energies):
        if energy > threshold and (i - last_peak_frame) >= min_peak_distance_frames:
            peak_count += 1
            last_peak_frame = i
    
    print(f"\n📊 VAD Peak Detection:")
    print(f"   Threshold: {threshold:.4f}")
    print(f"   Peaks detected: {peak_count}")
    print(f"   Audio duration: {len(audio)/sr:.2f}s")
    print(f"   Words spoken: ~{len(word_timings)}")
    print(f"   Peaks per word: {peak_count / len(word_timings):.2f}")
    
    # DIAGNOSIS
    print("\n" + "=" * 60)
    print("🔍 DIAGNOSIS")
    print("=" * 60)
    
    if peak_count > len(word_timings) * 2:
        print(f"\n❌ PROBLEM: Too many peaks detected!")
        print(f"   Detected {peak_count} peaks for only {len(word_timings)} words")
        print(f"   This is {peak_count / len(word_timings):.1f}x too many!")
        print(f"\n💡 Root cause:")
        print(f"   - Background noise creating false peaks")
        print(f"   - Syllable detection too sensitive")
        print(f"   - Method not suitable for noisy environments")
    
    if np.mean(pauses) > 0.5:
        print(f"\n⚠️  Large pauses between words (avg: {np.mean(pauses):.2f}s)")
        print(f"   This makes syllable counting unreliable")
    
    print(f"\n💡 RECOMMENDATION:")
    print(f"   VAD+Syllable method is NOT suitable for this use case!")
    print(f"   Consider alternatives:")
    print(f"   1. Use Whisper timestamps directly (already accurate)")
    print(f"   2. Try phoneme-based alignment")
    print(f"   3. Use MFCC+DTW for acoustic matching")
    print(f"   4. Hybrid: Whisper for anchors + interpolation")


if __name__ == "__main__":
    analyze_audio()

