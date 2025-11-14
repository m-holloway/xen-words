#!/usr/bin/env python3
"""
Test alternative alignment methods that might work better than VAD+Syllable.
"""

import json
import numpy as np
import librosa
from scipy.spatial.distance import euclidean
from fastdtw import fastdtw


def simple_time_based_alignment(audio_path, ground_truth_data):
    """
    Simplest possible approach: assume constant word rate.
    """
    print("\n🕐 Testing: Simple Time-Based Alignment")
    print("=" * 60)
    
    audio, sr = librosa.load(audio_path, sr=16000)
    audio_duration = len(audio) / sr
    
    script_words = ground_truth_data['script_words']
    word_timings = ground_truth_data['word_timings']
    num_words = len(script_words)
    
    # Assume words are evenly spaced
    words_per_second = num_words / audio_duration
    
    errors = []
    for wt in word_timings[:20]:
        if wt['script_index'] is not None:
            # Estimate time for this word index
            estimated_time = wt['script_index'] / words_per_second
            true_time = wt['start']
            error = abs(estimated_time - true_time)
            errors.append(error)
    
    mean_error = np.mean(errors)
    within_500ms = sum(1 for e in errors if e < 0.5) / len(errors) * 100
    
    print(f"Mean Error: {mean_error:.3f}s")
    print(f"Within 500ms: {within_500ms:.1f}%")
    
    if mean_error < 0.5:
        print("👍 This actually works better than VAD+Syllable!")
    else:
        print("❌ Still not good enough")
    
    return mean_error


def whisper_direct_alignment(ground_truth_data):
    """
    Just use Whisper's timestamps directly (the 'cheating' baseline).
    """
    print("\n🎤 Testing: Whisper Direct (Ground Truth)")
    print("=" * 60)
    
    word_timings = ground_truth_data['word_timings']
    
    # Perfect alignment (error = 0) since this IS the ground truth
    print("Mean Error: 0.000s (by definition)")
    print("Within 500ms: 100.0%")
    print("\n💡 This shows what PERFECT alignment looks like")
    print("   But it's not real-time - Whisper needs full audio")
    
    return 0.0


def pause_based_alignment(audio_path, ground_truth_data):
    """
    Detect word boundaries using pauses in audio.
    """
    print("\n⏸️  Testing: Pause-Based Word Detection")
    print("=" * 60)
    
    audio, sr = librosa.load(audio_path, sr=16000)
    script_words = ground_truth_data['script_words']
    word_timings = ground_truth_data['word_timings']
    
    # Detect pauses using RMS energy
    frame_length = int(sr * 0.025)  # 25ms
    hop_length = int(sr * 0.010)    # 10ms
    
    rms = librosa.feature.rms(y=audio, frame_length=frame_length, hop_length=hop_length)[0]
    
    # Find low energy regions (pauses)
    threshold = np.percentile(rms, 25)  # Bottom 25% = pauses
    is_pause = rms < threshold
    
    # Find pause boundaries
    word_boundaries = []
    in_pause = False
    pause_start = 0
    
    for i, pause in enumerate(is_pause):
        time = i * hop_length / sr
        
        if pause and not in_pause:
            # Start of pause
            in_pause = True
            pause_start = time
        elif not pause and in_pause:
            # End of pause = start of new word
            in_pause = False
            if time - pause_start > 0.05:  # Min 50ms pause
                word_boundaries.append(time)
    
    print(f"Detected {len(word_boundaries)} word boundaries")
    print(f"Expected ~{len(word_timings)} words")
    
    # Match boundaries to words
    errors = []
    for wt in word_timings[:20]:
        if wt['script_index'] is not None:
            true_time = wt['start']
            
            # Find closest boundary
            if word_boundaries:
                closest = min(word_boundaries, key=lambda x: abs(x - true_time))
                error = abs(closest - true_time)
                errors.append(error)
    
    if errors:
        mean_error = np.mean(errors)
        within_500ms = sum(1 for e in errors if e < 0.5) / len(errors) * 100
        
        print(f"Mean Error: {mean_error:.3f}s")
        print(f"Within 500ms: {within_500ms:.1f}%")
        
        if mean_error < 0.5:
            print("👍 Pause detection works reasonably well!")
        else:
            print("❌ Still not accurate enough")
        
        return mean_error
    
    return 999.0


def main():
    print("=" * 60)
    print("🧪 TESTING ALTERNATIVE METHODS")
    print("=" * 60)
    
    # Load ground truth
    with open('ground_truth_timings.json', 'r') as f:
        ground_truth = json.load(f)
    
    audio_file = "audio/adalyn_reading_background.wav"
    
    results = {}
    
    # Test methods
    results['whisper_direct'] = whisper_direct_alignment(ground_truth)
    results['simple_time'] = simple_time_based_alignment(audio_file, ground_truth)
    results['pause_based'] = pause_based_alignment(audio_file, ground_truth)
    
    # Compare
    print("\n" + "=" * 60)
    print("📊 COMPARISON")
    print("=" * 60)
    
    print(f"\nMethod Performance (Mean Error):")
    for method, error in sorted(results.items(), key=lambda x: x[1]):
        grade = "🎉" if error < 0.3 else "👍" if error < 0.5 else "⚠️" if error < 1.0 else "❌"
        print(f"  {grade} {method:20s}: {error:.3f}s")
    
    print(f"\n💡 FINDINGS:")
    
    best_practical = min(k for k, v in results.items() if k != 'whisper_direct'), min(v for k, v in results.items() if k != 'whisper_direct')
    
    if best_practical[1] < 0.5:
        print(f"   ✅ {best_practical[0]} is viable ({best_practical[1]:.3f}s error)")
        print(f"   Can be implemented in Flutter")
    else:
        print(f"   ❌ NO METHOD achieves acceptable accuracy!")
        print(f"   Best is {best_practical[0]} with {best_practical[1]:.3f}s error")
        print(f"\n   🤔 RECOMMENDATIONS:")
        print(f"   1. Use lightweight STT (Whisper streaming?) for anchors")
        print(f"   2. Interpolate between anchors")
        print(f"   3. Accept that perfect real-time tracking is hard!")
        print(f"   4. Consider showing word AFTER it's spoken (not before)")


if __name__ == "__main__":
    main()

