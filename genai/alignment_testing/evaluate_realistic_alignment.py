#!/usr/bin/env python3
"""
Realistic Phoneme-Level Alignment Evaluation

Tests the REAL scenario:
- Parent is supposed to read Script A
- They actually say Script A' (with variations)
- Whisper gives us ground truth of what was ACTUALLY said
- We test: Can we track position in Script A even though they said A'?

This is the real-world test!
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

def generate_ground_truth_timings(audio_path: str, output_json: str = None) -> Dict:
    """Use Whisper to get what was ACTUALLY said with word timings."""
    print(f"📥 Loading Whisper base model...")
    model = whisper.load_model("base")
    
    print(f"🎤 Transcribing audio (this is our ground truth)...")
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
    
    gt = {
        'audio': audio_path,
        'text': result['text'].strip(),
        'words': word_timings,
        'duration': result.get('duration', 0)
    }
    
    if output_json:
        with open(output_json, 'w') as f:
            json.dump(gt, f, indent=2)
        print(f"✅ Ground truth saved: {output_json}")
    
    print(f"✅ Detected {len(word_timings)} words")
    print(f"📝 Transcription: \"{gt['text'][:100]}...\"")
    
    return gt

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
    """Calculate phoneme similarity (0.0-1.0)."""
    if p1 == p2:
        return 1.0
    
    vowels = set(VOWELS)
    stops = {'P', 'B', 'T', 'D', 'K', 'G'}
    fricatives = {'F', 'V', 'TH', 'DH', 'S', 'Z', 'SH', 'ZH', 'HH'}
    nasals = {'M', 'N', 'NG'}
    liquids = {'L', 'R'}
    
    # Voiced/voiceless pairs
    pairs = [('P','B'), ('T','D'), ('K','G'), ('F','V'), ('S','Z'), ('TH','DH')]
    for a, b in pairs:
        if (p1, p2) == (a, b) or (p1, p2) == (b, a):
            return 0.9
    
    # Same class
    if p1 in vowels and p2 in vowels:
        return 0.75
    elif p1 in stops and p2 in stops:
        return 0.8
    elif p1 in fricatives and p2 in fricatives:
        return 0.8
    elif p1 in nasals and p2 in nasals:
        return 0.85
    elif p1 in liquids and p2 in liquids:
        return 0.9
    
    return 0.3

def fuzzy_phoneme_align(
    detected_phonemes: List[str],
    script_phonemes: List[str],
    word_boundaries: List[int],
    window_size: int = 15
) -> Tuple[int, float]:
    """Align detected phonemes to script using fuzzy matching."""
    if not detected_phonemes:
        return 0, 0.0
    
    recent = detected_phonemes[-window_size:]
    best_word = 0
    best_score = 0.0
    
    # Try aligning at each position in script
    for word_idx in range(len(word_boundaries)):
        scr_start = word_boundaries[word_idx]
        score, end_ph = _score_alignment(recent, script_phonemes, scr_start)
        
        if score > best_score:
            best_score = score
            # Map phoneme position to word
            for i in range(len(word_boundaries) - 1, -1, -1):
                if end_ph >= word_boundaries[i]:
                    best_word = i
                    break
    
    return best_word, best_score

def _score_alignment(
    detected: List[str],
    script: List[str],
    start: int
) -> Tuple[float, int]:
    """Score how well detected phonemes match script starting at position."""
    total_score = 0.0
    d_idx, s_idx = 0, start
    last_s_idx = start
    
    while d_idx < len(detected) and s_idx < len(script):
        sim = phoneme_similarity(detected[d_idx], script[s_idx])
        
        if sim > 0.7:
            # Good match
            total_score += sim
            last_s_idx = s_idx
            d_idx += 1
            s_idx += 1
        elif sim > 0.5:
            # Moderate match
            total_score += sim * 0.8
            last_s_idx = s_idx
            d_idx += 1
            s_idx += 1
        else:
            # Poor match - skip detected phoneme (likely noise/extra word)
            d_idx += 1
    
    avg_score = (total_score / len(detected)) if detected else 0.0
    return avg_score, last_s_idx

def align_sequences_for_eval(gt_words: List[str], script_words: List[str]) -> List[Tuple[int, int]]:
    """
    Align ground truth words to script words to establish expected positions.
    
    Returns: List of (gt_word_idx, expected_script_word_idx)
    """
    # Simple greedy alignment
    alignments = []
    script_idx = 0
    
    for gt_idx, gt_word in enumerate(gt_words):
        # Find best match in script starting from current position
        best_match = script_idx
        best_score = 0.0
        
        for s_idx in range(script_idx, min(script_idx + 10, len(script_words))):
            # Word similarity (simple string match for now)
            if gt_word == script_words[s_idx]:
                best_match = s_idx
                best_score = 1.0
                break
            elif gt_word.startswith(script_words[s_idx][:3]) or script_words[s_idx].startswith(gt_word[:3]):
                score = 0.8
                if score > best_score:
                    best_match = s_idx
                    best_score = score
        
        alignments.append((gt_idx, best_match))
        
        # Advance script position
        if best_score > 0.5:
            script_idx = best_match + 1
    
    return alignments

def evaluate_alignment(
    audio_path: str,
    script_text: str,
    gt_json: str = None
) -> Dict:
    """
    Evaluate phoneme-level alignment.
    
    Args:
        audio_path: Path to audio file
        script_text: The intended script (what parent should read)
        gt_json: Path to save/load ground truth
    
    Returns:
        Evaluation results
    """
    print(f"\n{'='*60}")
    print(f"📊 EVALUATING: {Path(audio_path).name}")
    print(f"{'='*60}\n")
    
    # Generate ground truth (what was ACTUALLY said)
    if gt_json and Path(gt_json).exists():
        print(f"📂 Loading existing ground truth...")
        with open(gt_json) as f:
            gt = json.load(f)
    else:
        gt = generate_ground_truth_timings(audio_path, gt_json)
    
    # Script (what parent SHOULD read)
    script_phonemes, script_boundaries, script_words = text_to_phonemes(script_text)
    
    print(f"\n📜 Expected Script:")
    print(f"   {len(script_words)} words: \"{script_text[:80]}...\"")
    print(f"   {len(script_phonemes)} phonemes")
    
    print(f"\n🎤 Actual (Ground Truth):")
    gt_text = ' '.join([w['word'] for w in gt['words']])
    print(f"   {len(gt['words'])} words: \"{gt['text'][:80]}...\"")
    
    # Align GT words to script words to establish expected positions
    gt_words = [w['word'] for w in gt['words']]
    expected_alignments = align_sequences_for_eval(gt_words, script_words)
    
    print(f"\n🎯 Simulating Streaming Alignment...")
    print(f"   (Processing in chunks, as Sherpa would provide partial results)")
    
    # Simulate streaming
    results = []
    cumulative_phonemes = []
    
    chunk_size = 5
    for i in range(0, len(gt['words']), chunk_size):
        chunk = gt['words'][i:i+chunk_size]
        chunk_text = ' '.join([w['word'] for w in chunk])
        chunk_phonemes, _, _ = text_to_phonemes(chunk_text)
        
        cumulative_phonemes.extend(chunk_phonemes)
        
        # Align to script
        pred_word_idx, confidence = fuzzy_phoneme_align(
            cumulative_phonemes,
            script_phonemes,
            script_boundaries,
            window_size=15
        )
        
        # Expected position (from alignment)
        last_gt_idx = min(i + len(chunk) - 1, len(gt_words) - 1)
        expected_idx = expected_alignments[last_gt_idx][1] if last_gt_idx < len(expected_alignments) else len(script_words) - 1
        
        results.append({
            'step': len(results) + 1,
            'detected_text': chunk_text[:40],
            'predicted_word_idx': pred_word_idx,
            'predicted_word': script_words[pred_word_idx] if pred_word_idx < len(script_words) else '?',
            'expected_word_idx': expected_idx,
            'expected_word': script_words[expected_idx] if expected_idx < len(script_words) else '?',
            'confidence': confidence,
            'correct': pred_word_idx == expected_idx,
            'off_by': abs(pred_word_idx - expected_idx),
            'gt_words_processed': last_gt_idx + 1
        })
    
    # Analyze results
    correct = sum(1 for r in results if r['correct'])
    close = sum(1 for r in results if r['off_by'] <= 1)
    very_close = sum(1 for r in results if r['off_by'] <= 2)
    total = len(results)
    
    accuracy = correct / total if total > 0 else 0
    close_acc = close / total if total > 0 else 0
    very_close_acc = very_close / total if total > 0 else 0
    avg_conf = np.mean([r['confidence'] for r in results])
    
    print(f"\n📈 Results:")
    print(f"   Total steps: {total}")
    print(f"   Exact match: {correct}/{total} ({100*accuracy:.1f}%)")
    print(f"   Within ±1 word: {close}/{total} ({100*close_acc:.1f}%)")
    print(f"   Within ±2 words: {very_close}/{total} ({100*very_close_acc:.1f}%)")
    print(f"   Avg confidence: {avg_conf:.2f}")
    
    # Show step-by-step
    print(f"\n📋 Step-by-Step Results:")
    for r in results[:10]:
        marker = "✅" if r['correct'] else "⚠️" if r['off_by'] <= 1 else "❌"
        print(f"   {marker} Step {r['step']}: \"{r['detected_text']}...\"")
        print(f"      → Pred: word {r['predicted_word_idx']} (\"{r['predicted_word']}\"), "
              f"Exp: word {r['expected_word_idx']} (\"{r['expected_word']}\"), "
              f"Conf: {r['confidence']:.2f}")
    
    if len(results) > 10:
        print(f"   ... and {len(results) - 10} more steps")
    
    return {
        'audio': audio_path,
        'script': script_text[:50],
        'total_steps': total,
        'correct': correct,
        'close': close,
        'accuracy': accuracy,
        'close_accuracy': close_acc,
        'very_close_accuracy': very_close_acc,
        'avg_confidence': avg_conf,
        'results': results
    }

def main():
    print("="*60)
    print("🧪 REALISTIC PHONEME-LEVEL ALIGNMENT TEST")
    print("="*60)
    print("\nThis tests real-world scenario:")
    print("- Parent reads Script A")
    print("- They actually say A' (with variations)")
    print("- Can we track position in Script A?")
    print("\nExpected: >85% accuracy on clean recordings\n")
    
    # Clean recording
    m4a_path = "../../test_audio/Clean recording.m4a"
    wav_path = "../../test_audio/clean_recording.wav"
    gt_json = "clean_recording_gt.json"
    
    if not Path(wav_path).exists():
        print(f"🔄 Converting M4A to WAV...")
        if not convert_to_wav(m4a_path, wav_path):
            print(f"❌ Conversion failed")
            return
        print(f"✅ Converted to WAV")
    
    # Script from adalyn_story.txt
    script_path = "scripts/adalyn_story.txt"
    with open(script_path) as f:
        script = f.read().strip()
    
    # Normalize script
    script = ' '.join(script.split())
    
    # Evaluate
    result = evaluate_alignment(wav_path, script, gt_json)
    
    # Verdict
    print(f"\n{'='*60}")
    print(f"🎯 SANITY CHECK VERDICT")
    print(f"{'='*60}")
    
    if result['close_accuracy'] >= 0.90:
        print(f"✅ EXCELLENT: {100*result['close_accuracy']:.1f}% within ±1 word!")
        print(f"   (Exact: {100*result['accuracy']:.1f}%)")
        print(f"   Algorithm works great even with variations.")
        print(f"   Ready for full 500-sample regression test!")
    elif result['close_accuracy'] >= 0.80:
        print(f"⚠️  GOOD: {100*result['close_accuracy']:.1f}% within ±1 word")
        print(f"   (Exact: {100*result['accuracy']:.1f}%)")
        print(f"   Needs minor tuning but fundamentally works.")
    elif result['close_accuracy'] >= 0.70:
        print(f"⚠️  MODERATE: {100*result['close_accuracy']:.1f}% within ±1 word")
        print(f"   (Exact: {100*result['accuracy']:.1f}%)")
        print(f"   Needs tuning before full regression.")
    else:
        print(f"❌ POOR: {100*result['close_accuracy']:.1f}% within ±1 word")
        print(f"   (Exact: {100*result['accuracy']:.1f}%)")
        print(f"   Algorithm needs significant improvement.")
    
    print(f"\n💡 Next Steps:")
    if result['close_accuracy'] >= 0.80:
        print(f"   ✅ Sanity check passed!")
        print(f"   → Run full regression on 500 LibriSpeech samples")
        print(f"   → Expected: 85-90% accuracy across diverse audio")
    else:
        print(f"   → Tune phoneme similarity scores")
        print(f"   → Adjust window size")
        print(f"   → Re-run sanity check")

if __name__ == "__main__":
    main()

