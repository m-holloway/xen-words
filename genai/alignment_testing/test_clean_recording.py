#!/usr/bin/env python3
"""
Simple Sanity Check: Clean Recording with Same Script

Since the recording follows the same script (with minor pronunciation differences),
we can directly compare word positions.
"""

import whisper
import numpy as np
import json
from pathlib import Path
from typing import List, Tuple
import subprocess
import sys

sys.path.append('.')
from test_phonetic_matching import word_to_phonemes, VOWELS

def convert_to_wav(input_path: str, output_path: str) -> bool:
    """Convert audio to WAV."""
    try:
        subprocess.run([
            'ffmpeg', '-i', input_path, '-ar', '16000', '-ac', '1', '-y', output_path
        ], check=True, capture_output=True, stderr=subprocess.DEVNULL)
        return True
    except:
        return False

def generate_gt(audio_path: str, output_json: str = None):
    """Generate ground truth using Whisper."""
    print(f"📥 Loading Whisper...")
    model = whisper.load_model("base")
    
    print(f"🎤 Transcribing...")
    result = model.transcribe(audio_path, word_timestamps=True, language='en')
    
    words = []
    if 'segments' in result:
        for seg in result['segments']:
            if 'words' in seg:
                for w in seg['words']:
                    words.append({
                        'word': w['word'].strip().lower(),
                        'start': w['start'],
                        'end': w['end']
                    })
    
    gt = {'text': result['text'].strip(), 'words': words}
    
    if output_json:
        with open(output_json, 'w') as f:
            json.dump(gt, f, indent=2)
    
    print(f"✅ {len(words)} words detected")
    return gt

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
    
    # Voiced/voiceless
    if (p1, p2) in [('P','B'), ('B','P'), ('T','D'), ('D','T'), 
                     ('K','G'), ('G','K'), ('F','V'), ('V','F'),
                     ('S','Z'), ('Z','S')]:
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

def main():
    print("="*60)
    print("🧪 PHONEME ALIGNMENT SANITY CHECK")
    print("="*60)
    print("\nTesting on clean recording where parent reads the script.")
    print("Expected: >85% accuracy\n")
    
    # Paths
    m4a = "../../test_audio/Clean recording.m4a"
    wav = "../../test_audio/clean_recording.wav"
    gt_json = "clean_recording_gt.json"
    
    if not Path(wav).exists():
        print("🔄 Converting to WAV...")
        convert_to_wav(m4a, wav)
    
    print(f"\n{'='*60}")
    print(f"📊 EVALUATING")
    print(f"{'='*60}\n")
    
    # Get ground truth
    if Path(gt_json).exists():
        print("📂 Loading ground truth...")
        with open(gt_json) as f:
            gt = json.load(f)
    else:
        gt = generate_gt(wav, gt_json)
    
    # Load script
    with open("scripts/adalyn_story.txt") as f:
        script = ' '.join(f.read().strip().split())
    
    script_ph, boundaries, script_words = text_to_phonemes(script)
    
    print(f"\n📜 Script: {len(script_words)} words, {len(script_ph)} phonemes")
    print(f"🎤 Ground Truth: {len(gt['words'])} words")
    print(f"\n📝 Script: \"{script[:80]}...\"")
    print(f"📝 Actual: \"{gt['text'][:80]}...\"")
    
    # Simulate streaming
    print(f"\n🎯 Testing phoneme-level alignment...")
    
    results = []
    cumulative_ph = []
    
    for i in range(0, len(gt['words']), 5):
        chunk = gt['words'][i:i+5]
        chunk_text = ' '.join([w['word'] for w in chunk])
        chunk_ph, _, _ = text_to_phonemes(chunk_text)
        
        cumulative_ph.extend(chunk_ph)
        
        # Align
        pred_idx, conf = align_phonemes(cumulative_ph, script_ph, boundaries)
        
        # Expected: same position (since same script)
        expected_idx = min(i + len(chunk) - 1, len(script_words) - 1)
        
        results.append({
            'step': len(results) + 1,
            'text': chunk_text[:40],
            'predicted': pred_idx,
            'pred_word': script_words[pred_idx] if pred_idx < len(script_words) else '?',
            'expected': expected_idx,
            'exp_word': script_words[expected_idx] if expected_idx < len(script_words) else '?',
            'confidence': conf,
            'correct': pred_idx == expected_idx,
            'off_by': abs(pred_idx - expected_idx)
        })
    
    # Analyze
    correct = sum(1 for r in results if r['correct'])
    close = sum(1 for r in results if r['off_by'] <= 1)
    very_close = sum(1 for r in results if r['off_by'] <= 2)
    total = len(results)
    
    acc = correct / total if total > 0 else 0
    close_acc = close / total if total > 0 else 0
    
    print(f"\n📈 Results:")
    print(f"   Steps: {total}")
    print(f"   Exact: {correct}/{total} ({100*acc:.1f}%)")
    print(f"   ±1 word: {close}/{total} ({100*close_acc:.1f}%)")
    print(f"   ±2 words: {very_close}/{total} ({100*very_close/total:.1f}%)")
    print(f"   Avg conf: {np.mean([r['confidence'] for r in results]):.2f}")
    
    # Details
    print(f"\n📋 Details:")
    for r in results[:12]:
        marker = "✅" if r['correct'] else "⚠️" if r['off_by'] <= 1 else "❌"
        print(f"   {marker} Step {r['step']}: \"{r['text']}...\"")
        print(f"      Pred: {r['predicted']} (\"{r['pred_word']}\"), "
              f"Exp: {r['expected']} (\"{r['exp_word']}\"), "
              f"Off: {r['off_by']}, Conf: {r['confidence']:.2f}")
    
    # Verdict
    print(f"\n{'='*60}")
    print(f"🎯 VERDICT")
    print(f"{'='*60}")
    
    if close_acc >= 0.90:
        print(f"✅ EXCELLENT: {100*close_acc:.1f}% within ±1 word!")
        print(f"   Ready for 500-sample regression test!")
    elif close_acc >= 0.80:
        print(f"⚠️  GOOD: {100*close_acc:.1f}% within ±1 word")
        print(f"   Needs minor tuning")
    elif close_acc >= 0.70:
        print(f"⚠️  MODERATE: {100*close_acc:.1f}%")
        print(f"   Needs tuning")
    else:
        print(f"❌ POOR: {100*close_acc:.1f}%")
        print(f"   Needs improvement")

if __name__ == "__main__":
    main()

