#!/usr/bin/env python3
"""Verify a debug APK's architecture, contents, signing and credential exclusion."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import zipfile
from api_common import ROOT, read_key


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", nargs="?", type=Path, default=ROOT / "build/naret-quest.apk")
    args = parser.parse_args()
    apk = args.apk.resolve()
    checks = {}
    with zipfile.ZipFile(apk) as bundle:
        names = bundle.namelist()
        libraries = [name for name in names if name.startswith("lib/")]
        checks["arm64_only"] = bool(libraries) and all(name.startswith("lib/arm64-v8a/") for name in libraries)
        for key, library in {
            "godot": "libgodot_android.so", "openxr": "libgodotopenxrvendors.so",
            "aruco": "libopencv_aruco.android.template_debug.arm64.so", "loader": "libopenxr_loader.so",
        }.items():
            checks[key] = f"lib/arm64-v8a/{library}" in names
        checks["source_trees_excluded"] = not any(name.startswith(("assets/android/", "assets/third_party/", "assets/tools/", "assets/tests/")) for name in names)
        checks["env_files_excluded"] = not any(Path(name).name.startswith(".env") or Path(name).name == "config.json" for name in names)
        checks["offline_audio"] = "assets/assets/audio/manifest.json" in names
        secret = read_key().encode()
        checks["local_credential_absent"] = not secret or not any(secret in bundle.read(name) for name in names if not name.endswith("/"))
    sdk = Path(os.environ.get("ANDROID_HOME", str(Path.home() / "Library/Android/sdk")))
    candidates = sorted((sdk / "build-tools").glob("*/aapt.exe" if os.name == "nt" else "*/aapt"), key=lambda p: tuple(int(n) for n in p.parent.name.split(".") if n.isdigit()))
    if not candidates:
        raise SystemExit("Android build-tools required for package/signature audit")
    aapt = candidates[-1]
    badging = subprocess.run([str(aapt), "dump", "badging", str(apk)], check=True, capture_output=True, text=True, timeout=30).stdout
    permissions = subprocess.run([str(aapt), "dump", "permissions", str(apk)], check=True, capture_output=True, text=True, timeout=30).stdout
    checks["package"] = "name='de.uni_greifswald.naret.cprwitness'" in badging
    for permission in ["android.permission.INTERNET", "android.permission.RECORD_AUDIO", "android.permission.CAMERA", "horizonos.permission.HEADSET_CAMERA", "com.oculus.permission.USE_SCENE"]:
        checks[permission] = permission in permissions
    signed = subprocess.run([str(aapt.parent / ("apksigner.bat" if os.name == "nt" else "apksigner")), "verify", str(apk)], capture_output=True, text=True, timeout=30)
    checks["signature_valid"] = signed.returncode == 0
    report = {
        "apk": apk.name, "bytes": apk.stat().st_size,
        "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(), "checks": checks,
        "on_headset_tested": False,
    }
    target = apk.with_suffix(".manifest.json")
    target.write_text(json.dumps(report, indent=2) + "\n")
    for key, passed in checks.items(): print(f"{'PASS' if passed else 'FAIL'} {key}")
    print(f"Report: {target.name}")
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
