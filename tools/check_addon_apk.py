"""Ensure the test APK contains the imported Android detector, not its backup."""
from pathlib import Path
import hashlib
import zipfile

project = Path(__file__).resolve().parents[1]
apk = project / "build/naret-addon-nano-colour.apk"
library = project / "addons/opencv_aruco/bin/android/libopencv_aruco.android.template_debug.arm64.so"
with zipfile.ZipFile(apk) as archive:
    candidates = [name for name in archive.namelist()
                  if name.startswith("lib/arm64-v8a/") and "opencv_aruco" in name]
    assert len(candidates) == 1, candidates
    packaged = archive.read(candidates[0])
    assert packaged == library.read_bytes(), "APK detector differs from imported library"
    print("APK detector matches addon-port:", hashlib.sha256(packaged).hexdigest())
