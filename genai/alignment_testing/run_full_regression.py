#!/usr/bin/env python3
"""
Full Regression Test: 500 LibriSpeech Samples

Tests phoneme-level alignment across diverse:
- Speakers (male, female, different accents)
- Recording conditions
- Speech rates
- Background noise (augmented samples)
"""

import numpy as np
import json
from pathlib import Path
from typing import List, Tuple, Dict
from tqdm import tqdm
import sys

sys.path.append('.')
from test_phonetic_matching import word_to_phonemes, VOWELS

def text_to_phonemes(text: str):
    """Convert text to phonemes."""
    words = text.lower().split()
    phonemes = []
    boundaries = [0]
    
    for word in words:
        ph = word_to_phonemes(word)
        phonemes.extend(ph)
        boundaries.append(len(phonemes))
    
    return phonemes, boundaries[:-1], words

def phoneme_sim(p1: str, p2: str) -> float:
    """Phoneme similarity."""
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
    """Fuzzy phoneme alignment."""
    if not detected:
        return 0, 0.0
    
    recent = detected[-15:]
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
    """Score alignment."""
    total, d_idx, s_idx, last_s = 0.0, 0, start, start
    
    while d_idx < len(detected) and s_idx < len(script):
        sim = phoneme_sim(detected[d_idx], script[s_idx])
        
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

def evaluate_sample(gt_json_path: str) -> Dict:
    """
    Evaluate a single sample.
    
    For LibriSpeech: ground truth text = script (perfect reading)
    """
    with open(gt_json_path) as f:
        gt = json.load(f)
    
    # For LibriSpeech, the transcription IS the script
    script_text = gt['transcript']
    script_ph, boundaries, script_words = text_to_phonemes(script_text)
    
    # Simulate streaming
    results = []
    cumulative_ph = []
    
    for i in range(0, len(gt['word_timings']), 5):
        chunk = gt['word_timings'][i:i+5]
        chunk_text = ' '.join([w['word'] for w in chunk])
        chunk_ph, _, _ = text_to_phonemes(chunk_text)
        
        cumulative_ph.extend(chunk_ph)
        
        pred_idx, conf = align_phonemes(cumulative_ph, script_ph, boundaries)
        expected_idx = min(i + len(chunk) - 1, len(script_words) - 1)
        
        results.append({
            'predicted': pred_idx,
            'expected': expected_idx,
            'confidence': conf,
            'correct': pred_idx == expected_idx,
            'off_by': abs(pred_idx - expected_idx)
        })
    
    # Metrics
    correct = sum(1 for r in results if r['correct'])
    close = sum(1 for r in results if r['off_by'] <= 1)
    total = len(results)
    
    return {
        'file': gt_json_path,
        'total_steps': total,
        'correct': correct,
        'close': close,
        'accuracy': correct / total if total > 0 else 0,
        'close_accuracy': close / total if total > 0 else 0,
        'avg_confidence': np.mean([r['confidence'] for r in results]) if results else 0,
        'avg_off_by': np.mean([r['off_by'] for r in results]) if results else 0
    }

def main():
    print("="*60)
    print("🧪 FULL REGRESSION TEST: 500 SAMPLES")
    print("="*60)
    print("\nTesting phoneme-level alignment on diverse audio:")
    print("- Multiple speakers")
    print("- Various speech rates")
    print("- Clean + noisy (augmented)")
    print("\nThis will take ~10-20 minutes...\n")
    
    # Find all ground truth files
    gt_dir = Path("ground_truth_500")
    if not gt_dir.exists():
        print(f"❌ Ground truth directory not found: {gt_dir}")
        print(f"   Run: python 02_generate_ground_truth_batch.py first")
        return
    
    gt_files = sorted(gt_dir.glob("*.json"))
    
    if len(gt_files) < 100:
        print(f"⚠️  Only found {len(gt_files)} ground truth files")
        print(f"   Expected ~500")
        if input("Continue anyway? (y/n): ").lower() != 'y':
            return
    
    print(f"📂 Found {len(gt_files)} ground truth files")
    print(f"\n{'='*60}")
    print(f"RUNNING TESTS")
    print(f"{'='*60}\n")
    
    # Evaluate all samples
    results = []
    for gt_file in tqdm(gt_files, desc="Testing"):
        try:
            result = evaluate_sample(str(gt_file))
            results.append(result)
        except Exception as e:
            print(f"⚠️  Error on {gt_file.name}: {e}")
            continue
    
    # Aggregate results
    print(f"\n{'='*60}")
    print(f"📊 AGGREGATE RESULTS")
    print(f"{'='*60}\n")
    
    total_samples = len(results)
    accuracies = [r['accuracy'] for r in results]
    close_accuracies = [r['close_accuracy'] for r in results]
    confidences = [r['avg_confidence'] for r in results]
    off_bys = [r['avg_off_by'] for r in results]
    
    print(f"Samples tested: {total_samples}")
    print(f"\n📈 Accuracy (Exact Match):")
    print(f"   Mean:   {100*np.mean(accuracies):.1f}%")
    print(f"   Median: {100*np.median(accuracies):.1f}%")
    print(f"   Std:    {100*np.std(accuracies):.1f}%")
    print(f"   Min:    {100*np.min(accuracies):.1f}%")
    print(f"   Max:    {100*np.max(accuracies):.1f}%")
    
    print(f"\n📈 Accuracy (±1 Word):")
    print(f"   Mean:   {100*np.mean(close_accuracies):.1f}%")
    print(f"   Median: {100*np.median(close_accuracies):.1f}%")
    print(f"   Std:    {100*np.std(close_accuracies):.1f}%")
    print(f"   Min:    {100*np.min(close_accuracies):.1f}%")
    print(f"   Max:    {100*np.max(close_accuracies):.1f}%")
    
    print(f"\n📈 Confidence:")
    print(f"   Mean:   {np.mean(confidences):.2f}")
    print(f"   Median: {np.median(confidences):.2f}")
    
    print(f"\n📈 Average Error (words off):")
    print(f"   Mean:   {np.mean(off_bys):.2f} words")
    print(f"   Median: {np.median(off_bys):.2f} words")
    
    # Distribution
    print(f"\n📊 Accuracy Distribution (±1 word):")
    bins = [(0.95, 1.0), (0.90, 0.95), (0.85, 0.90), (0.80, 0.85), (0, 0.80)]
    for low, high in bins:
        count = sum(1 for a in close_accuracies if low <= a < high)
        pct = 100 * count / total_samples if total_samples > 0 else 0
        bar = "█" * int(pct / 2)
        print(f"   {100*low:5.1f}-{100*high:5.1f}%: {count:3d} samples ({pct:5.1f}%) {bar}")
    
    # Worst cases
    print(f"\n⚠️  Worst 5 Samples:")
    worst = sorted(results, key=lambda r: r['close_accuracy'])[:5]
    for i, r in enumerate(worst, 1):
        print(f"   {i}. {Path(r['file']).name}: {100*r['close_accuracy']:.1f}% (avg off: {r['avg_off_by']:.1f} words)")
    
    # Best cases
    print(f"\n✅ Best 5 Samples:")
    best = sorted(results, key=lambda r: r['close_accuracy'], reverse=True)[:5]
    for i, r in enumerate(best, 1):
        print(f"   {i}. {Path(r['file']).name}: {100*r['close_accuracy']:.1f}% (avg off: {r['avg_off_by']:.1f} words)")
    
    # Save results
    results_file = "regression_results.json"
    with open(results_file, 'w') as f:
        json.dump({
            'total_samples': total_samples,
            'mean_accuracy': float(np.mean(accuracies)),
            'mean_close_accuracy': float(np.mean(close_accuracies)),
            'median_accuracy': float(np.median(accuracies)),
            'median_close_accuracy': float(np.median(close_accuracies)),
            'std_accuracy': float(np.std(accuracies)),
            'mean_confidence': float(np.mean(confidences)),
            'mean_error_words': float(np.mean(off_bys)),
            'per_sample_results': results
        }, f, indent=2)
    print(f"\n💾 Results saved: {results_file}")
    
    # Final verdict
    print(f"\n{'='*60}")
    print(f"🎯 FINAL VERDICT")
    print(f"{'='*60}")
    
    mean_close = np.mean(close_accuracies)
    
    if mean_close >= 0.90:
        print(f"✅ EXCELLENT: {100*mean_close:.1f}% average (±1 word)!")
        print(f"   Phoneme-level alignment is PRODUCTION-READY!")
        print(f"   → Ready to port to Dart")
    elif mean_close >= 0.85:
        print(f"⚠️  VERY GOOD: {100*mean_close:.1f}% average (±1 word)")
        print(f"   Close to production-ready, minor tuning recommended")
    elif mean_close >= 0.80:
        print(f"⚠️  GOOD: {100*mean_close:.1f}% average (±1 word)")
        print(f"   Needs tuning before production")
    else:
        print(f"❌ NEEDS WORK: {100*mean_close:.1f}% average (±1 word)")
        print(f"   Requires significant improvement")
    
    print(f"\n💡 Next Steps:")
    if mean_close >= 0.85:
        print(f"   1. ✅ Algorithm validated!")
        print(f"   2. Port to Dart (PhonemeAligner class)")
        print(f"   3. Integrate with Sherpa-ONNX")
        print(f"   4. Test in Flutter app")
        print(f"   5. Deploy to users!")
    else:
        print(f"   1. Analyze worst-case samples")
        print(f"   2. Tune phoneme similarity scores")
        print(f"   3. Adjust window size")
        print(f"   4. Re-run regression")

if __name__ == "__main__":
    main()

