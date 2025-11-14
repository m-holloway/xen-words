#!/usr/bin/env python3
"""
Test alignment accuracy against ground truth word timings.
Measure how well our VAD+Syllable method performs in real-time.
"""

import json
import numpy as np
import librosa
from pathlib import Path
import matplotlib.pyplot as plt


class VadSyllableAligner:
    """Simple VAD + Syllable counting alignment (matching Flutter implementation)."""
    
    def __init__(self, script_words, sample_rate=16000, frame_ms=32):
        self.script_words = script_words
        self.sample_rate = sample_rate
        self.frame_size = int(sample_rate * frame_ms / 1000)
        self.current_word = 0
        
        # Parameters (matching Flutter VoiceAlignmentTracker)
        self.energy_threshold = 0.01
        self.syllables_per_word = 1.5
        self.min_peak_distance = 0.15  # seconds
        
        # State
        self.syllable_count = 0
        self.last_peak_time = 0
        self.energy_history = []
        
    def process_audio(self, audio):
        """Process audio and return word position estimates over time."""
        positions = []
        times = []
        
        for i in range(0, len(audio) - self.frame_size, self.frame_size):
            frame = audio[i:i + self.frame_size]
            time = i / self.sample_rate
            
            # Calculate RMS energy
            energy = np.sqrt(np.mean(frame**2))
            
            # Adaptive threshold
            self.energy_history.append(energy)
            if len(self.energy_history) > 20:
                self.energy_history.pop(0)
            
            threshold = np.percentile(self.energy_history, 75) if len(self.energy_history) > 5 else 0.01
            
            # Detect syllable peaks
            if energy > threshold:
                time_since_last_peak = time - self.last_peak_time
                
                if time_since_last_peak >= self.min_peak_distance:
                    self.syllable_count += 1
                    self.last_peak_time = time
                    
                    # Update word position
                    estimated_words = self.syllable_count / self.syllables_per_word
                    self.current_word = min(int(estimated_words), len(self.script_words) - 1)
            
            positions.append(self.current_word)
            times.append(time)
        
        return times, positions


def load_ground_truth(json_path: str):
    """Load ground truth word timings."""
    with open(json_path, 'r') as f:
        data = json.load(f)
    return data


def test_vad_alignment(audio_path: str, ground_truth_data: dict):
    """Test VAD+Syllable alignment against ground truth."""
    print("\n🧪 Testing VAD+Syllable Alignment...")
    print("=" * 60)
    
    # Load audio
    audio, sr = librosa.load(audio_path, sr=16000)
    script_words = ground_truth_data['script_words']
    word_timings = ground_truth_data['word_timings']
    
    print(f"📊 Audio: {len(audio)/sr:.1f}s, {len(script_words)} words in script")
    
    # Run VAD alignment
    aligner = VadSyllableAligner(script_words)
    times, positions = aligner.process_audio(audio)
    
    # Compare against ground truth
    errors = []
    latencies = []
    
    print(f"\n📈 Word-by-Word Accuracy:")
    print(f"{'Word':<15} {'GT Time':<10} {'Est Time':<10} {'Error':<10} {'Latency':<10}")
    print("-" * 65)
    
    for wt in word_timings[:20]:  # Check first 20 words
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
            latency = estimated_time - true_time  # Positive = late, negative = early
            
            errors.append(error)
            latencies.append(latency)
            
            status = "✓" if error < 0.5 else "✗"
            print(f"{word:<15} {true_time:<10.2f} {estimated_time:<10.2f} {error:<10.2f} {latency:<10.2f} {status}")
    
    # Statistics
    print("\n" + "=" * 60)
    print("📊 ACCURACY STATISTICS")
    print("=" * 60)
    
    if errors:
        print(f"Mean Error: {np.mean(errors):.3f}s")
        print(f"Median Error: {np.median(errors):.3f}s")
        print(f"Std Dev: {np.std(errors):.3f}s")
        print(f"Max Error: {np.max(errors):.3f}s")
        print(f"\nMean Latency: {np.mean(latencies):.3f}s")
        print(f"Median Latency: {np.median(latencies):.3f}s")
        
        # Accuracy thresholds
        within_250ms = sum(1 for e in errors if e < 0.25) / len(errors) * 100
        within_500ms = sum(1 for e in errors if e < 0.5) / len(errors) * 100
        within_1s = sum(1 for e in errors if e < 1.0) / len(errors) * 100
        
        print(f"\n✅ Accuracy within thresholds:")
        print(f"   Within 250ms: {within_250ms:.1f}%")
        print(f"   Within 500ms: {within_500ms:.1f}%")
        print(f"   Within 1.0s:  {within_1s:.1f}%")
    
    return times, positions, errors, latencies


def plot_results(times, positions, ground_truth_data, errors):
    """Plot alignment results vs ground truth."""
    fig, axes = plt.subplots(3, 1, figsize=(14, 10))
    
    # Plot 1: Word position over time
    ax = axes[0]
    ax.plot(times, positions, 'b-', label='VAD Estimate', linewidth=2)
    
    # Add ground truth markers
    word_timings = ground_truth_data['word_timings']
    for wt in word_timings:
        if wt['script_index'] is not None:
            ax.axvline(wt['start'], color='red', alpha=0.3, linewidth=1)
            ax.plot(wt['start'], wt['script_index'], 'ro', markersize=4)
    
    ax.set_xlabel('Time (seconds)')
    ax.set_ylabel('Word Index')
    ax.set_title('Word Position Over Time: VAD Estimate vs Ground Truth')
    ax.legend(['VAD Estimate', 'Ground Truth Markers'])
    ax.grid(True, alpha=0.3)
    
    # Plot 2: Error over time
    ax = axes[1]
    if errors:
        ax.plot(range(len(errors)), errors, 'r-', linewidth=2)
        ax.axhline(np.mean(errors), color='blue', linestyle='--', label=f'Mean: {np.mean(errors):.3f}s')
        ax.axhline(0.5, color='green', linestyle='--', label='500ms threshold')
        ax.set_xlabel('Word Index')
        ax.set_ylabel('Error (seconds)')
        ax.set_title('Alignment Error Per Word')
        ax.legend()
        ax.grid(True, alpha=0.3)
    
    # Plot 3: Error distribution
    ax = axes[2]
    if errors:
        ax.hist(errors, bins=30, color='blue', alpha=0.7, edgecolor='black')
        ax.axvline(np.mean(errors), color='red', linestyle='--', linewidth=2, label=f'Mean: {np.mean(errors):.3f}s')
        ax.axvline(np.median(errors), color='green', linestyle='--', linewidth=2, label=f'Median: {np.median(errors):.3f}s')
        ax.set_xlabel('Error (seconds)')
        ax.set_ylabel('Frequency')
        ax.set_title('Distribution of Alignment Errors')
        ax.legend()
        ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig('alignment_accuracy_results.png', dpi=150)
    print(f"\n📊 Saved plot to: alignment_accuracy_results.png")
    plt.close()


def main():
    print("=" * 60)
    print("🎯 ALIGNMENT ACCURACY TESTING")
    print("=" * 60)
    
    # Paths
    ground_truth_file = "ground_truth_timings.json"
    audio_file = "audio/adalyn_reading_background.wav"
    
    # Check files exist
    if not Path(ground_truth_file).exists():
        print(f"\n❌ Ground truth not found: {ground_truth_file}")
        print("   Run: python get_ground_truth.py first!")
        return
    
    if not Path(audio_file).exists():
        print(f"\n❌ Audio file not found: {audio_file}")
        return
    
    # Load ground truth
    print(f"\n📂 Loading ground truth...")
    ground_truth = load_ground_truth(ground_truth_file)
    print(f"   ✓ {ground_truth['total_words']} words with timings")
    
    # Test VAD alignment
    times, positions, errors, latencies = test_vad_alignment(audio_file, ground_truth)
    
    # Plot results
    if errors:
        plot_results(times, positions, ground_truth, errors)
    
    print("\n" + "=" * 60)
    print("✅ TESTING COMPLETE!")
    print("=" * 60)
    
    if errors:
        mean_error = np.mean(errors)
        
        if mean_error < 0.3:
            print("🎉 EXCELLENT: Mean error < 300ms")
        elif mean_error < 0.5:
            print("👍 GOOD: Mean error < 500ms")
        elif mean_error < 1.0:
            print("⚠️  FAIR: Mean error < 1s (needs improvement)")
        else:
            print("❌ POOR: Mean error > 1s (major issues)")
        
        print(f"\n💡 Recommendations:")
        if np.mean(latencies) > 0.5:
            print("   - System is too slow (high latency)")
            print("   - Consider reducing syllable-per-word ratio")
        elif np.mean(latencies) < -0.5:
            print("   - System is too fast (negative latency)")
            print("   - Consider increasing syllable-per-word ratio")
        
        if np.std(errors) > 0.5:
            print("   - High variance in errors")
            print("   - Algorithm is inconsistent")
            print("   - Need better energy threshold tuning")


if __name__ == "__main__":
    main()

