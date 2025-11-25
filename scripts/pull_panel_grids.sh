#!/usr/bin/env bash
set -euo pipefail

# Pull all generated panel grid PNGs from the app's private storage on a
# connected Android device/emulator into a local directory (for debugging).
# Usage:
#   ./scripts/pull_panel_grids.sh [local_output_dir]
#
# Notes:
# - Requires a debuggable build of the app (so that `adb shell run-as` works).
# - Respects $ANDROID_SERIAL if you have multiple devices attached.

PKG="${PKG:-com.xensemble.xen_words}"
REMOTE_DIR="/data/user/0/$PKG/code_cache/xen_words_art"
OUT_DIR="${1:-./_local/panel_grids}"

ADB_BIN="${ADB:-adb}"
DEVICE_OPTS=()
if [[ -n "${ANDROID_SERIAL-}" ]]; then
  DEVICE_OPTS=(-s "$ANDROID_SERIAL")
fi

echo "=== Xen Words panel grid pull ==="
echo " Package:     $PKG"
echo " Remote dir:  $REMOTE_DIR"
echo " Local out:   $OUT_DIR"
mkdir -p "$OUT_DIR"

echo
echo "[1/3] Checking device connection…"
if ! $ADB_BIN "${DEVICE_OPTS[@]:-}" get-state >/dev/null 2>&1; then
  echo "ERROR: No adb device detected. Is your phone/emulator connected and authorized?"
  exit 1
fi

echo "[2/3] Verifying 'adb shell run-as $PKG' works…"
if ! $ADB_BIN "${DEVICE_OPTS[@]:-}" shell "run-as $PKG ls >/dev/null 2>&1"; then
  echo "ERROR: 'adb shell run-as $PKG' failed."
  echo "This usually means the app is not a debuggable build or the package name is wrong."
  exit 1
fi

echo "[3/3] Listing PNG files in $REMOTE_DIR…"
REMOTE_LIST=$($ADB_BIN "${DEVICE_OPTS[@]:-}" shell "run-as $PKG sh -c 'ls \"$REMOTE_DIR\"/*.png 2>/dev/null'" || true)

if [[ -z "$REMOTE_LIST" ]]; then
  echo "No PNG files found in $REMOTE_DIR."
  exit 0
fi

COUNT=0
while IFS= read -r REMOTE; do
  REMOTE="${REMOTE//$'\r'/}"  # strip CR if present
  [[ -z "$REMOTE" ]] && continue
  BASENAME=$(basename "$REMOTE")
  LOCAL_PATH="$OUT_DIR/$BASENAME"
  echo "→ Pulling $REMOTE → $LOCAL_PATH"
  # Use run-as + cat to read from the app's private storage.
  $ADB_BIN "${DEVICE_OPTS[@]:-}" exec-out run-as "$PKG" cat "$REMOTE" >"$LOCAL_PATH"
  COUNT=$((COUNT + 1))
done <<< "$REMOTE_LIST"

echo
echo "Pulled $COUNT file(s) into $OUT_DIR:"
ls -1 "$OUT_DIR" || true