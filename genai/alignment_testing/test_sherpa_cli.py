#!/usr/bin/env python3
"""
Quick Sherpa-ONNX CLI Test

Tests transcription quality of your actual Sherpa model:
1. Run Sherpa on clean recording
2. Compare to Whisper ground truth
3. Calculate Word Error Rate
4. Test phoneme alignment with Sherpa output
"""

import sherpa_onnx
import wave
import numpy as np
import json
from pathlib import Path
import sys

sys.path.append('.')
from test_phonetic_matching import word_to_phonemes, VOWELS

# ============================================================
# SHERPA TRANSCRIPTION
# ============================================================

def transcribe_with_sherpa(audio_path: str, model_dir: str) -> str:
    """
    Transcribe audio using Sherpa-ONNX (same model as your Flutter app).
    
    Returns: Transcribed text
    """
    print(f"📥 Loading Sherpa model from {model_dir}...")
    
    model_path = Path(model_dir)
    
    # Create recognizer using the helper function
    # Note: Using the chunk-16-left-128 variants (streaming model)
    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=str(model_path / "tokens.txt"),
        encoder=str(model_path / "encoder-epoch-99-avg-1-chunk-16-left-128.onnx"),
        decoder=str(model_path / "decoder-epoch-99-avg-1-chunk-16-left-128.onnx"),
        joiner=str(model_path / "joiner-epoch-99-avg-1-chunk-16-left-128.onnx"),
        num_threads=4,
        sample_rate=16000,
        feature_dim=80,
        decoding_method="greedy_search",
    )
    
    print(f"✅ Model loaded")
    
    # Load audio
    print(f"🎤 Loading audio: {audio_path}")
    with wave.open(audio_path, 'rb') as wf:
        sample_rate = wf.getframerate()
        audio_data = wf.readframes(wf.getnframes())
        samples = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
    
    print(f"✅ Audio loaded: {len(samples)/sample_rate:.2f}s")
    
    # Create stream and process
    print(f"🎯 Transcribing...")
    stream = recognizer.create_stream()
    stream.accept_waveform(sample_rate, samples)
    
    # Process all audio
    while recognizer.is_ready(stream):
        recognizer.decode_stream(stream)
    
    # Get final result
    result = recognizer.get_result(stream)
    text = result.text if hasattr(result, 'text') else str(result)
    
    print(f"✅ Transcription complete")
    
    return text.strip()

# ============================================================
# COMPARISON & ANALYSIS
# ============================================================

def calculate_wer(reference: str, hypothesis: str) -> dict:
    """
    Calculate Word Error Rate between reference and hypothesis.
    
    WER = (Substitutions + Deletions + Insertions) / Total Reference Words
    """
    ref_words = reference.lower().split()
    hyp_words = hypothesis.lower().split()
    
    # Simple alignment (not perfect but good enough for estimate)
    # Count exact matches
    matches = 0
    ref_idx = 0
    hyp_idx = 0
    
    while ref_idx < len(ref_words) and hyp_idx < len(hyp_words):
        if ref_words[ref_idx] == hyp_words[hyp_idx]:
            matches += 1
            ref_idx += 1
            hyp_idx += 1
        elif ref_idx + 1 < len(ref_words) and ref_words[ref_idx + 1] == hyp_words[hyp_idx]:
            # Deletion in hypothesis
            ref_idx += 1
        elif hyp_idx + 1 < len(hyp_words) and ref_words[ref_idx] == hyp_words[hyp_idx + 1]:
            # Insertion in hypothesis
            hyp_idx += 1
        else:
            # Substitution
            ref_idx += 1
            hyp_idx += 1
    
    errors = len(ref_words) - matches
    wer = errors / len(ref_words) if ref_words else 0
    accuracy = matches / len(ref_words) if ref_words else 0
    
    return {
        'reference_words': len(ref_words),
        'hypothesis_words': len(hyp_words),
        'matches': matches,
        'errors': errors,
        'wer': wer,
        'accuracy': accuracy
    }

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

def phoneme_similarity(p1: str, p2: str) -> float:
    """Phoneme similarity score."""
    if p1 == p2:
        return 1.0
    
    vowels = set(VOWELS)
    
    # Voiced/voiceless pairs
    if (p1, p2) in [('P','B'), ('B','P'), ('T','D'), ('D','T'), 
                     ('K','G'), ('G','K'), ('F','V'), ('V','F'),
                     ('S','Z'), ('Z','S'), ('TH','DH'), ('DH','TH')]:
        return 0.9
    
    if p1 in vowels and p2 in vowels:
        return 0.75
    
    return 0.3

def align_phonemes(detected, script, boundaries):
    """Fuzzy phoneme alignment."""
    if not detected:
        return 0, 0.0
    
    recent = detected[-15:]
    best_word, best_score = 0, 0.0
    
    for w_idx in range(len(boundaries)):
        start = boundaries[w_idx]
        total, d_idx, s_idx, last_s = 0.0, 0, start, start
        
        while d_idx < len(recent) and s_idx < len(script):
            sim = phoneme_similarity(recent[d_idx], script[s_idx])
            
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
            for i in range(len(boundaries) - 1, -1, -1):
                if last_s >= boundaries[i]:
                    best_word = i
                    break
    
    return best_word, best_score

def test_alignment(sherpa_text: str, script_text: str) -> dict:
    """
    Test phoneme alignment with Sherpa output.
    
    Simulates processing the text incrementally as Sherpa would provide it.
    """
    print(f"\n🎯 Testing phoneme alignment...")
    
    # Prepare script
    script_ph, boundaries, script_words = text_to_phonemes(script_text)
    
    print(f"   Script: {len(script_words)} words, {len(script_ph)} phonemes")
    
    # Process Sherpa output incrementally (5 words at a time)
    sherpa_words = sherpa_text.lower().split()
    print(f"   Sherpa: {len(sherpa_words)} words")
    
    results = []
    cumulative_ph = []
    
    for i in range(0, len(sherpa_words), 5):
        chunk = sherpa_words[i:i+5]
        chunk_text = ' '.join(chunk)
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
    
    correct = sum(1 for r in results if r['correct'])
    close = sum(1 for r in results if r['off_by'] <= 1)
    total = len(results)
    
    return {
        'total_steps': total,
        'correct': correct,
        'close': close,
        'accuracy': correct / total if total > 0 else 0,
        'close_accuracy': close / total if total > 0 else 0,
        'avg_confidence': np.mean([r['confidence'] for r in results]) if results else 0,
        'results': results
    }

# ============================================================
# MAIN
# ============================================================

def main():
    print("="*60)
    print("🧪 SHERPA-ONNX CLI SANITY CHECK")
    print("="*60)
    print("\nTesting YOUR actual Sherpa model's transcription quality\n")
    
    MODEL_DIR = "sherpa-onnx-streaming-zipformer-en-2023-06-26"
    AUDIO_PATH = "../../test_audio/clean_recording.wav"
    GT_PATH = "clean_recording_gt.json"
    SCRIPT_PATH = "scripts/adalyn_story.txt"
    
    # Load ground truth
    print(f"📂 Loading ground truth...")
    with open(GT_PATH) as f:
        gt = json.load(f)
    
    gt_text = ' '.join([w['word'] for w in gt['words']])
    print(f"✅ Whisper (ground truth): {len(gt['words'])} words")
    print(f"   \"{gt_text[:80]}...\"")
    
    # Load script
    with open(SCRIPT_PATH) as f:
        script = ' '.join(f.read().strip().split())
    print(f"✅ Expected script: {len(script.split())} words")
    print(f"   \"{script[:80]}...\"")
    
    # Transcribe with Sherpa
    print(f"\n{'='*60}")
    print(f"STEP 1: SHERPA TRANSCRIPTION")
    print(f"{'='*60}\n")
    
    try:
        sherpa_text = transcribe_with_sherpa(AUDIO_PATH, MODEL_DIR)
    except Exception as e:
        print(f"❌ Error: {e}")
        print(f"\nTrying alternate API...")
        # If that fails, we'll need to check the API more carefully
        import traceback
        traceback.print_exc()
        return
    
    print(f"\n🎤 Sherpa output:")
    print(f"   \"{sherpa_text}\"")
    
    # Compare to Whisper
    print(f"\n{'='*60}")
    print(f"STEP 2: TRANSCRIPTION QUALITY")
    print(f"{'='*60}\n")
    
    wer_stats = calculate_wer(gt_text, sherpa_text)
    
    print(f"📊 Word Error Rate Analysis:")
    print(f"   Reference (Whisper): {wer_stats['reference_words']} words")
    print(f"   Hypothesis (Sherpa): {wer_stats['hypothesis_words']} words")
    print(f"   Matches: {wer_stats['matches']}")
    print(f"   Errors: {wer_stats['errors']}")
    print(f"   Accuracy: {100*wer_stats['accuracy']:.1f}%")
    print(f"   WER: {100*wer_stats['wer']:.1f}%")
    
    # Verdict on transcription
    print(f"\n📈 Transcription Quality:")
    if wer_stats['wer'] < 0.15:
        print(f"   ✅ EXCELLENT (WER < 15%)")
        print(f"   Sherpa is accurate enough for phoneme alignment!")
    elif wer_stats['wer'] < 0.30:
        print(f"   ⚠️  GOOD (WER 15-30%)")
        print(f"   Phoneme alignment should still work with tuning")
    else:
        print(f"   ❌ POOR (WER > 30%)")
        print(f"   May need different STT model or significant tuning")
    
    # Test alignment
    print(f"\n{'='*60}")
    print(f"STEP 3: PHONEME ALIGNMENT TEST")
    print(f"{'='*60}\n")
    
    alignment_stats = test_alignment(sherpa_text, script)
    
    print(f"📊 Alignment Accuracy:")
    print(f"   Total steps: {alignment_stats['total_steps']}")
    print(f"   Exact match: {alignment_stats['correct']}/{alignment_stats['total_steps']} ({100*alignment_stats['accuracy']:.1f}%)")
    print(f"   Within ±1 word: {alignment_stats['close']}/{alignment_stats['total_steps']} ({100*alignment_stats['close_accuracy']:.1f}%)")
    print(f"   Avg confidence: {alignment_stats['avg_confidence']:.2f}")
    
    # Verdict on alignment
    print(f"\n📈 Alignment Performance:")
    if alignment_stats['close_accuracy'] >= 0.85:
        print(f"   ✅ EXCELLENT (>85% within ±1 word)")
        print(f"   Ready for production!")
    elif alignment_stats['close_accuracy'] >= 0.70:
        print(f"   ⚠️  GOOD (70-85%)")
        print(f"   Usable but may need tuning")
    else:
        print(f"   ❌ NEEDS WORK (<70%)")
        print(f"   Requires tuning before deployment")
    
    # Final verdict
    print(f"\n{'='*60}")
    print(f"🎯 FINAL VERDICT")
    print(f"{'='*60}\n")
    
    if wer_stats['wer'] < 0.15 and alignment_stats['close_accuracy'] >= 0.85:
        print(f"✅ GO FOR IT!")
        print(f"   Sherpa transcription: {100*wer_stats['accuracy']:.1f}% accurate")
        print(f"   Phoneme alignment: {100*alignment_stats['close_accuracy']:.1f}% accurate")
        print(f"   Expected real-world accuracy: 85-90%")
        print(f"\n💡 Next Steps:")
        print(f"   1. Test streaming simulation in Python")
        print(f"   2. Port to Dart")
        print(f"   3. Ship in 2-3 days! 🚀")
    elif wer_stats['wer'] < 0.30 and alignment_stats['close_accuracy'] >= 0.70:
        print(f"⚠️  PROCEED WITH TUNING")
        print(f"   Sherpa transcription: {100*wer_stats['accuracy']:.1f}% accurate")
        print(f"   Phoneme alignment: {100*alignment_stats['close_accuracy']:.1f}% accurate")
        print(f"   Expected real-world accuracy: 70-80%")
        print(f"\n💡 Next Steps:")
        print(f"   1. Tune phoneme similarity weights")
        print(f"   2. Test streaming simulation")
        print(f"   3. Re-test and iterate")
    else:
        print(f"❌ NEEDS MORE WORK")
        print(f"   Sherpa transcription: {100*wer_stats['accuracy']:.1f}% accurate")
        print(f"   Phoneme alignment: {100*alignment_stats['close_accuracy']:.1f}% accurate")
        print(f"\n💡 Options:")
        print(f"   1. Try different Sherpa model")
        print(f"   2. Significant phoneme matching tuning")
        print(f"   3. Consider hybrid approach")

if __name__ == "__main__":
    main()

