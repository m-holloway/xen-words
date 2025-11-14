#!/usr/bin/env python3
"""
Systematically tune alignment parameters to find optimal settings.
Tests multiple combinations and reports best configuration.
"""

import json
import numpy as np
import librosa
from pathlib import Path
from test_alignment_accuracy import VadSyllableAligner, load_ground_truth


def test_parameters(audio_path, ground_truth_data, params):
    """Test a specific parameter configuration."""
    # Load audio
    audio, sr = librosa.load(audio_path, sr=16000)
    script_words = ground_truth_data['script_words']
    word_timings = ground_truth_data['word_timings']
    
    # Create aligner with specific parameters
    aligner = VadSyllableAligner(script_words)
    aligner.syllables_per_word = params['syllables_per_word']
    aligner.min_peak_distance = params['min_peak_distance']
    aligner.energy_threshold = params['energy_threshold']
    
    # Run alignment
    times, positions = aligner.process_audio(audio)
    
    # Compare against ground truth
    errors = []
    latencies = []
    
    for wt in word_timings[:20]:  # First 20 words
        word = wt['word']
        true_time = wt['start']
        script_idx = wt['script_index']
        
        if script_idx is None:
            continue
        
        # Find when we estimated this word position
        estimated_time = None
        for t, pos in zip(times, positions):
            if pos >= script_idx:
                estimated_time = t
                break
        
        if estimated_time is not None:
            error = abs(estimated_time - true_time)
            latency = estimated_time - true_time
            
            errors.append(error)
            latencies.append(latency)
    
    if not errors:
        return None
    
    return {
        'mean_error': np.mean(errors),
        'median_error': np.median(errors),
        'std_dev': np.std(errors),
        'mean_latency': np.mean(latencies),
        'within_250ms': sum(1 for e in errors if e < 0.25) / len(errors) * 100,
        'within_500ms': sum(1 for e in errors if e < 0.5) / len(errors) * 100,
        'within_1s': sum(1 for e in errors if e < 1.0) / len(errors) * 100,
    }


def main():
    print("=" * 60)
    print("🎛️  PARAMETER TUNING")
    print("=" * 60)
    
    # Load data
    ground_truth_file = "ground_truth_timings.json"
    audio_file = "audio/adalyn_reading_background.wav"
    
    if not Path(ground_truth_file).exists():
        print(f"\n❌ Ground truth not found: {ground_truth_file}")
        return
    
    ground_truth = load_ground_truth(ground_truth_file)
    
    # Parameter grid to test
    syllables_per_word_values = [1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0]
    min_peak_distance_values = [0.10, 0.15, 0.20, 0.25]
    energy_threshold_values = [0.005, 0.01, 0.02, 0.03]
    
    print(f"\n📊 Testing {len(syllables_per_word_values)} syllable ratios...")
    print(f"   {len(min_peak_distance_values)} peak distances...")
    print(f"   {len(energy_threshold_values)} energy thresholds...")
    print(f"   Total combinations: {len(syllables_per_word_values) * len(min_peak_distance_values) * len(energy_threshold_values)}")
    
    best_result = None
    best_params = None
    all_results = []
    
    # Test all combinations
    for syl_per_word in syllables_per_word_values:
        for peak_dist in min_peak_distance_values:
            for energy_thresh in energy_threshold_values:
                params = {
                    'syllables_per_word': syl_per_word,
                    'min_peak_distance': peak_dist,
                    'energy_threshold': energy_thresh
                }
                
                result = test_parameters(audio_file, ground_truth, params)
                
                if result is not None:
                    result['params'] = params
                    all_results.append(result)
                    
                    # Track best (lowest mean error)
                    if best_result is None or result['mean_error'] < best_result['mean_error']:
                        best_result = result
                        best_params = params
                        
                        print(f"🎯 New best: syl={syl_per_word:.1f}, peak={peak_dist:.2f}, energy={energy_thresh:.3f}")
                        print(f"   Mean error: {result['mean_error']:.3f}s, Within 500ms: {result['within_500ms']:.1f}%")
    
    # Print results
    print("\n" + "=" * 60)
    print("🏆 BEST PARAMETERS FOUND")
    print("=" * 60)
    
    if best_result:
        print(f"\nOptimal Configuration:")
        print(f"  syllables_per_word: {best_params['syllables_per_word']}")
        print(f"  min_peak_distance: {best_params['min_peak_distance']}")
        print(f"  energy_threshold: {best_params['energy_threshold']}")
        
        print(f"\nPerformance:")
        print(f"  Mean Error: {best_result['mean_error']:.3f}s")
        print(f"  Median Error: {best_result['median_error']:.3f}s")
        print(f"  Std Dev: {best_result['std_dev']:.3f}s")
        print(f"  Mean Latency: {best_result['mean_latency']:.3f}s")
        
        print(f"\nAccuracy Thresholds:")
        print(f"  Within 250ms: {best_result['within_250ms']:.1f}%")
        print(f"  Within 500ms: {best_result['within_500ms']:.1f}%")
        print(f"  Within 1.0s:  {best_result['within_1s']:.1f}%")
        
        # Grade
        mean_error = best_result['mean_error']
        if mean_error < 0.3:
            print("\n🎉 EXCELLENT: Ready for production!")
        elif mean_error < 0.5:
            print("\n👍 GOOD: Acceptable for use")
        elif mean_error < 1.0:
            print("\n⚠️  FAIR: Needs more tuning")
        else:
            print("\n❌ POOR: Major issues remain")
        
        # Save results
        with open('tuning_results.json', 'w') as f:
            json.dump({
                'best_params': best_params,
                'best_result': {k: v for k, v in best_result.items() if k != 'params'},
                'all_results': [
                    {
                        'params': r['params'],
                        'mean_error': r['mean_error'],
                        'within_500ms': r['within_500ms']
                    }
                    for r in sorted(all_results, key=lambda x: x['mean_error'])[:10]
                ]
            }, f, indent=2)
        
        print(f"\n💾 Saved detailed results to: tuning_results.json")
    else:
        print("\n❌ No valid results found!")


if __name__ == "__main__":
    main()

