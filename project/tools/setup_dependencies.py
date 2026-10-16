#!/usr/bin/env python3
"""Install the Godot Android build template for gradle exports.

The detector (addons/opencv_aruco), the camera plugin (addons/GodotAndroidCamera), the
OpenXR vendors addon and addons/naret_upstream are committed with this project, so the
submodule staging this script used to do is gone. Only the template remains: it is
Godot-version specific and git-ignored (android/build/).
"""
from __future__ import annotations

import argparse
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def stage_android_template(archive: Path) -> None:
    destination = ROOT / "android/build"
    (ROOT / "android").mkdir(parents=True, exist_ok=True)
    (ROOT / "android/.gdignore").touch()
    if not (destination / "build.gradle").exists():
        destination.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                path = Path(member.filename)
                if path.is_absolute() or ".." in path.parts:
                    raise SystemExit("Unsafe Android template archive path.")
            bundle.extractall(destination)
        (ROOT / "android/.build_version").write_text(archive.parent.name)
    # zipfile deliberately does not restore executable permission from Unix zip metadata.
    gradlew = destination / "gradlew"
    if gradlew.exists():
        gradlew.chmod(gradlew.stat().st_mode | 0o100)
    print("Android build template ready; Gradle wrapper is executable.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-template", type=Path, required=True, help="Install matching Godot android_source.zip, retaining an existing build tree")
    args = parser.parse_args()
    stage_android_template(args.android_template)


if __name__ == "__main__":
    main()
