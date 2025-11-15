#!/usr/bin/env python3
"""
Download a tiny subset of LibriSpeech for sanity check.
Downloads first 10 samples from dev-clean.
"""

import urllib.request
import tarfile
import os
from pathlib import Path
import shutil

def download_librispeech_tiny(output_dir='librispeech_tiny', n_samples=10):
    """
    Download first n_samples from LibriSpeech dev-clean.
    """
    print("=" * 60)
    print(f"📥 DOWNLOADING LIBRISPEECH DATASET ({n_samples} samples)")
    print("=" * 60)
    
    output_path = Path(output_dir)
    output_path.mkdir(exist_ok=True)
    
    # LibriSpeech dev-clean URL
    url = "http://www.openslr.org/resources/12/dev-clean.tar.gz"
    tar_path = output_path / "dev-clean.tar.gz"
    
    print(f"\n📦 Downloading LibriSpeech dev-clean...")
    print(f"   URL: {url}")
    print(f"   Size: ~337 MB (we'll only extract first {n_samples} samples)")
    print(f"   This may take a few minutes...")
    
    # Download
    if not tar_path.exists():
        urllib.request.urlretrieve(url, tar_path)
        print(f"   ✅ Downloaded to: {tar_path}")
    else:
        print(f"   ✅ Already downloaded: {tar_path}")
    
    # Extract first n_samples
    print(f"\n📂 Extracting first {n_samples} audio files...")
    
    audio_dir = output_path / "audio"
    audio_dir.mkdir(exist_ok=True)
    
    count = 0
    with tarfile.open(tar_path, 'r:gz') as tar:
        for member in tar.getmembers():
            if member.name.endswith('.flac'):
                # Extract audio file
                tar.extract(member, output_path)
                
                # Move to flat structure
                src = output_path / member.name
                dst = audio_dir / f"sample_{count:04d}.flac"
                shutil.move(str(src), str(dst))
                
                # Also extract transcript
                txt_member_name = member.name.replace('.flac', '.txt')
                for txt_member in tar.getmembers():
                    if txt_member.name == txt_member_name:
                        tar.extract(txt_member, output_path)
                        txt_src = output_path / txt_member.name
                        txt_dst = audio_dir / f"sample_{count:04d}.txt"
                        shutil.move(str(txt_src), str(txt_dst))
                        break
                
                count += 1
                print(f"   Extracted: {dst.name}")
                
                if count >= n_samples:
                    break
    
    # Clean up extracted directories
    for item in (output_path / "LibriSpeech").iterdir():
        if item.is_dir():
            shutil.rmtree(item)
    (output_path / "LibriSpeech").rmdir()
    
    print(f"\n✅ Downloaded {count} samples to: {audio_dir}")
    print(f"   Total size: ~{count * 0.5:.1f} MB")
    
    return audio_dir

if __name__ == "__main__":
    import sys
    n_samples = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    output_dir = sys.argv[2] if len(sys.argv) > 2 else 'librispeech_tiny'
    audio_dir = download_librispeech_tiny(output_dir=output_dir, n_samples=n_samples)
    
    # List samples
    print("\n📋 Sample list:")
    for i, audio_file in enumerate(sorted(audio_dir.glob("*.flac"))):
        txt_file = audio_file.with_suffix('.txt')
        if txt_file.exists():
            text = txt_file.read_text().strip()
            # Take first 60 chars
            text_preview = text[:60] + "..." if len(text) > 60 else text
            print(f"   {i+1}. {audio_file.name}: \"{text_preview}\"")
    
    print("\n" + "=" * 60)
    print("✅ DOWNLOAD COMPLETE!")
    print("=" * 60)

