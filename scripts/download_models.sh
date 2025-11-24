#!/bin/bash

# Define the target directory
TARGET_DIR="assets/sherpa-onnx-models/sherpa-onnx-streaming-zipformer-en-2023-06-26"

# Create the directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Base URL for the model files
BASE_URL="https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26/resolve/main"

# List of files to download
FILES=(
    "encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx"
    "decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx"
    "joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx"
    "tokens.txt"
    "bpe.model"
)

# Download each file
for file in "${FILES[@]}"; do
    if [ -f "$TARGET_DIR/$file" ]; then
        echo "$file already exists in $TARGET_DIR, skipping..."
    else
        echo "Downloading $file..."
        curl -L "$BASE_URL/$file" -o "$TARGET_DIR/$file"
    fi
done

echo "All models downloaded successfully!"

