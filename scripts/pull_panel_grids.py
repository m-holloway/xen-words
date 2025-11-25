#!/usr/bin/env python3
"""
Pull and archive panel grid PNGs from the Xen Words Android app.

This script:
  1. Lists all PNG files in the app's internal panel art directory:
       /data/user/0/com.xensemble.xen_words/code_cache/xen_words_art
  2. Uses `adb shell "run-as ... cat ..."` to stream each file to the host
  3. Saves them under a local directory (default: ./_local/panel_grids)

Notes:
  - Requires a debuggable build of com.xensemble.xen_words
    so that `adb shell "run-as com.xensemble.xen_words …"` works.
  - Respects the ANDROID_SERIAL environment variable if multiple devices exist.
"""

import os
import subprocess
from pathlib import Path
from typing import List, Tuple

PACKAGE_NAME = "com.xensemble.xen_words"
APP_DIR = "/data/user/0/com.xensemble.xen_words/code_cache/xen_words_art"
DEFAULT_LOCAL_DIR = "_local/panel_grids"


def run_adb_command(cmd: str) -> str:
  """Run an adb command and return stdout (stripped), or '' on error."""
  try:
    result = subprocess.run(
      cmd,
      shell=True,
      capture_output=True,
      text=True,
      check=True,
    )
    return result.stdout.strip()
  except subprocess.CalledProcessError as e:
    print(f"Error running command: {cmd}")
    if e.stderr:
      print(f"Error: {e.stderr.strip()}")
    return ""


def check_device_connected() -> bool:
  """Return True if at least one adb device is connected."""
  output = run_adb_command("adb devices")
  if not output:
    return False
  # Skip the header line; look for any line that ends with '\tdevice'
  for line in output.splitlines()[1:]:
    if line.strip().endswith("\tdevice"):
      return True
  return False


def list_panel_grids_on_device() -> List[str]:
  """List PNG files in the app's panel grid directory using run-as."""
  print(f"Listing panel grids on device in {APP_DIR} …")
  cmd = f'adb shell "run-as {PACKAGE_NAME} ls {APP_DIR} 2>/dev/null"'
  output = run_adb_command(cmd)
  if not output:
    print("No files found on device (or run-as failed).")
    return []

  files = [
    f.strip()
    for f in output.splitlines()
    if f.strip().lower().endswith(".png")
  ]
  print(f"Found {len(files)} PNG files on device.")
  return files


def pull_panel_grids(files: List[str], local_dir: Path) -> Tuple[int, int]:
  """
  Pull the given PNG files from the device into local_dir.

  Returns (downloaded_count, failed_count).
  """
  local_dir.mkdir(parents=True, exist_ok=True)

  downloaded = 0
  failed = 0

  for filename in files:
    local_path = local_dir / filename
    remote_path = f"{APP_DIR}/{filename}"

    print(f"Pulling {remote_path} → {local_path} …")
    # Use run-as to cat the file contents and redirect locally.
    cmd = f'adb shell "run-as {PACKAGE_NAME} cat {remote_path}"'
    try:
      with open(local_path, "wb") as f:
        proc = subprocess.run(
          cmd,
          shell=True,
          stdout=f,
          stderr=subprocess.PIPE,
        )
      if proc.returncode == 0 and local_path.exists() and local_path.stat().st_size > 0:
        size = local_path.stat().st_size
        print(f"  ✓ Downloaded {filename} ({size:,} bytes)")
        downloaded += 1
      else:
        print(f"  ✗ Failed to download {filename}")
        if proc.stderr:
          print(f"    Error: {proc.stderr.decode('utf-8', 'ignore').strip()}")
        if local_path.exists() and local_path.stat().st_size == 0:
          local_path.unlink()
        failed += 1
    except Exception as e:
      print(f"  ✗ Exception while downloading {filename}: {e}")
      if local_path.exists():
        try:
          local_path.unlink()
        except Exception:
          pass
      failed += 1

  return downloaded, failed


def main() -> None:
  print("=" * 70)
  print("XEN WORDS PANEL GRID SYNC - Pull panel grids from Android device")
  print("=" * 70)
  print(f"Package:   {PACKAGE_NAME}")
  print(f"App dir:   {APP_DIR}")

  # Determine local output directory (allow overriding via env or arg)
  import sys

  if len(sys.argv) > 1:
    local_dir = Path(sys.argv[1])
  else:
    local_dir = Path(DEFAULT_LOCAL_DIR)

  print(f"Local dir: {local_dir}")

  # Check adb connection
  print("\nChecking device connection…")
  if not check_device_connected():
    print("❌ No device connected! Run `adb devices` and ensure at least one device is in 'device' state.")
    return
  print("✓ Device connected.")

  # Verify run-as works
  print("\nVerifying run-as access to app data…")
  test_cmd = f'adb shell "run-as {PACKAGE_NAME} ls {APP_DIR} >/dev/null 2>&1"'
  test_out = subprocess.run(test_cmd, shell=True)
  if test_out.returncode != 0:
    print("❌ `adb shell run-as` failed.")
    print("   Make sure you are running a debuggable build of the app and the package name is correct.")
    return
  print("✓ run-as is available.")

  # List files on device
  files = list_panel_grids_on_device()
  if not files:
    print("\n✓ No panel grid PNG files to pull.")
    return

  # Pull files
  print("\nPulling panel grids…")
  downloaded, failed = pull_panel_grids(files, local_dir)

  # Summary
  print("\n" + "=" * 70)
  print("PANEL GRID SYNC SUMMARY")
  print("=" * 70)
  print(f"Total found on device:   {len(files)}")
  print(f"Successfully downloaded: {downloaded}")
  print(f"Failed:                  {failed}")
  print(f"Local directory:         {local_dir.resolve()}")
  print("=" * 70)


if __name__ == "__main__":
  main()


