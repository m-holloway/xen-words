#!/usr/bin/env python3
"""
Generate ground truth word timings using Whisper word-level timestamps.
This gives us the ACTUAL timing of each word in the audio for accuracy testing.
"""

import whisper
import json
from pathlib import Path

def get_word_timings(audio_path: str, script_path: str):
    """
    Get ground truth word timings using Whisper word-level timestamps.
    
    Returns:
        List of dicts with {word, start, end, index_in_script}
    """
    print(f"\n🎤 Loading Whisper model...")
    model = whisper.load_model("base")
    
    print(f"🎧 Transcribing audio: {audio_path}")
    result = model.transcribe(
        audio_path,
        word_timestamps=True,
        language="en"
    )
    
    # Load script
    with open(script_path, 'r') as f:
        script_text = f.read()
    
    script_words = [w.lower() for w in script_text.split() if w.strip()]
    
    print(f"\n📝 Script has {len(script_words)} words")
    print(f"   First 10: {' '.join(script_words[:10])}")
    
    # Extract word timings from Whisper result
    ground_truth = []
    
    for segment in result['segments']:
        if 'words' not in segment:
            continue
            
        for word_info in segment['words']:
            word = word_info['word'].strip().lower()
            start = word_info['start']
            end = word_info['end']
            
            # Try to find this word in the script
            # Look for best match position
            best_match_idx = None
            for i, script_word in enumerate(script_words):
                if script_word in word or word in script_word:
                    best_match_idx = i
                    break
            
            ground_truth.append({
                'word': word,
                'start': start,
                'end': end,
                'duration': end - start,
                'script_index': best_match_idx,
                'script_word': script_words[best_match_idx] if best_match_idx is not None else None
            })
    
    print(f"\n✅ Extracted {len(ground_truth)} words from audio")
    
    # Print first few
    print("\n📊 First 10 words with timings:")
    for i, wt in enumerate(ground_truth[:10]):
        print(f"   {i+1}. '{wt['word']}' at {wt['start']:.2f}s (script: {wt['script_word']})")
    
    return ground_truth, script_words


def save_ground_truth(ground_truth, script_words, output_path: str):
    """Save ground truth to JSON file."""
    data = {
        'script_words': script_words,
        'word_timings': ground_truth,
        'total_words': len(ground_truth),
        'script_length': len(script_words)
    }
    
    with open(output_path, 'w') as f:
        json.dump(data, f, indent=2)
    
    print(f"\n💾 Saved ground truth to: {output_path}")


if __name__ == "__main__":
    # Process the Adalyn story audio
    audio_file = "audio/adalyn_reading_background.wav"
    script_file = "scripts/adalyn_story.txt"
    output_file = "ground_truth_timings.json"
    
    print("=" * 60)
    print("🎯 GROUND TRUTH EXTRACTION")
    print("=" * 60)
    
    if not Path(audio_file).exists():
        print(f"❌ Audio file not found: {audio_file}")
        print("\n📝 Please ensure audio file exists at:")
        print(f"   {Path(audio_file).absolute()}")
        exit(1)
    
    if not Path(script_file).exists():
        print(f"❌ Script file not found: {script_file}")
        exit(1)
    
    # Get ground truth
    ground_truth, script_words = get_word_timings(audio_file, script_file)
    
    # Save to JSON
    save_ground_truth(ground_truth, script_words, output_file)
    
    print("\n✅ Ground truth extraction complete!")
    print("\n📈 Next steps:")
    print("   1. Run: python test_alignment_accuracy.py")
    print("   2. This will test VAD+Syllable against ground truth")
    print("   3. We'll get REAL accuracy metrics!")

