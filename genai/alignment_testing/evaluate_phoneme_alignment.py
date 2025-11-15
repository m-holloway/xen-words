#!/usr/bin/env python3
"""
Complete Phoneme-Level Alignment Evaluation

Tests phoneme-level forced alignment:
1. Sanity check on clean recording (should be 100%)
2. Full regression on 500 LibriSpeech samples
"""

import whisper
import numpy as np
import json
from pathlib import Path
from typing import List, Tuple, Dict
import sys
import subprocess

# Import our phoneme matching code
sys.path.append('.')
from test_phonetic_matching import word_to_phonemes, CMU_DICT, VOWELS

def convert_audio_to_wav(input_path: str, output_path: str) -> bool:
    """Convert M4A/other to WAV using ffmpeg."""
    try:
        subprocess.run([
            'ffmpeg', '-i', input_path,
            '-ar', '16000',  # 16kHz
            '-ac', '1',       # Mono
            '-y',             # Overwrite
            output_path
        ], check=True, capture_output=True)
        return True
    except Exception as e:
        print(f"⚠️  Conversion failed: {e}")
        return False

def generate_ground_truth(audio_path: str, output_path: str) -> Dict:
    """Generate word-level ground truth using Whisper."""
    print(f"📥 Loading Whisper model...")
    model = whisper.load_model("base")
    
    print(f"🎤 Transcribing: {audio_path}")
    result = model.transcribe(
        audio_path,
        word_timestamps=True,
        language='en'
    )
    
    # Extract word timings
    word_timings = []
    if 'segments' in result:
        for segment in result['segments']:
            if 'words' in segment:
                for word_info in segment['words']:
                    word_timings.append({
                        'word': word_info['word'].strip().lower(),
                        'start': word_info['start'],
                        'end': word_info['end'],
                        'confidence': word_info.get('probability', 1.0)
                    })
    
    ground_truth = {
        'audio': audio_path,
        'text': result['text'],
        'words': word_timings,
        'duration': result.get('duration', 0)
    }
    
    # Save
    with open(output_path, 'w') as f:
        json.dump(ground_truth, f, indent=2)
    
    print(f"✅ Ground truth saved: {output_path}")
    print(f"   Detected {len(word_timings)} words")
    print(f"   Text: \"{result['text']}\"")
    
    return ground_truth

def text_to_phoneme_sequence(text: str) -> Tuple[List[str], List[int], List[str]]:
    """
    Convert text to phoneme sequence with word boundaries.
    
    Returns: (phonemes, word_boundaries, words)
    """
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
    if (p1, p2) in [('P', 'B'), ('B', 'P'), ('T', 'D'), ('D', 'T'), 
                     ('K', 'G'), ('G', 'K'), ('F', 'V'), ('V', 'F'),
                     ('S', 'Z'), ('Z', 'S'), ('TH', 'DH'), ('DH', 'TH')]:
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
    
    # Use sliding window
    recent = detected_phonemes[-window_size:]
    
    best_word_idx = 0
    best_score = 0.0
    
    # Try aligning at each position
    for word_idx in range(len(word_boundaries)):
        script_start = word_boundaries[word_idx]
        
        score, end_phoneme = _score_alignment(recent, script_phonemes, script_start)
        
        if score > best_score:
            best_score = score
            # Find word for this phoneme position
            for i in range(len(word_boundaries) - 1, -1, -1):
                if end_phoneme >= word_boundaries[i]:
                    best_word_idx = i
                    break
    
    return best_word_idx, best_score

def _score_alignment(
    detected: List[str],
    script: List[str],
    script_start: int
) -> Tuple[float, int]:
    """Score alignment starting at position."""
    total_score = 0.0
    det_idx = 0
    scr_idx = script_start
    last_scr_idx = script_start
    
    while det_idx < len(detected) and scr_idx < len(script):
        sim = phoneme_similarity(detected[det_idx], script[scr_idx])
        
        if sim > 0.7:
            total_score += sim
            last_scr_idx = scr_idx
            det_idx += 1
            scr_idx += 1
        elif sim > 0.5:
            total_score += sim * 0.8
            last_scr_idx = scr_idx
            det_idx += 1
            scr_idx += 1
        else:
            # Try skipping detected phoneme
            det_idx += 1
    
    avg_score = total_score / len(detected) if detected else 0.0
    return avg_score, last_scr_idx

def simulate_streaming_alignment(
    ground_truth: Dict,
    script_text: str,
    chunk_size: int = 5  # Process 5 words at a time
) -> List[Dict]:
    """
    Simulate streaming alignment as if Sherpa was providing partial results.
    
    Returns list of alignment results at each step.
    """
    # Prepare script
    script_phonemes, word_boundaries, script_words = text_to_phoneme_sequence(script_text)
    
    # Simulate streaming by processing ground truth words incrementally
    gt_words = ground_truth['words']
    results = []
    detected_phonemes_cumulative = []
    
    for i in range(0, len(gt_words), chunk_size):
        # Simulate receiving next chunk of words
        chunk = gt_words[i:i+chunk_size]
        chunk_text = ' '.join([w['word'] for w in chunk])
        
        # Phonemize this chunk
        chunk_phonemes, _, _ = text_to_phoneme_sequence(chunk_text)
        detected_phonemes_cumulative.extend(chunk_phonemes)
        
        # Align
        word_idx, confidence = fuzzy_phoneme_align(
            detected_phonemes_cumulative,
            script_phonemes,
            word_boundaries,
            window_size=15
        )
        
        # Expected position (last word in chunk)
        expected_idx = min(i + len(chunk) - 1, len(script_words) - 1)
        
        results.append({
            'detected_text': chunk_text,
            'predicted_word_idx': word_idx,
            'predicted_word': script_words[word_idx] if word_idx < len(script_words) else '?',
            'expected_word_idx': expected_idx,
            'expected_word': script_words[expected_idx] if expected_idx < len(script_words) else '?',
            'confidence': confidence,
            'correct': word_idx == expected_idx,
            'off_by': abs(word_idx - expected_idx) if word_idx < len(script_words) else 999
        })
    
    return results

def evaluate_sample(audio_path: str, script_text: str, ground_truth_path: str = None) -> Dict:
    """Evaluate alignment on a single sample."""
    print("\n" + "="*60)
    print(f"📊 EVALUATING: {audio_path}")
    print("="*60)
    
    # Generate or load ground truth
    if ground_truth_path and Path(ground_truth_path).exists():
        print(f"📂 Loading existing ground truth...")
        with open(ground_truth_path) as f:
            ground_truth = json.load(f)
    else:
        ground_truth = generate_ground_truth(audio_path, ground_truth_path or 'temp_gt.json')
    
    print(f"\n📜 Script:")
    print(f"   \"{script_text}\"")
    
    print(f"\n🎤 Ground Truth:")
    print(f"   \"{ground_truth['text']}\"")
    
    # Simulate streaming alignment
    print(f"\n🎯 Simulating Streaming Alignment...")
    results = simulate_streaming_alignment(ground_truth, script_text, chunk_size=5)
    
    # Analyze results
    correct = sum(1 for r in results if r['correct'])
    close = sum(1 for r in results if r['off_by'] <= 1)
    total = len(results)
    
    accuracy = correct / total if total > 0 else 0
    close_accuracy = close / total if total > 0 else 0
    
    print(f"\n📈 Results:")
    print(f"   Total steps: {total}")
    print(f"   Exact match: {correct}/{total} ({100*accuracy:.1f}%)")
    print(f"   Within 1 word: {close}/{total} ({100*close_accuracy:.1f}%)")
    print(f"   Avg confidence: {np.mean([r['confidence'] for r in results]):.2f}")
    
    # Show step-by-step
    print(f"\n📋 Step-by-Step:")
    for i, r in enumerate(results[:10]):  # Show first 10
        marker = "✅" if r['correct'] else "⚠️" if r['off_by'] <= 1 else "❌"
        print(f"   {marker} Step {i+1}: \"{r['detected_text'][:30]}...\"")
        print(f"      → Predicted: word {r['predicted_word_idx']} (\"{r['predicted_word']}\")")
        print(f"      → Expected:  word {r['expected_word_idx']} (\"{r['expected_word']}\")")
        print(f"      → Confidence: {r['confidence']:.2f}")
    
    if len(results) > 10:
        print(f"   ... and {len(results) - 10} more steps")
    
    return {
        'audio': audio_path,
        'total_steps': total,
        'correct': correct,
        'close': close,
        'accuracy': accuracy,
        'close_accuracy': close_accuracy,
        'avg_confidence': np.mean([r['confidence'] for r in results]),
        'results': results
    }

def main():
    print("="*60)
    print("🧪 PHONEME-LEVEL ALIGNMENT EVALUATION")
    print("="*60)
    
    # Step 1: Sanity check on clean recording
    print("\n" + "="*60)
    print("STEP 1: SANITY CHECK (Clean Recording)")
    print("="*60)
    
    clean_recording_m4a = "../../test_audio/Clean recording.m4a"
    clean_recording_wav = "../../test_audio/clean_recording.wav"
    
    # Convert to WAV if needed
    if not Path(clean_recording_wav).exists():
        print(f"🔄 Converting M4A to WAV...")
        if not convert_audio_to_wav(clean_recording_m4a, clean_recording_wav):
            print(f"❌ Failed to convert audio")
            return
    
    # Script for Adalyn story
    adalyn_script = """you are adalyn today you see a glowing window shimmering 
    in your backyard you put on your rainbow boots and step outside"""
    adalyn_script = ' '.join(adalyn_script.split())  # Normalize whitespace
    
    # Evaluate
    sanity_result = evaluate_sample(
        clean_recording_wav,
        adalyn_script,
        ground_truth_path='clean_recording_gt.json'
    )
    
    # Verdict
    print("\n" + "="*60)
    print("🎯 SANITY CHECK VERDICT")
    print("="*60)
    if sanity_result['accuracy'] >= 0.95:
        print(f"✅ EXCELLENT: {100*sanity_result['accuracy']:.1f}% accuracy")
        print(f"   Clean recording → near-perfect alignment!")
    elif sanity_result['accuracy'] >= 0.85:
        print(f"⚠️  GOOD: {100*sanity_result['accuracy']:.1f}% accuracy")
        print(f"   May need tuning but fundamentally works")
    else:
        print(f"❌ POOR: {100*sanity_result['accuracy']:.1f}% accuracy")
        print(f"   Algorithm needs improvement before testing on 500 samples")
        return
    
    # Step 2: Ask if user wants to run full regression
    print("\n" + "="*60)
    print("STEP 2: FULL REGRESSION TEST")
    print("="*60)
    print(f"Ready to test on 500 LibriSpeech samples...")
    print(f"This will take ~30-60 minutes.")
    print(f"\nTo run regression test:")
    print(f"  python evaluate_phoneme_alignment.py --full-test")

if __name__ == "__main__":
    import sys
    
    if '--full-test' in sys.argv:
        print("Running full regression test...")
        # TODO: Implement full test
        print("(Full test not yet implemented - needs integration with 500 samples)")
    else:
        main()

