#!/usr/bin/env python3
"""Read-only Quest export preflight; nonzero exit means the APK is not ready to build."""
from __future__ import annotations
import argparse
from pathlib import Path
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", action="store_true", help="Also require an authorized ADB device")
    args = parser.parse_args()
    failures = []
    variant = "debug"  # make apk exports debug
    checks = {
        "ArUco ARM64": ROOT / f"addons/opencv_aruco/bin/android/libopencv_aruco.android.template_{variant}.arm64.so",
        "OpenXR Vendors ARM64": ROOT / f"addons/godotopenxrvendors/.bin/android/template_{variant}/arm64/libgodotopenxrvendors.so",
        "Meta Android loader": ROOT / f"addons/godotopenxrvendors/.bin/android/{variant}/godotopenxr-meta-{variant}.aar",
        "Hand tracking sources": ROOT / "addons/naret_upstream/avatar/cpr_hand_zone.gd",
        "Android build template": ROOT / "android/build/build.gradle",
        "Quest export preset": ROOT / "export_presets.cfg",
    }
    for label, path in checks.items():
        good = path.is_file() and path.stat().st_size > 0
        if good and path.suffix == ".so":
            with path.open("rb") as stream:
                header = stream.read(20)
            good = header[:4] == b"\x7fELF" and header[4] == 2 and header[18:20] == b"\xb7\x00"
        print(f"{'OK' if good else 'MISSING'} {label}")
        if not good:
            failures.append(label)
    sdk = Path(os.environ.get("ANDROID_HOME", str(Path.home() / "Library/Android/sdk")))
    print(f"{'OK' if sdk.exists() else 'MISSING'} Android SDK")
    if not sdk.exists():
        failures.append("Android SDK")
    if args.device:
        adb = shutil.which("adb") or str(sdk / "platform-tools/adb")
        try:
            result = subprocess.run([adb, "devices"], capture_output=True, text=True, timeout=10, check=True)
            authorized = sum(line.endswith("\tdevice") for line in result.stdout.splitlines())
            print(f"{'OK' if authorized else 'MISSING'} authorized Quest/device ({authorized})")
            if not authorized:
                failures.append("ADB device")
        except (OSError, subprocess.SubprocessError):
            print("MISSING ADB device")
            failures.append("ADB device")
    if failures:
        print("Preflight incomplete. See docs/TRACKING.md; do not treat a preview as headset validation.")
        return 1
    print(f"Ready for {variant} export; on-headset tracking and performance still require measurement.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
