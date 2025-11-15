"""
🔍 Interactive Training Data Explorer

Run this in Jupyter/IPython for interactive exploration:
    jupyter notebook
    # Then open this file or copy cells into a notebook

Or run standalone sections:
    python explore_data.py
"""

import numpy as np
import matplotlib.pyplot as plt
import librosa
import librosa.display
import json
from pathlib import Path
from IPython.display import Audio, display

# ============================================================================
# CONFIGURATION
# ============================================================================

DATASET_DIR = Path('dataset_tiny')  # Change to 'dataset_100' when ready
GT_DIR = Path('ground_truth_tiny')  # Change to 'ground_truth_100' when ready

# ============================================================================
# UTILITIES
# ============================================================================

def load_sample(sample_id, augmented=False):
    """Load all data for a sample."""
    suffix = '_augmented' if augmented else '_clean'
    npz_path = DATASET_DIR / f"sample_{sample_id:04d}{suffix}.npz"
    
    if not npz_path.exists():
        return None
    
    data = np.load(npz_path)
    gt_path = GT_DIR / f"sample_{sample_id:04d}_gt.json"
    
    with open(gt_path) as f:
        gt = json.load(f)
    
    wav_path = GT_DIR / gt['wav_file']
    audio, sr = librosa.load(wav_path, sr=16000)
    
    return {
        'features': data['features'],
        'labels': data['labels'],
        'gt': gt,
        'audio': audio,
        'sr': sr
    }

# ============================================================================
# CELL 1: Load and Preview Sample
# ============================================================================

def preview_sample(sample_id=0, augmented=False):
    """Quick preview of a sample."""
    data = load_sample(sample_id, augmented)
    
    if not data:
        print(f"❌ Sample {sample_id} not found")
        return None
    
    gt = data['gt']
    print("=" * 80)
    print(f"📊 Sample {sample_id} ({'Augmented' if augmented else 'Clean'})")
    print("=" * 80)
    print(f"\n📝 Transcript: \"{gt['transcript']}\"")
    print(f"\n📋 Stats:")
    print(f"   Duration: {gt['duration']:.1f}s")
    print(f"   Words: {len(gt['word_timings'])}")
    print(f"   Training windows: {len(data['features'])}")
    print(f"   Boundary windows: {np.sum(data['labels']):.0f} ({np.sum(data['labels'])/len(data['labels'])*100:.1f}%)")
    
    print(f"\n🎯 First 5 words:")
    for i, word in enumerate(gt['word_timings'][:5]):
        print(f"   {i+1}. \"{word['word']}\" @ {word['start']:.2f}s - {word['end']:.2f}s")
    
    return data

# ============================================================================
# CELL 2: Visualize Sample
# ============================================================================

def visualize_sample(sample_id=0, augmented=False):
    """Comprehensive visualization."""
    data = load_sample(sample_id, augmented)
    
    if not data:
        print(f"❌ Sample {sample_id} not found")
        return
    
    gt = data['gt']
    audio = data['audio']
    sr = data['sr']
    labels = data['labels']
    
    fig, axes = plt.subplots(3, 1, figsize=(16, 10))
    
    # Waveform with word boundaries
    ax = axes[0]
    time = np.arange(len(audio)) / sr
    ax.plot(time, audio, linewidth=0.5, alpha=0.7)
    ax.set_xlabel('Time (s)')
    ax.set_ylabel('Amplitude')
    ax.set_title(f'Waveform ({("Augmented" if augmented else "Clean")})')
    ax.grid(True, alpha=0.3)
    
    for word in gt['word_timings']:
        ax.axvline(word['start'], color='green', alpha=0.3, linewidth=1)
        ax.text(word['start'], ax.get_ylim()[1]*0.9, word['word'], 
                rotation=90, fontsize=7, va='top')
    
    # Spectrogram
    ax = axes[1]
    D = librosa.amplitude_to_db(np.abs(librosa.stft(audio)), ref=np.max)
    img = librosa.display.specshow(D, y_axis='hz', x_axis='time', sr=sr, ax=ax)
    ax.set_title('Spectrogram')
    plt.colorbar(img, ax=ax, format='%+2.0f dB')
    
    for word in gt['word_timings']:
        ax.axvline(word['start'], color='red', alpha=0.5, linewidth=1)
    
    # Training labels
    ax = axes[2]
    window_times = np.arange(len(labels)) * 0.016
    ax.plot(window_times, labels, 'g-', linewidth=2, label='Boundary Label')
    ax.fill_between(window_times, 0, labels, alpha=0.3, color='green')
    ax.set_xlabel('Time (s)')
    ax.set_ylabel('Label (0/1)')
    ax.set_title('Training Labels (1 = word boundary)')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_ylim(-0.1, 1.1)
    
    plt.tight_layout()
    plt.show()
    
    # Audio player (works in Jupyter)
    try:
        print("\n🔊 Audio Player:")
        display(Audio(audio, rate=sr))
    except:
        print("\n💡 Run in Jupyter to play audio")

# ============================================================================
# CELL 3: Compare Clean vs Augmented
# ============================================================================

def compare_clean_augmented(sample_id=0):
    """Side-by-side comparison."""
    clean = load_sample(sample_id, augmented=False)
    aug = load_sample(sample_id, augmented=True)
    
    if not clean or not aug:
        print(f"❌ Sample {sample_id} not found")
        return
    
    fig, axes = plt.subplots(2, 2, figsize=(16, 10))
    
    # Clean waveform
    ax = axes[0, 0]
    time = np.arange(len(clean['audio'])) / clean['sr']
    ax.plot(time, clean['audio'], linewidth=0.5)
    ax.set_title('🎵 Clean Audio')
    ax.set_xlabel('Time (s)')
    ax.set_ylabel('Amplitude')
    ax.grid(True, alpha=0.3)
    
    # Augmented waveform
    ax = axes[0, 1]
    time = np.arange(len(aug['audio'])) / aug['sr']
    ax.plot(time, aug['audio'], linewidth=0.5, color='orange')
    ax.set_title('🔊 Augmented Audio (Panera noise)')
    ax.set_xlabel('Time (s)')
    ax.set_ylabel('Amplitude')
    ax.grid(True, alpha=0.3)
    
    # Clean labels
    ax = axes[1, 0]
    window_times = np.arange(len(clean['labels'])) * 0.016
    ax.plot(window_times, clean['labels'], 'g-', linewidth=2)
    ax.fill_between(window_times, 0, clean['labels'], alpha=0.3, color='green')
    ax.set_title('Clean: Boundary Labels')
    ax.set_xlabel('Time (s)')
    ax.set_ylabel('Label')
    ax.set_ylim(-0.1, 1.1)
    ax.grid(True, alpha=0.3)
    
    # Augmented labels
    ax = axes[1, 1]
    window_times = np.arange(len(aug['labels'])) * 0.016
    ax.plot(window_times, aug['labels'], 'g-', linewidth=2, color='orange')
    ax.fill_between(window_times, 0, aug['labels'], alpha=0.3, color='orange')
    ax.set_title('Augmented: Boundary Labels (should match!)')
    ax.set_xlabel('Time (s)')
    ax.set_ylabel('Label')
    ax.set_ylim(-0.1, 1.1)
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.show()
    
    # Sanity check
    if np.array_equal(clean['labels'], aug['labels']):
        print("✅ PASS: Labels are identical")
    else:
        print("❌ FAIL: Labels differ!")
    
    # Audio players (works in Jupyter)
    try:
        print("\n🎵 Clean Audio:")
        display(Audio(clean['audio'], rate=clean['sr']))
        print("\n🔊 Augmented Audio:")
        display(Audio(aug['audio'], rate=aug['sr']))
    except:
        print("\n💡 Run in Jupyter to play audio")

# ============================================================================
# CELL 4: Inspect Specific Window
# ============================================================================

def inspect_window(sample_id=0, window_idx=2, augmented=False):
    """Deep dive into one training window."""
    data = load_sample(sample_id, augmented)
    
    if not data or window_idx >= len(data['features']):
        print(f"❌ Invalid sample or window")
        return
    
    window_features = data['features'][window_idx]  # (31, 13)
    window_label = data['labels'][window_idx]
    
    center_time = window_idx * 0.016
    start_time = center_time - 0.25
    end_time = center_time + 0.25
    
    print("=" * 80)
    print(f"🔬 Window {window_idx} - Sample {sample_id:04d}")
    print("=" * 80)
    print(f"\n⏱️  Time: {start_time:.3f}s - {end_time:.3f}s (center: {center_time:.3f}s)")
    print(f"🏷️  Label: {'🎯 BOUNDARY' if window_label == 1 else '🔵 NON-BOUNDARY'}")
    print(f"📊 Features: {window_features.shape} (31 frames × 13 MFCCs)")
    
    # Find nearest word
    gt = data['gt']
    nearest_word = None
    min_dist = float('inf')
    
    for word in gt['word_timings']:
        dist = abs(word['start'] - center_time)
        if dist < min_dist:
            min_dist = dist
            nearest_word = word
    
    if nearest_word:
        print(f"\n🎯 Nearest word: \"{nearest_word['word']}\" @ {nearest_word['start']:.3f}s")
        print(f"   Distance: {min_dist*1000:.0f}ms")
    
    # Visualize
    fig, axes = plt.subplots(2, 1, figsize=(14, 8))
    
    # MFCC heatmap
    ax = axes[0]
    im = ax.imshow(window_features.T, aspect='auto', origin='lower', cmap='viridis')
    ax.axvline(15, color='red', linestyle='--', linewidth=2, label='Center (predicted)')
    ax.set_xlabel('Frame (within 500ms window)')
    ax.set_ylabel('MFCC Coefficient')
    ax.set_title(f'MFCC Heatmap - Window {window_idx} (Label: {int(window_label)})')
    ax.legend()
    plt.colorbar(im, ax=ax)
    
    # MFCC trajectories
    ax = axes[1]
    for i in range(13):
        ax.plot(window_features[:, i], label=f'MFCC {i}', alpha=0.7)
    ax.axvline(15, color='red', linestyle='--', linewidth=2, label='Center')
    ax.set_xlabel('Frame')
    ax.set_ylabel('MFCC Value')
    ax.set_title('MFCC Trajectories')
    ax.legend(bbox_to_anchor=(1.05, 1), loc='upper left', fontsize=8)
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.show()

# ============================================================================
# CELL 5: Dataset Statistics
# ============================================================================

def analyze_dataset():
    """Statistics across entire dataset."""
    npz_files = sorted(DATASET_DIR.glob('*.npz'))
    
    all_ratios = []
    total_windows = 0
    total_boundaries = 0
    
    for npz_file in npz_files:
        data = np.load(npz_file)
        labels = data['labels']
        n_boundaries = np.sum(labels)
        
        all_ratios.append(n_boundaries / len(labels))
        total_windows += len(labels)
        total_boundaries += n_boundaries
    
    print("=" * 80)
    print("📊 DATASET STATISTICS")
    print("=" * 80)
    print(f"\nTotal samples: {len(npz_files)}")
    print(f"Total windows: {total_windows}")
    print(f"Total boundaries: {total_boundaries:.0f} ({total_boundaries/total_windows*100:.1f}%)")
    print(f"\nBoundary ratio:")
    print(f"  Mean: {np.mean(all_ratios)*100:.2f}%")
    print(f"  Std:  {np.std(all_ratios)*100:.2f}%")
    print(f"  Min:  {np.min(all_ratios)*100:.2f}%")
    print(f"  Max:  {np.max(all_ratios)*100:.2f}%")
    
    # Histogram
    plt.figure(figsize=(10, 6))
    plt.hist(np.array(all_ratios) * 100, bins=20, edgecolor='black', alpha=0.7)
    plt.xlabel('Boundary Ratio (%)')
    plt.ylabel('Number of Samples')
    plt.title('Distribution of Boundary Ratios')
    plt.axvline(np.mean(all_ratios) * 100, color='red', linestyle='--', 
                linewidth=2, label=f'Mean: {np.mean(all_ratios)*100:.1f}%')
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.show()

# ============================================================================
# MAIN - Run some examples
# ============================================================================

if __name__ == "__main__":
    print("\n" + "=" * 80)
    print("🔍 TRAINING DATA EXPLORER")
    print("=" * 80)
    print("\nAvailable functions:")
    print("  preview_sample(sample_id, augmented=False)")
    print("  visualize_sample(sample_id, augmented=False)")
    print("  compare_clean_augmented(sample_id)")
    print("  inspect_window(sample_id, window_idx, augmented=False)")
    print("  analyze_dataset()")
    print("\nExample usage:")
    print("  data = preview_sample(0)")
    print("  visualize_sample(0, augmented=True)")
    print("  compare_clean_augmented(0)")
    print("  inspect_window(0, window_idx=17)")
    print("  analyze_dataset()")
    print("\n💡 Best experience: Copy cells into Jupyter for audio playback!")
    print("\nRunning quick preview...\n")
    
    # Quick demo
    data = preview_sample(0)
    if data:
        print("\n✅ Sample loaded! Try: visualize_sample(0)")

