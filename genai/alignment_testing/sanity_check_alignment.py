#!/usr/bin/env python3
"""
Sanity Check: Test phoneme-level alignment when script matches audio

This validates the algorithm by using Whisper's transcription as BOTH:
1. Ground truth (word timings)
2. Expected script

If the parent reads the script perfectly, we should get ~100% accuracy.
"""

import whisper
import numpy as np
import json
from pathlib import Path
from typing import List, Tuple, Dict
import subprocess
import sys

sys.path.append('.')
from test_phonetic_matching import word_to_phonemes, VOWELS

def convert_to_wav(input_path: str, output_path: str) -> bool:
    """Convert audio to 16kHz mono WAV."""
    try:
        subprocess.run([
            'ffmpeg', '-i', input_path,
            '-ar', '16000', '-ac', '1', '-y', output_path
        ], check=True, capture_output=True, stderr=subprocess.DEVNULL)
        return True
    except:
        return False

def generate_ground_truth(audio_path: str) -> Dict:
    """Generate ground truth using Whisper."""
    print(f"📥 Loading Whisper...")
    model = whisper.load_model("base")
    
    print(f"🎤 Transcribing...")
    result = model.transcribe(audio_path, word_timestamps=True, language='en')
    
    word_timings = []
    if 'segments' in result:
        for segment in result['segments']:
            if 'words' in segment:
                for w in segment['words']:
                    word_timings.append({
                        'word': w['word'].strip().lower(),
                        'start': w['start'],
                        'end': w['end']
                    })
    
    return {
        'text': result['text'].strip(),
        'words': word_timings,
        'duration': result.get('duration', 0)
    }

def text_to_phonemes(text: str) -> Tuple[List[str], List[int], List[str]]:
    """Convert text to phonemes with word boundaries."""
    words = text.lower().split()
    phonemes = []
    boundaries = [0]
    
    for word in words:
        word_phonemes = word_to_phonemes(word)
        phonemes.extend(word_phonemes)
        boundaries.append(len(phonemes))
    
    return phonemes, boundaries[:-1], words

def phoneme_similarity(p1: str, p2: str) -> float:
    """Phoneme similarity score."""
    if p1 == p2:
        return 1.0
    
    vowels = set(VOWELS)
    
    # Voiced/voiceless pairs
    pairs = [('P','B'), ('T','D'), ('K','G'), ('F','V'), ('S','Z'), ('TH','DH')]
    for a, b in pairs:
        if (p1, p2) == (a, b) or (p1, p2) == (b, a):
            return 0.9
    
    # Same class
    if p1 in vowels and p2 in vowels:
        return 0.75
    
    return 0.3

def fuzzy_align(detected: List[str], script: List[str], boundaries: List[int]) -> Tuple[int, float]:
    """Align detected phonemes to script."""
    if not detected:
        return 0, 0.0
    
    recent = detected[-15:]  # Window
    best_word = 0
    best_score = 0.0
    
    for word_idx in range(len(boundaries)):
        scr_start = boundaries[word_idx]
        score, end_ph = _score(recent, script, scr_start)
        
        if score > best_score:
            best_score = score
            for i in range(len(boundaries) - 1, -1, -1):
                if end_ph >= boundaries[i]:
                    best_word = i
                    break
    
    return best_word, best_score

def _score(detected: List[str], script: List[str], start: int) -> Tuple[float, int]:
    """Score alignment."""
    total = 0.0
    d_idx, s_idx = 0, start
    last_s = start
    
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

def evaluate(audio_path: str) -> Dict:
    """Evaluate alignment on audio."""
    print(f"\n{'='*60}")
    print(f"📊 EVALUATING: {Path(audio_path).name}")
    print(f"{'='*60}\n")
    
    # Generate ground truth
    gt = generate_ground_truth(audio_path)
    
    print(f"✅ Transcribed {len(gt['words'])} words")
    print(f"📜 Text: \"{gt['text'][:80]}...\"")
    
    # Use transcription as script (perfect match scenario)
    script_text = ' '.join([w['word'] for w in gt['words']])
    script_phonemes, boundaries, script_words = text_to_phonemes(script_text)
    
    print(f"\n🎯 Testing phoneme-level alignment...")
    print(f"   Script: {len(script_words)} words, {len(script_phonemes)} phonemes")
    
    # Simulate streaming by processing incrementally
    results = []
    cumulative_phonemes = []
    
    for i in range(0, len(gt['words']), 5):  # 5 words at a time
        chunk = gt['words'][i:i+5]
        chunk_text = ' '.join([w['word'] for w in chunk])
        chunk_phonemes, _, _ = text_to_phonemes(chunk_text)
        
        cumulative_phonemes.extend(chunk_phonemes)
        
        # Align
        pred_word_idx, confidence = fuzzy_align(
            cumulative_phonemes,
            script_phonemes,
            boundaries
        )
        
        expected_idx = min(i + len(chunk) - 1, len(script_words) - 1)
        
        results.append({
            'step': len(results) + 1,
            'detected': chunk_text,
            'predicted': pred_word_idx,
            'expected': expected_idx,
            'confidence': confidence,
            'correct': pred_word_idx == expected_idx,
            'off_by': abs(pred_word_idx - expected_idx)
        })
    
    # Analyze
    correct = sum(1 for r in results if r['correct'])
    close = sum(1 for r in results if r['off_by'] <= 1)
    total = len(results)
    
    accuracy = correct / total if total > 0 else 0
    close_acc = close / total if total > 0 else 0
    
    print(f"\n📈 Results:")
    print(f"   Steps: {total}")
    print(f"   Exact: {correct}/{total} ({100*accuracy:.1f}%)")
    print(f"   ±1 word: {close}/{total} ({100*close_acc:.1f}%)")
    print(f"   Avg confidence: {np.mean([r['confidence'] for r in results]):.2f}")
    
    # Show details
    print(f"\n📋 Details:")
    for r in results[:8]:
        marker = "✅" if r['correct'] else "⚠️" if r['off_by'] <= 1 else "❌"
        print(f"   {marker} Step {r['step']}: \"{r['detected'][:30]}...\"")
        print(f"      Pred: {r['predicted']}, Exp: {r['expected']}, Conf: {r['confidence']:.2f}")
    
    if len(results) > 8:
        print(f"   ... and {len(results) - 8} more")
    
    return {
        'accuracy': accuracy,
        'close_accuracy': close_acc,
        'total': total,
        'correct': correct,
        'close': close
    }

def main():
    print("="*60)
    print("🧪 PHONEME ALIGNMENT SANITY CHECK")
    print("="*60)
    print("\nThis tests the algorithm when parent reads the script perfectly.")
    print("Expected: >95% accuracy on clean recordings.\n")
    
    # Test clean recording
    m4a_path = "../../test_audio/Clean recording.m4a"
    wav_path = "../../test_audio/clean_recording.wav"
    
    if not Path(wav_path).exists():
        print(f"🔄 Converting to WAV...")
        if not convert_to_wav(m4a_path, wav_path):
            print(f"❌ Conversion failed")
            return
    
    result = evaluate(wav_path)
    
    # Verdict
    print(f"\n{'='*60}")
    print(f"🎯 VERDICT")
    print(f"{'='*60}")
    
    if result['accuracy'] >= 0.95:
        print(f"✅ EXCELLENT: {100*result['accuracy']:.1f}% accuracy!")
        print(f"   Algorithm is working correctly.")
        print(f"   Ready for full regression test on 500 samples.")
    elif result['accuracy'] >= 0.85:
        print(f"⚠️  GOOD: {100*result['accuracy']:.1f}% accuracy")
        print(f"   Needs minor tuning but fundamentally works.")
    elif result['accuracy'] >= 0.70:
        print(f"⚠️  MODERATE: {100*result['accuracy']:.1f}% accuracy")
        print(f"   Needs tuning before full regression.")
    else:
        print(f"❌ POOR: {100*result['accuracy']:.1f}% accuracy")
        print(f"   Algorithm needs debugging.")
    
    print(f"\n💡 Next:")
    if result['accuracy'] >= 0.85:
        print(f"   Run full regression: python run_full_regression.py")
    else:
        print(f"   Tune parameters and re-test")

if __name__ == "__main__":
    main()

