#!/usr/bin/env python3
"""
Advanced Alignment Test - Pushing to 95-99% Accuracy

Tests the full system with advanced fuzzy matching techniques:
1. Weighted Levenshtein
2. Dynamic Time Warping (DTW)
3. Smith-Waterman local alignment
4. Dead reckoning with multiple hypotheses

Goal: Achieve 95-99% accuracy on Sherpa output.
"""

import json
import numpy as np
from pathlib import Path
import sys

sys.path.append('.')
from test_phonetic_matching import word_to_phonemes, VOWELS
from advanced_fuzzy_alignment import (
    dead_reckoning_align,
    beam_search_align,
    weighted_levenshtein,
    dtw_alignment,
    smith_waterman
)

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

def test_basic_alignment(sherpa_text: str, script_text: str) -> dict:
    """Test with BASIC phoneme similarity (our original method)."""
    script_ph, boundaries, script_words = text_to_phonemes(script_text)
    sherpa_words = sherpa_text.lower().split()
    
    results = []
    cumulative_ph = []
    
    # Process incrementally (5 words at a time, as before)
    for i in range(0, len(sherpa_words), 5):
        chunk = sherpa_words[i:i+5]
        chunk_text = ' '.join(chunk)
        chunk_ph, _, _ = text_to_phonemes(chunk_text)
        
        cumulative_ph.extend(chunk_ph)
        
        # Use simple phoneme matching (original method)
        def simple_align(detected, script, boundaries):
            if not detected:
                return 0, 0.0
            
            recent = detected[-15:]
            best_word, best_score = 0, 0.0
            
            for w_idx in range(len(boundaries)):
                start = boundaries[w_idx]
                total, d_idx, s_idx, last_s = 0.0, 0, start, start
                
                while d_idx < len(recent) and s_idx < len(script):
                    sim = 1.0 if recent[d_idx] == script[s_idx] else 0.75 if (recent[d_idx] in VOWELS and script[s_idx] in VOWELS) else 0.3
                    
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
                
                score = (total / len(recent)) if recent else 0.0
                
                if score > best_score:
                    best_score = score
                    for j in range(len(boundaries) - 1, -1, -1):
                        if last_s >= boundaries[j]:
                            best_word = j
                            break
            
            return best_word, best_score
        
        pred_idx, conf = simple_align(cumulative_ph, script_ph, boundaries)
        expected_idx = min(i + len(chunk) - 1, len(script_words) - 1)
        
        results.append({
            'predicted': pred_idx,
            'expected': expected_idx,
            'confidence': conf,
            'correct': pred_idx == expected_idx,
            'off_by': abs(pred_idx - expected_idx)
        })
    
    correct = sum(1 for r in results if r['correct'])
    close = sum(1 for r in results if r['off_by'] <= 1)
    total = len(results)
    
    return {
        'method': 'Basic Phoneme Similarity',
        'total_steps': total,
        'correct': correct,
        'close': close,
        'accuracy': correct / total if total > 0 else 0,
        'close_accuracy': close / total if total > 0 else 0,
        'avg_confidence': np.mean([r['confidence'] for r in results]) if results else 0,
        'results': results
    }

def test_advanced_alignment(sherpa_text: str, script_text: str) -> dict:
    """Test with ADVANCED fuzzy matching (dead reckoning)."""
    script_ph, boundaries, script_words = text_to_phonemes(script_text)
    sherpa_words = sherpa_text.lower().split()
    
    results = []
    cumulative_ph = []
    current_pos = 0
    
    # Process incrementally
    for i in range(0, len(sherpa_words), 5):
        chunk = sherpa_words[i:i+5]
        chunk_text = ' '.join(chunk)
        chunk_ph, _, _ = text_to_phonemes(chunk_text)
        
        cumulative_ph.extend(chunk_ph)
        
        # Use advanced dead reckoning alignment
        pred_idx, conf, debug = dead_reckoning_align(
            cumulative_ph,
            script_ph,
            boundaries,
            current_position=current_pos
        )
        
        current_pos = pred_idx
        expected_idx = min(i + len(chunk) - 1, len(script_words) - 1)
        
        results.append({
            'predicted': pred_idx,
            'expected': expected_idx,
            'confidence': conf,
            'correct': pred_idx == expected_idx,
            'off_by': abs(pred_idx - expected_idx),
            'debug': debug
        })
    
    correct = sum(1 for r in results if r['correct'])
    close = sum(1 for r in results if r['off_by'] <= 1)
    very_close = sum(1 for r in results if r['off_by'] <= 2)
    total = len(results)
    
    return {
        'method': 'Advanced Dead Reckoning',
        'total_steps': total,
        'correct': correct,
        'close': close,
        'very_close': very_close,
        'accuracy': correct / total if total > 0 else 0,
        'close_accuracy': close / total if total > 0 else 0,
        'very_close_accuracy': very_close / total if total > 0 else 0,
        'avg_confidence': np.mean([r['confidence'] for r in results]) if results else 0,
        'results': results
    }

def main():
    print("="*60)
    print("🧪 ADVANCED ALIGNMENT COMPARISON TEST")
    print("="*60)
    print("\nComparing BASIC vs ADVANCED fuzzy matching")
    print("Goal: Improve from 92% to 95-99% accuracy\n")
    
    # Load script
    with open('scripts/adalyn_story.txt') as f:
        script = ' '.join(f.read().strip().split())
    
    # Sherpa output from our test
    sherpa_text = "YOU ARE ADELAN AND TO DAY YOU WENT TO SEE A GLOWING TRAIL OUTSIDE YOUR WINDOW YOU PUT ON YOUR RAINBOW BOOTS AND OPEN THE DOOR THE SPARKLING PATH LEADS TO A BIG TREE YOU FOLLOW IT AND FIND A LITTLE FAIRY SHE IS SITTING ON A FLOWER THE FAIRY LOOKS AT YOU AND SMILES SHE HAS MAGIC DUST IN HER HANDS"
    
    print(f"📜 Script: {len(script.split())} words")
    print(f"🤖 Sherpa: {len(sherpa_text.split())} words")
    
    # Test 1: Basic alignment
    print(f"\n{'='*60}")
    print(f"TEST 1: BASIC PHONEME SIMILARITY")
    print(f"{'='*60}\n")
    
    basic_results = test_basic_alignment(sherpa_text, script)
    
    print(f"📊 Results:")
    print(f"   Total steps: {basic_results['total_steps']}")
    print(f"   Exact match: {basic_results['correct']}/{basic_results['total_steps']} ({100*basic_results['accuracy']:.1f}%)")
    print(f"   Within ±1 word: {basic_results['close']}/{basic_results['total_steps']} ({100*basic_results['close_accuracy']:.1f}%)")
    print(f"   Avg confidence: {basic_results['avg_confidence']:.2f}")
    
    # Test 2: Advanced alignment
    print(f"\n{'='*60}")
    print(f"TEST 2: ADVANCED DEAD RECKONING")
    print(f"{'='*60}\n")
    
    advanced_results = test_advanced_alignment(sherpa_text, script)
    
    print(f"📊 Results:")
    print(f"   Total steps: {advanced_results['total_steps']}")
    print(f"   Exact match: {advanced_results['correct']}/{advanced_results['total_steps']} ({100*advanced_results['accuracy']:.1f}%)")
    print(f"   Within ±1 word: {advanced_results['close']}/{advanced_results['total_steps']} ({100*advanced_results['close_accuracy']:.1f}%)")
    print(f"   Within ±2 words: {advanced_results['very_close']}/{advanced_results['total_steps']} ({100*advanced_results['very_close_accuracy']:.1f}%)")
    print(f"   Avg confidence: {advanced_results['avg_confidence']:.2f}")
    
    # Comparison
    print(f"\n{'='*60}")
    print(f"📈 IMPROVEMENT ANALYSIS")
    print(f"{'='*60}\n")
    
    improvement = advanced_results['close_accuracy'] - basic_results['close_accuracy']
    
    print(f"Accuracy (±1 word):")
    print(f"   Basic:    {100*basic_results['close_accuracy']:.1f}%")
    print(f"   Advanced: {100*advanced_results['close_accuracy']:.1f}%")
    print(f"   Improvement: +{100*improvement:.1f} percentage points")
    
    print(f"\nConfidence:")
    print(f"   Basic:    {basic_results['avg_confidence']:.2f}")
    print(f"   Advanced: {advanced_results['avg_confidence']:.2f}")
    
    # Show specific improvements
    print(f"\n🔍 Cases Where Advanced Method Improved:")
    for i, (basic, advanced) in enumerate(zip(basic_results['results'], advanced_results['results'])):
        if advanced['off_by'] < basic['off_by']:
            print(f"   Step {i+1}:")
            print(f"      Basic:    off by {basic['off_by']} words")
            print(f"      Advanced: off by {advanced['off_by']} words ✅")
            if 'debug' in advanced:
                debug = advanced['debug']
                print(f"      Methods agreed: SW={debug['smith_waterman'][0]}, DTW={debug['dtw'][0]}, Lev={debug['levenshtein'][0]}")
    
    # Final verdict
    print(f"\n{'='*60}")
    print(f"🎯 FINAL VERDICT")
    print(f"{'='*60}\n")
    
    if advanced_results['close_accuracy'] >= 0.95:
        print(f"✅ SUCCESS: {100*advanced_results['close_accuracy']:.1f}% accuracy!")
        print(f"   Achieved 95%+ accuracy goal! 🎉")
        print(f"   Advanced fuzzy matching works!")
    elif advanced_results['close_accuracy'] >= 0.90:
        print(f"⚠️  GOOD: {100*advanced_results['close_accuracy']:.1f}% accuracy")
        print(f"   Close to 95% target")
        print(f"   Minor tuning needed")
    else:
        print(f"⚠️  MORE WORK NEEDED: {100*advanced_results['close_accuracy']:.1f}%")
        print(f"   Need to adjust parameters")
    
    print(f"\n💡 Key Insights:")
    print(f"   1. Multiple alignment techniques vote on position")
    print(f"   2. Sequence-aware matching handles word splits")
    print(f"   3. Smith-Waterman finds anchor points")
    print(f"   4. DTW handles tempo variations")
    print(f"   5. Weighted Levenshtein tolerates phoneme errors")
    
    print(f"\n🚀 Ready for Production:")
    if advanced_results['close_accuracy'] >= 0.90:
        print(f"   ✅ Advanced method is production-ready!")
        print(f"   ✅ Port to Dart for deployment")
    else:
        print(f"   ⚠️  Need more parameter tuning first")

if __name__ == "__main__":
    main()

