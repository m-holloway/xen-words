#!/bin/bash
# Setup script for real-time Sherpa-ONNX testing

set -e

echo "=========================================="
echo "🔧 Setting up Sherpa-ONNX Test Environment"
echo "=========================================="
echo ""

# Check Python packages
echo "📦 Checking Python packages..."
if ! python3 -c "import sherpa_onnx" 2>/dev/null; then
    echo "⚠️  sherpa-onnx not installed"
    echo "Installing sherpa-onnx..."
    pip install sherpa-onnx
else
    echo "✅ sherpa-onnx installed"
fi

if ! python3 -c "import wave" 2>/dev/null; then
    echo "⚠️  wave module not available"
fi

# Download Sherpa model (same as Flutter app uses)
MODEL_NAME="sherpa-onnx-streaming-zipformer-en-2023-06-26"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL_NAME}.tar.bz2"

echo ""
echo "📥 Checking Sherpa model..."

if [ -d "$MODEL_NAME" ]; then
    echo "✅ Model already downloaded: $MODEL_NAME"
else
    echo "⬇️  Downloading model..."
    echo "   URL: $MODEL_URL"
    echo "   Size: ~100MB"
    echo ""
    
    wget -q --show-progress "$MODEL_URL"
    
    echo "📦 Extracting model..."
    tar -xf "${MODEL_NAME}.tar.bz2"
    rm "${MODEL_NAME}.tar.bz2"
    
    echo "✅ Model downloaded and extracted"
fi

# Check audio files
echo ""
echo "🎵 Checking audio files..."

if [ -f "../../test_audio/clean_recording.wav" ]; then
    echo "✅ Clean recording found"
else
    if [ -f "../../test_audio/Clean recording.m4a" ]; then
        echo "🔄 Converting Clean recording.m4a to WAV..."
        ffmpeg -i "../../test_audio/Clean recording.m4a" \
               -ar 16000 -ac 1 -y \
               "../../test_audio/clean_recording.wav" 2>/dev/null
        echo "✅ Converted to WAV"
    else
        echo "⚠️  Clean recording not found"
    fi
fi

if [ -f "../../test_audio/reading_with_noise.wav" ]; then
    echo "✅ Noisy recording found"
else
    if [ -f "../../test_audio/reading-with-background-noise.m4a" ]; then
        echo "🔄 Converting reading-with-background-noise.m4a to WAV..."
        ffmpeg -i "../../test_audio/reading-with-background-noise.m4a" \
               -ar 16000 -ac 1 -y \
               "../../test_audio/reading_with_noise.wav" 2>/dev/null
        echo "✅ Converted to WAV"
    else
        echo "⚠️  Noisy recording not found"
    fi
fi

echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "Run the test:"
echo "  python test_realtime_sherpa_streaming.py"
echo ""

