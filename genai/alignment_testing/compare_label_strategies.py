#!/usr/bin/env python3
"""
Compare hard vs soft labels for knowledge distillation.
Visualize the difference and show why soft labels are better.
"""

import numpy as np
import matplotlib.pyplot as plt
import json
from pathlib import Path

def create_hard_labels(duration, word_timings, hop_ms=16, window_ms=50):
    """Binary labels."""
    n_frames = int(duration * 1000 / hop_ms) + 1
    labels = np.zeros(n_frames)
    
    for word in word_timings:
        start_time = word['start']
        frame_idx = int(start_time * 1000 / hop_ms)
        window_frames = int(window_ms / hop_ms)
        
        start_frame = max(0, frame_idx - window_frames // 2)
        end_frame = min(n_frames, frame_idx + window_frames // 2)
        labels[start_frame:end_frame] = 1.0
    
    return labels

def create_soft_labels(duration, word_timings, hop_ms=16, sigma_ms=50):
    """Gaussian soft labels."""
    n_frames = int(duration * 1000 / hop_ms) + 1
    labels = np.zeros(n_frames)
    
    for word in word_timings:
        start_time = word['start']
        
        for frame_idx in range(n_frames):
            frame_time = frame_idx * hop_ms / 1000
            distance_ms = abs(frame_time - start_time) * 1000
            
            prob = np.exp(-(distance_ms**2) / (2 * sigma_ms**2))
            labels[frame_idx] = max(labels[frame_idx], prob)
    
    return labels

def visualize_comparison(gt_file, sigma_values=[25, 50, 100]):
    """
    Compare hard vs soft labels for one sample.
    """
    # Load ground truth
    with open(gt_file) as f:
        gt = json.load(f)
    
    duration = gt['duration']
    word_timings = gt['word_timings']
    
    # Create labels
    hard_labels = create_hard_labels(duration, word_timings)
    soft_labels_variants = [create_soft_labels(duration, word_timings, sigma_ms=s) for s in sigma_values]
    
    # Create figure
    fig, axes = plt.subplots(len(sigma_values) + 2, 1, figsize=(16, 12))
    
    time_axis = np.arange(len(hard_labels)) * 0.016
    
    # Plot 0: Word boundaries
    ax = axes[0]
    for word in word_timings:
        ax.axvline(word['start'], color='red', alpha=0.5, linewidth=1)
        ax.text(word['start'], 0.5, word['word'], rotation=90, fontsize=7, va='bottom')
    ax.set_ylim(0, 1)
    ax.set_title('Ground Truth: Word Boundaries')
    ax.set_ylabel('Boundary')
    ax.grid(True, alpha=0.3)
    
    # Plot 1: Hard labels
    ax = axes[1]
    ax.fill_between(time_axis, 0, hard_labels, alpha=0.3, color='blue', label='Hard Labels')
    ax.plot(time_axis, hard_labels, 'b-', linewidth=2)
    for word in word_timings:
        ax.axvline(word['start'], color='red', alpha=0.3, linewidth=1)
    ax.set_ylim(-0.1, 1.1)
    ax.set_title('Hard Labels (Binary: 0 or 1)')
    ax.set_ylabel('Label')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    # Stats for hard
    n_positive = np.sum(hard_labels > 0.5)
    ratio = n_positive / len(hard_labels) * 100
    ax.text(0.02, 0.98, f'Positive: {n_positive}/{len(hard_labels)} ({ratio:.1f}%)',
            transform=ax.transAxes, va='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    # Plots 2+: Soft labels with different sigmas
    for i, (soft_labels, sigma) in enumerate(zip(soft_labels_variants, sigma_values)):
        ax = axes[i + 2]
        ax.fill_between(time_axis, 0, soft_labels, alpha=0.3, color='green', label=f'Soft Labels (σ={sigma}ms)')
        ax.plot(time_axis, soft_labels, 'g-', linewidth=2)
        for word in word_timings:
            ax.axvline(word['start'], color='red', alpha=0.3, linewidth=1)
        ax.set_ylim(-0.1, 1.1)
        ax.set_title(f'Soft Labels (Gaussian σ={sigma}ms)')
        ax.set_ylabel('Probability')
        ax.legend()
        ax.grid(True, alpha=0.3)
        
        # Stats for soft
        n_high = np.sum(soft_labels > 0.5)
        n_med = np.sum((soft_labels > 0.1) & (soft_labels <= 0.5))
        n_low = np.sum((soft_labels > 0.01) & (soft_labels <= 0.1))
        ax.text(0.02, 0.98, 
                f'High (>0.5): {n_high} | Med (0.1-0.5): {n_med} | Low (0.01-0.1): {n_low}',
                transform=ax.transAxes, va='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    axes[-1].set_xlabel('Time (s)')
    plt.tight_layout()
    plt.savefig('label_comparison.png', dpi=150)
    plt.show()
    
    # Print comparison
    print("=" * 80)
    print("📊 LABEL COMPARISON")
    print("=" * 80)
    print(f"\nSample: {gt['transcript'][:80]}...")
    print(f"Duration: {duration:.1f}s")
    print(f"Words: {len(word_timings)}")
    print(f"Frames: {len(hard_labels)}")
    
    print(f"\n📍 Hard Labels:")
    print(f"   Positive frames: {np.sum(hard_labels > 0.5):.0f} ({np.sum(hard_labels > 0.5)/len(hard_labels)*100:.1f}%)")
    print(f"   Negative frames: {np.sum(hard_labels <= 0.5):.0f} ({np.sum(hard_labels <= 0.5)/len(hard_labels)*100:.1f}%)")
    print(f"   Class imbalance ratio: {(np.sum(hard_labels <= 0.5) / np.sum(hard_labels > 0.5)):.1f}:1")
    
    for soft_labels, sigma in zip(soft_labels_variants, sigma_values):
        print(f"\n🎯 Soft Labels (σ={sigma}ms):")
        print(f"   High prob (>0.5): {np.sum(soft_labels > 0.5):.0f} ({np.sum(soft_labels > 0.5)/len(soft_labels)*100:.1f}%)")
        print(f"   Med prob (0.1-0.5): {np.sum((soft_labels > 0.1) & (soft_labels <= 0.5)):.0f}")
        print(f"   Low prob (0.01-0.1): {np.sum((soft_labels > 0.01) & (soft_labels <= 0.1)):.0f}")
        print(f"   Near-zero (<0.01): {np.sum(soft_labels <= 0.01):.0f}")
        print(f"   Mean label value: {np.mean(soft_labels):.4f}")
        print(f"   Non-zero frames: {np.sum(soft_labels > 0.01):.0f} ({np.sum(soft_labels > 0.01)/len(soft_labels)*100:.1f}%)")
    
    print("\n✅ Key Insight:")
    print("   Soft labels provide continuous signal - model learns 'distance to boundary'")
    print("   Hard labels have sharp discontinuity - model only learns binary classification")

if __name__ == "__main__":
    import sys
    
    gt_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('ground_truth_tiny')
    sample_id = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    
    gt_file = gt_dir / f"sample_{sample_id:04d}_gt.json"
    
    if not gt_file.exists():
        print(f"❌ Ground truth file not found: {gt_file}")
        exit(1)
    
    visualize_comparison(gt_file, sigma_values=[25, 50, 100])

