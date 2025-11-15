#!/usr/bin/env python3
"""
Proof of Concept: Forced Alignment using Whisper's word-level timestamps

This demonstrates the CORRECT approach:
1. We have a known script
2. We use Whisper to get word-level timestamps
3. We match detected words to script words (forced alignment)
4. Result: Precise word tracking even with pauses, noise, etc.

This is what we SHOULD be building, not generic boundary detection!
"""

import whisper
import numpy as np
import json
from pathlib import Path

def forced_align_demo(audio_path, script_text):
    """
    Demonstrate forced alignment approach.
    
    Args:
        audio_path: Path to audio file
        script_text: Known text that should be spoken
    """
    print("=" * 60)
    print("🎯 FORCED ALIGNMENT PROOF OF CONCEPT")
    print("=" * 60)
    
    print(f"\n📜 Script (what SHOULD be said):")
    print(f"   \"{script_text}\"")
    
    script_words = script_text.lower().split()
    print(f"\n   Script has {len(script_words)} words")
    
    # Load Whisper
    print(f"\n📥 Loading Whisper model...")
    model = whisper.load_model("base")
    
    # Transcribe with word-level timestamps
    print(f"\n🎤 Transcribing audio: {audio_path}")
    result = model.transcribe(
        str(audio_path),
        word_timestamps=True,
        language='en'
    )
    
    # Extract detected words
    detected_words = []
    if 'segments' in result:
        for segment in result['segments']:
            if 'words' in segment:
                for word_info in segment['words']:
                    detected_words.append({
                        'word': word_info['word'].strip().lower(),
                        'start': word_info['start'],
                        'end': word_info['end'],
                        'confidence': word_info.get('probability', 1.0)
                    })
    
    print(f"\n🔍 Detected {len(detected_words)} words:")
    for i, w in enumerate(detected_words[:10]):
        print(f"   {i:2d}. \"{w['word']}\" @ {w['start']:.2f}s (conf: {w['confidence']:.2f})")
    if len(detected_words) > 10:
        print(f"   ... and {len(detected_words)-10} more")
    
    # FORCED ALIGNMENT: Match detected words to script
    print(f"\n🎯 FORCED ALIGNMENT:")
    print(f"   Matching detected words to script...")
    
    aligned = []
    script_idx = 0
    
    for detected in detected_words:
        # Try to match to next script word(s)
        if script_idx < len(script_words):
            script_word = script_words[script_idx]
            
            # Simple matching (could be fuzzy)
            if detected['word'] == script_word or detected['word'] in script_word or script_word in detected['word']:
                aligned.append({
                    'script_idx': script_idx,
                    'script_word': script_word,
                    'detected_word': detected['word'],
                    'start': detected['start'],
                    'end': detected['end'],
                    'match_type': 'exact' if detected['word'] == script_word else 'partial'
                })
                script_idx += 1
            else:
                # Detected word not in script (false positive or out of order)
                aligned.append({
                    'script_idx': None,
                    'script_word': None,
                    'detected_word': detected['word'],
                    'start': detected['start'],
                    'end': detected['end'],
                    'match_type': 'extra'
                })
    
    # Report alignment
    print(f"\n📊 Alignment Results:")
    print(f"   Matched: {sum(1 for a in aligned if a['script_idx'] is not None)}/{len(script_words)}")
    print(f"   Extra detections: {sum(1 for a in aligned if a['match_type'] == 'extra')}")
    
    print(f"\n✅ Aligned Words (first 10):")
    for a in aligned[:10]:
        if a['script_idx'] is not None:
            marker = "✓" if a['match_type'] == 'exact' else "~"
            print(f"   {marker} Script[{a['script_idx']:2d}]: \"{a['script_word']}\" → \"{a['detected_word']}\" @ {a['start']:.2f}s")
        else:
            print(f"   ✗ Extra: \"{a['detected_word']}\" @ {a['start']:.2f}s (not in script)")
    
    # Simulate real-time tracking
    print(f"\n🎬 SIMULATING REAL-TIME WORD TRACKING:")
    print(f"   (What the UI would show as parent reads)")
    print()
    
    for i, a in enumerate(aligned[:15]):
        if a['script_idx'] is not None:
            # Build display string
            display_words = []
            for idx in range(min(len(script_words), a['script_idx'] + 5)):
                if idx < a['script_idx']:
                    display_words.append(f"[{script_words[idx]}]")  # Read
                elif idx == a['script_idx']:
                    display_words.append(f"**{script_words[idx].upper()}**")  # Current
                else:
                    display_words.append(script_words[idx])  # Upcoming
            
            print(f"   t={a['start']:.1f}s: {' '.join(display_words[:8])}")
    
    # KEY INSIGHT
    print("\n" + "=" * 60)
    print("🔑 KEY INSIGHT")
    print("=" * 60)
    print("""
This is what we need to build:
1. Acoustic model predicts phonemes from audio (not just boundaries!)
2. Script provides constraint (words must be in order)
3. Alignment algorithm matches predictions to script
4. Output: Current word index in real-time

Benefits vs boundary detection:
✅ Knows what SHOULD be said (uses script)
✅ Recovers from errors (forward constraint)
✅ Direct word index (no post-processing)
✅ Robust to noise (script helps disambiguate)
✅ Low latency (streaming-friendly)
    """)
    
    return aligned

def main():
    # Test on your actual audio
    audio_path = Path("audio/adalyn_reading_background.wav")
    
    script_text = """
    You are Adalyn. Today you see a glowing window shimmering in your backyard.
    You put on your rainbow boots and step outside. The window smells like 
    cinnamon and sparkles. When you touch it your hand goes right through.
    """.strip()
    
    if audio_path.exists():
        aligned = forced_align_demo(audio_path, script_text)
        
        # Save results
        with open('forced_alignment_demo.json', 'w') as f:
            json.dump(aligned, f, indent=2)
        print(f"\n💾 Results saved to: forced_alignment_demo.json")
    else:
        print(f"\n⚠️  Audio file not found: {audio_path}")
        print("   Please provide path to your test audio.")

if __name__ == "__main__":
    main()

