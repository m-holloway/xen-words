#!/usr/bin/env python3
"""
Generate ground truth word timings for a batch of audio files using Whisper.
"""

import whisper
import json
from pathlib import Path
import librosa
import soundfile as sf
from tqdm import tqdm

def convert_flac_to_wav(flac_path, wav_path):
    """Convert FLAC to WAV (16kHz mono)."""
    audio, sr = librosa.load(flac_path, sr=16000, mono=True)
    sf.write(wav_path, audio, sr)
    return wav_path

def generate_ground_truth_for_file(audio_path, model, output_dir):
    """
    Generate ground truth word timings for a single audio file.
    """
    audio_path = Path(audio_path)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Convert FLAC to WAV if needed
    if audio_path.suffix == '.flac':
        wav_path = output_dir / (audio_path.stem + '.wav')
        if not wav_path.exists():
            convert_flac_to_wav(audio_path, wav_path)
    else:
        wav_path = audio_path
    
    # Transcribe with word-level timestamps
    result = model.transcribe(
        str(wav_path),
        word_timestamps=True,
        language='en'
    )
    
    # Extract word timings
    word_timings = []
    for segment in result['segments']:
        if 'words' in segment:
            for word_info in segment['words']:
                word_timings.append({
                    'word': word_info['word'].strip(),
                    'start': word_info['start'],
                    'end': word_info['end']
                })
    
    # Save ground truth
    gt_path = output_dir / (audio_path.stem + '_gt.json')
    ground_truth = {
        'audio_file': audio_path.name,
        'wav_file': wav_path.name,
        'transcript': result['text'].strip(),
        'word_timings': word_timings,
        'duration': result['segments'][-1]['end'] if result['segments'] else 0.0
    }
    
    with open(gt_path, 'w') as f:
        json.dump(ground_truth, f, indent=2)
    
    return ground_truth, wav_path

def generate_ground_truth_batch(audio_dir, output_dir='ground_truth_tiny', model_name='base'):
    """
    Generate ground truth for all audio files in a directory.
    """
    print("=" * 60)
    print("🎙️ GENERATING GROUND TRUTH WITH WHISPER")
    print("=" * 60)
    
    audio_dir = Path(audio_dir)
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Load Whisper model
    print(f"\n📥 Loading Whisper '{model_name}' model...")
    model = whisper.load_model(model_name)
    print(f"   ✅ Model loaded")
    
    # Find all audio files
    audio_files = sorted(audio_dir.glob("*.flac")) + sorted(audio_dir.glob("*.wav"))
    print(f"\n📂 Found {len(audio_files)} audio files")
    
    # Process each file
    print(f"\n🔄 Processing...")
    results = []
    for audio_file in tqdm(audio_files, desc="Transcribing"):
        try:
            gt, wav_path = generate_ground_truth_for_file(audio_file, model, output_dir)
            results.append({
                'audio': audio_file,
                'wav': wav_path,
                'gt': gt,
                'success': True
            })
        except Exception as e:
            print(f"\n   ❌ Error processing {audio_file.name}: {e}")
            results.append({
                'audio': audio_file,
                'success': False,
                'error': str(e)
            })
    
    # Summary
    successful = sum(1 for r in results if r['success'])
    total_words = sum(len(r['gt']['word_timings']) for r in results if r['success'])
    total_duration = sum(r['gt']['duration'] for r in results if r['success'])
    
    print(f"\n" + "=" * 60)
    print("✅ GROUND TRUTH GENERATION COMPLETE!")
    print("=" * 60)
    print(f"   Successful: {successful}/{len(audio_files)}")
    print(f"   Total words: {total_words}")
    print(f"   Total duration: {total_duration:.1f}s ({total_duration/60:.1f} min)")
    print(f"   Output dir: {output_dir}")
    
    # Save summary
    summary_path = output_dir / "summary.json"
    summary = {
        'model': model_name,
        'total_files': len(audio_files),
        'successful': successful,
        'total_words': total_words,
        'total_duration': total_duration,
        'files': [
            {
                'audio': str(r['audio'].name) if r['success'] else str(r['audio']),
                'words': len(r['gt']['word_timings']) if r['success'] else 0,
                'duration': r['gt']['duration'] if r['success'] else 0,
            }
            for r in results if r['success']
        ]
    }
    
    with open(summary_path, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"\n📊 Summary saved to: {summary_path}")
    
    return results

if __name__ == "__main__":
    import sys
    
    audio_dir = sys.argv[1] if len(sys.argv) > 1 else "librispeech_tiny/audio"
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "ground_truth_tiny"
    
    results = generate_ground_truth_batch(audio_dir, output_dir)
    
    # Show first 3 examples
    print("\n📋 Sample Ground Truth (first 3):")
    for i, r in enumerate([r for r in results if r['success']][:3]):
        gt = r['gt']
        print(f"\n{i+1}. {gt['audio_file']}")
        print(f"   Duration: {gt['duration']:.1f}s")
        print(f"   Words: {len(gt['word_timings'])}")
        print(f"   Transcript: \"{gt['transcript'][:80]}...\"")
        print(f"   First 5 words:")
        for j, word in enumerate(gt['word_timings'][:5]):
            print(f"      {j+1}. \"{word['word']}\" @ {word['start']:.2f}s")

