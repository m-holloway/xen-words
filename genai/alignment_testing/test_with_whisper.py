#!/usr/bin/env python3
"""
Test alignment with Whisper as ground truth

Uses OpenAI's Whisper model to get accurate word timestamps,
then compares our lightweight approaches against it.
"""

import argparse
import json
import time
from pathlib import Path
from typing import List, Dict, Tuple

import librosa
import numpy as np

try:
    import whisper
    WHISPER_AVAILABLE = True
except ImportError:
    WHISPER_AVAILABLE = False
    print("⚠️  Whisper not installed. Install with: pip install openai-whisper")

from test_alignment import AlignmentTester


def get_whisper_timestamps(audio_path: str, model_size: str = "base") -> Dict:
    """
    Get word-level timestamps using Whisper
    
    Args:
        audio_path: Path to audio file
        model_size: Whisper model size (tiny, base, small, medium, large)
    
    Returns:
        Dict with transcription and word timestamps
    """
    if not WHISPER_AVAILABLE:
        raise ImportError("Whisper is not installed")
    
    print(f"\n{'='*60}")
    print(f"WHISPER GROUND TRUTH ({model_size} model)")
    print(f"{'='*60}")
    
    # Load Whisper model
    print(f"Loading Whisper {model_size} model...")
    start_time = time.time()
    model = whisper.load_model(model_size)
    load_time = time.time() - start_time
    print(f"Model loaded in {load_time:.2f}s")
    
    # Transcribe with word timestamps
    print(f"Transcribing audio...")
    start_time = time.time()
    result = model.transcribe(
        audio_path,
        word_timestamps=True,
        verbose=False,
    )
    transcribe_time = time.time() - start_time
    
    print(f"\nTranscription complete in {transcribe_time:.2f}s")
    print(f"Text: {result['text']}")
    
    # Extract word-level timestamps
    word_timestamps = []
    if 'segments' in result:
        for segment in result['segments']:
            if 'words' in segment:
                for word_info in segment['words']:
                    word_timestamps.append({
                        'word': word_info['word'].strip(),
                        'start': word_info['start'],
                        'end': word_info['end'],
                        'probability': word_info.get('probability', 1.0),
                    })
    
    print(f"Extracted {len(word_timestamps)} word timestamps")
    
    # Show first few words
    print(f"\nFirst 5 words:")
    for i, word_info in enumerate(word_timestamps[:5]):
        print(f"  {i+1}. '{word_info['word']}' at {word_info['start']:.2f}s - {word_info['end']:.2f}s")
    
    return {
        'text': result['text'],
        'words': word_timestamps,
        'model': model_size,
        'transcribe_time': transcribe_time,
    }


def compare_timestamps(
    ground_truth: List[Dict],
    predicted: List[Dict],
    tolerance_ms: float = 500,
) -> Dict:
    """
    Compare predicted timestamps against ground truth
    
    Args:
        ground_truth: List of word timestamps from Whisper
        predicted: List of word timestamps from lightweight approach
        tolerance_ms: Tolerance in milliseconds for matching
    
    Returns:
        Dict with comparison metrics
    """
    # Convert tolerance to seconds
    tolerance_s = tolerance_ms / 1000.0
    
    matches = 0
    total_error = 0.0
    errors = []
    
    # Match words (case-insensitive, strip punctuation)
    def normalize_word(w):
        import re
        return re.sub(r'[^\w]', '', w.lower())
    
    gt_words = [normalize_word(w['word']) for w in ground_truth]
    pred_words = [normalize_word(w['word']) for w in predicted]
    
    # Find matching words
    for i, gt_word in enumerate(gt_words):
        if i < len(pred_words) and gt_word == pred_words[i]:
            # Words match, check timestamp accuracy
            gt_start = ground_truth[i]['start']
            pred_start = predicted[i]['start']
            
            error = abs(gt_start - pred_start)
            total_error += error
            errors.append(error)
            
            if error <= tolerance_s:
                matches += 1
    
    if errors:
        mean_error = np.mean(errors)
        std_error = np.std(errors)
        max_error = np.max(errors)
    else:
        mean_error = std_error = max_error = 0.0
    
    return {
        'words_matched': matches,
        'total_words': len(gt_words),
        'accuracy': matches / len(gt_words) if len(gt_words) > 0 else 0,
        'mean_error_ms': mean_error * 1000,
        'std_error_ms': std_error * 1000,
        'max_error_ms': max_error * 1000,
        'tolerance_ms': tolerance_ms,
    }


def main():
    parser = argparse.ArgumentParser(description='Test alignment with Whisper ground truth')
    parser.add_argument('--audio', type=str, required=True, help='Path to audio file')
    parser.add_argument('--script', type=str, default='scripts/adalyn_story.txt', help='Path to script text')
    parser.add_argument('--whisper-model', type=str, default='base', 
                       choices=['tiny', 'base', 'small', 'medium', 'large'],
                       help='Whisper model size')
    parser.add_argument('--tolerance', type=float, default=500, 
                       help='Tolerance in ms for timestamp matching')
    parser.add_argument('--output', type=str, default='results/whisper_comparison.json',
                       help='Output file')
    
    args = parser.parse_args()
    
    if not WHISPER_AVAILABLE:
        print("\n❌ ERROR: Whisper is not installed")
        print("Install with: pip install openai-whisper")
        print("Note: This will download ~140MB for base model on first run")
        return
    
    # Load script text
    script_path = Path(args.script)
    if script_path.exists():
        script_text = script_path.read_text().strip()
    else:
        script_text = "You are Adalyn, and today you went to see a glowing trail outside your window."
    
    print(f"\n{'='*60}")
    print("ALIGNMENT TESTING WITH WHISPER GROUND TRUTH")
    print(f"{'='*60}")
    print(f"Audio: {args.audio}")
    print(f"Script: {script_text[:50]}...")
    print(f"{'='*60}\n")
    
    # Get Whisper ground truth
    whisper_result = get_whisper_timestamps(args.audio, args.whisper_model)
    
    # Test lightweight approaches
    print(f"\n{'='*60}")
    print("TESTING LIGHTWEIGHT APPROACHES")
    print(f"{'='*60}")
    
    tester = AlignmentTester(script_text)
    audio, sr = tester.load_audio(args.audio)
    results = tester.run_all_tests(audio)
    
    # Compare each approach against Whisper
    print(f"\n{'='*60}")
    print("COMPARISON VS WHISPER GROUND TRUTH")
    print(f"{'='*60}")
    
    comparisons = []
    for result in results:
        comparison = compare_timestamps(
            whisper_result['words'],
            result['timestamps'],
            args.tolerance,
        )
        
        comparison['approach'] = result['approach']
        comparisons.append(comparison)
        
        print(f"\n{result['approach']}:")
        print(f"  Words matched: {comparison['words_matched']} / {comparison['total_words']}")
        print(f"  Accuracy: {comparison['accuracy']:.1%}")
        print(f"  Mean error: {comparison['mean_error_ms']:.1f}ms")
        print(f"  Std error: {comparison['std_error_ms']:.1f}ms")
        print(f"  Max error: {comparison['max_error_ms']:.1f}ms")
    
    # Save results
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w') as f:
        json.dump({
            'audio_file': args.audio,
            'script': script_text,
            'whisper_model': args.whisper_model,
            'whisper_result': {
                'text': whisper_result['text'],
                'words_count': len(whisper_result['words']),
                'transcribe_time': whisper_result['transcribe_time'],
            },
            'lightweight_results': results,
            'comparisons': comparisons,
        }, f, indent=2)
    
    print(f"\n{'='*60}")
    print(f"Results saved to: {output_path}")
    print(f"{'='*60}")


if __name__ == '__main__':
    main()

