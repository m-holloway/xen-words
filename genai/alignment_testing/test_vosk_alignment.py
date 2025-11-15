#!/usr/bin/env python3
"""
Quick Vosk Forced Alignment POC

Test if Vosk can do forced alignment on parent reading audio.
This uses grammar constraints to force Vosk to only recognize script words.
"""

import json
import wave

try:
    from vosk import Model, KaldiRecognizer, SetLogLevel
    VOSK_AVAILABLE = True
except ImportError:
    VOSK_AVAILABLE = False
    print("⚠️  Vosk not installed. Install with: pip install vosk")

def test_vosk_alignment(audio_path, script_text):
    """
    Test Vosk forced alignment on audio file.
    
    Args:
        audio_path: Path to WAV file (16kHz, mono)
        script_text: Known text that should be spoken
    """
    if not VOSK_AVAILABLE:
        print("\n❌ Vosk not installed.")
        print("   Install with: pip install vosk")
        print("   Then download model:")
        print("   wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip")
        print("   unzip vosk-model-small-en-us-0.15.zip")
        return
    
    print("=" * 60)
    print("🎯 VOSK FORCED ALIGNMENT TEST")
    print("=" * 60)
    
    # Check for model
    import os
    model_path = "vosk-model-small-en-us-0.15"
    if not os.path.exists(model_path):
        print(f"\n❌ Vosk model not found: {model_path}")
        print("   Download with:")
        print("   wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip")
        print("   unzip vosk-model-small-en-us-0.15.zip")
        return
    
    print(f"\n📜 Script:")
    print(f"   \"{script_text}\"")
    
    script_words = script_text.lower().split()
    print(f"   {len(script_words)} words")
    
    # Load model
    print(f"\n📥 Loading Vosk model...")
    SetLogLevel(-1)  # Suppress verbose logs
    model = Model(model_path)
    print(f"   Model loaded: {model_path}")
    print(f"   Model size: ~40 MB")
    
    # Open audio
    print(f"\n🎤 Processing audio: {audio_path}")
    wf = wave.open(audio_path, "rb")
    
    if wf.getnchannels() != 1 or wf.getsampwidth() != 2 or wf.getframerate() != 16000:
        print(f"   ⚠️  Audio format: {wf.getnchannels()} channels, {wf.getframerate()} Hz")
        print(f"   ⚠️  Vosk requires: 1 channel, 16000 Hz")
        print(f"   ⚠️  Results may be inaccurate. Convert with:")
        print(f"   ffmpeg -i input.wav -ar 16000 -ac 1 output.wav")
    
    # Create recognizer with word timestamps
    rec = KaldiRecognizer(model, wf.getframerate())
    rec.SetWords(True)  # Enable word-level timestamps
    
    # TEST 1: Full transcription (no constraints)
    print(f"\n📊 TEST 1: Full Transcription (no grammar)")
    results_unconstrained = []
    
    while True:
        data = wf.readframes(4000)
        if len(data) == 0:
            break
        if rec.AcceptWaveform(data):
            result = json.loads(rec.Result())
            if 'result' in result:
                results_unconstrained.extend(result['result'])
    
    final = json.loads(rec.FinalResult())
    if 'result' in final:
        results_unconstrained.extend(final['result'])
    
    print(f"   Detected {len(results_unconstrained)} words:")
    detected_text = " ".join([w['word'] for w in results_unconstrained])
    print(f"   \"{detected_text}\"")
    
    # Show first 10 word timings
    print(f"\n   Word timings (first 10):")
    for i, w in enumerate(results_unconstrained[:10]):
        print(f"      {i:2d}. \"{w['word']}\" @ {w['start']:.2f}s - {w['end']:.2f}s (conf: {w.get('conf', 1.0):.2f})")
    
    # TEST 2: With grammar constraints (forced alignment)
    print(f"\n📊 TEST 2: Forced Alignment (with grammar)")
    print(f"   Setting grammar to script words...")
    
    # Reset audio
    wf = wave.open(audio_path, "rb")
    
    # Create new recognizer with grammar
    rec_constrained = KaldiRecognizer(model, wf.getframerate())
    rec_constrained.SetWords(True)
    
    # Set grammar - Vosk will only recognize these words
    grammar = json.dumps(script_words)
    rec_constrained.SetGrammar(grammar)
    
    results_constrained = []
    while True:
        data = wf.readframes(4000)
        if len(data) == 0:
            break
        if rec_constrained.AcceptWaveform(data):
            result = json.loads(rec_constrained.Result())
            if 'result' in result:
                results_constrained.extend(result['result'])
    
    final = json.loads(rec_constrained.FinalResult())
    if 'result' in final:
        results_constrained.extend(final['result'])
    
    print(f"   Detected {len(results_constrained)} words:")
    constrained_text = " ".join([w['word'] for w in results_constrained])
    print(f"   \"{constrained_text}\"")
    
    print(f"\n   Word timings (first 10):")
    for i, w in enumerate(results_constrained[:10]):
        print(f"      {i:2d}. \"{w['word']}\" @ {w['start']:.2f}s - {w['end']:.2f}s (conf: {w.get('conf', 1.0):.2f})")
    
    # Compare to script
    print(f"\n🎯 ALIGNMENT ANALYSIS:")
    print(f"   Script words:     {len(script_words)}")
    print(f"   Detected (free):  {len(results_unconstrained)}")
    print(f"   Detected (forced): {len(results_constrained)}")
    
    # Calculate match rate
    matched = 0
    for i, script_word in enumerate(script_words):
        if i < len(results_constrained):
            detected_word = results_constrained[i]['word']
            if script_word == detected_word:
                matched += 1
    
    accuracy = (matched / len(script_words) * 100) if script_words else 0
    print(f"   Matched words:    {matched} ({accuracy:.1f}%)")
    
    # Show alignment
    print(f"\n   Alignment (first 10):")
    for i in range(min(10, len(script_words))):
        script_word = script_words[i]
        if i < len(results_constrained):
            detected = results_constrained[i]
            match = "✓" if script_word == detected['word'] else "✗"
            print(f"      {match} Script[{i:2d}]: \"{script_word}\" → \"{detected['word']}\" @ {detected['start']:.2f}s")
        else:
            print(f"      ✗ Script[{i:2d}]: \"{script_word}\" → (not detected)")
    
    # Verdict
    print(f"\n" + "=" * 60)
    print(f"📈 VERDICT")
    print(f"=" * 60)
    
    if accuracy >= 90:
        print(f"✅ EXCELLENT! {accuracy:.1f}% accuracy")
        print(f"   Vosk forced alignment works great on this audio!")
        print(f"   Recommendation: Use Vosk for production.")
    elif accuracy >= 75:
        print(f"⚠️  GOOD: {accuracy:.1f}% accuracy")
        print(f"   Vosk works but could be better.")
        print(f"   May need Whisper Tiny for higher accuracy.")
    elif accuracy >= 60:
        print(f"⚠️  MODERATE: {accuracy:.1f}% accuracy")
        print(f"   Vosk struggles with this audio.")
        print(f"   Recommendation: Use Whisper Tiny instead.")
    else:
        print(f"❌ POOR: {accuracy:.1f}% accuracy")
        print(f"   Vosk doesn't work well on this audio.")
        print(f"   Recommendation: Use Whisper Tiny or record clearer audio.")
    
    print(f"\n💡 Next Steps:")
    if accuracy >= 75:
        print(f"   1. Test with live microphone audio")
        print(f"   2. Integrate Vosk into Flutter")
        print(f"   3. Build streaming word tracker")
    else:
        print(f"   1. Test with Whisper Tiny (better accuracy)")
        print(f"   2. Or record test audio with less background noise")
    
    wf.close()

def main():
    import sys
    
    if len(sys.argv) < 3:
        print("Usage: python test_vosk_alignment.py <audio.wav> <script_text>")
        print("\nExample:")
        print('  python test_vosk_alignment.py audio/adalyn.wav "you are adalyn today you see a glowing window"')
        return
    
    audio_path = sys.argv[1]
    script_text = sys.argv[2]
    
    test_vosk_alignment(audio_path, script_text)

if __name__ == "__main__":
    # Default test
    audio_path = "audio/adalyn_reading_background.wav"
    script_text = "you are adalyn today you see a glowing window shimmering in your backyard you put on your rainbow boots and step outside"
    
    import os
    if os.path.exists(audio_path):
        test_vosk_alignment(audio_path, script_text)
    else:
        print(f"⚠️  Audio file not found: {audio_path}")
        print("\nUsage:")
        print('  python test_vosk_alignment.py <audio.wav> "script text"')

