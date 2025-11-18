### Voice-Recognition Emulation (Python)
Use the scripts under `genai/alignment_testing` to iterate on Sherpa/VAD logic outside of Flutter:

1. Create a Python 3.10 virtualenv (3.14 is unsupported by `numba`/`torch`):
   ```bash
   cd genai
   python3.10 -m venv .venv_alignment
   source .venv_alignment/bin/activate
   pip install -r alignment_testing/requirements.txt
   pip install sherpa-onnx
   ```
2. Run the real-time parity harness against the Adalyn recording:
   ```bash
   cd alignment_testing
   python replay_audio_with_v13.py \
     --audio ../../test_audio/clean_recording.wav \
     --ground-truth clean_recording_gt.json \
     --script scripts/adalyn_story.txt
   ```
   This replays the exact Sherpa/STT + VAD stack and prints every anchor/prediction so you can reproduce “jump ahead” issues locally.
3. For lower-level Sherpa testing see `README_REALTIME_TEST.md` and `test_realtime_sherpa_streaming.py`.

