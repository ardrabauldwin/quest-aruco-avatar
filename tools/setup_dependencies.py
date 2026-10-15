#!/usr/bin/env python3
"""Stage runtime files from pinned submodules; never edit the upstream checkout.

Run after `git submodule update --init --recursive`. Optional vendor download is
version and SHA256 pinned. Native ArUco builds remain upstream's responsibility.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VENDOR_VERSION = "5.1.0-stable"
VENDOR_SHA256 = "6a838dbdf4115549e4511ebee0da9a5dcc8f9f6258d4cc2f2ee57a907a3e2911"
VENDOR_URL = f"https://github.com/GodotVR/godot_openxr_vendors/releases/download/{VENDOR_VERSION}/godotopenxrvendorsaddon.zip"
AVATAR_FILES = (
    "simple_pose_stabilizer.gd", "cpr_hand_zone.gd", "cpr_hand_zone.tscn",
    "cpr_motion_session.gd", "cpr_metronome.gd", "cpr_target_guide.gdshader",
)


def copy_file(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def stage_avatar(include_model: bool) -> None:
    source = ROOT / "third_party/quest-aruco-avatar/project"
    target = ROOT / "addons/naret_upstream/avatar"
    target.mkdir(parents=True, exist_ok=True)
    for name in AVATAR_FILES:
        text = (source / name).read_text(encoding="utf-8")
        if name == "cpr_motion_session.gd":
            # Preserve the upstream stroke detector. Only make its standalone-demo
            # practice policy configurable; NaReT's scenario owns 30:2 and pauses.
            changes = {
                "var target_bpm := 110.0": "var automatic_breathing_pause := true\nvar metronome_enabled := true\nvar target_bpm := 110.0",
                "\t\tbeat_requested.emit()": "\t\tif metronome_enabled:\n\t\t\tbeat_requested.emit()",
                "if count >= 30:": "if count >= 30 and automatic_breathing_pause:",
            }
            for before, after in changes.items():
                if text.count(before) != 1:
                    raise SystemExit("Pinned CPR source changed; review policy patch before staging.")
                text = text.replace(before, after)
        for dependency in AVATAR_FILES:
            text = text.replace(f"res://{dependency}", f"res://addons/naret_upstream/avatar/{dependency}")
        (target / name).write_text(text, encoding="utf-8")
    copy_file(source.parent / "LICENSE.md", target / "LICENSE.md")
    copy_file(source / "assets/img_of_marker0_dict4x4_50.png", ROOT / "assets/textures/markers/aruco_4x4_50_0.png")
    if include_model:
        copy_file(source / "assets/avatar/mannequin.glb", ROOT / "assets/models/mannequin_upstream.glb")
        copy_file(source / "assets/avatar/mannequin_texgen_0.png", ROOT / "assets/models/mannequin_texgen_0.png")
    print("Staged upstream filtering and CPR hand tracking (Unlicense).")


def stage_aruco(force: bool) -> None:
    source = ROOT / "third_party/godot-opencv-aruco/project/addons/opencv_aruco"
    native = list((source / "bin").rglob("*.so")) + list((source / "bin").rglob("*.dll")) + list((source / "bin").rglob("*.framework"))
    host_dir = {"Darwin": "macos", "Windows": "windows", "Linux": "linux"}.get(platform.system(), "")
    host_native = [p for p in native if host_dir in p.relative_to(source / "bin").parts]
    if not host_native and not force:
        print("ArUco source pinned; host native library not built. Desktop preview remains available.")
        print("Build the upstream extension, then rerun with --aruco. See docs/TRACKING.md.")
        return
    target = ROOT / "addons/opencv_aruco"
    shutil.copytree(source, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns("*.uid", ".gitkeep"))
    # Only advertise binaries actually built. A missing host binary must not poison
    # the Godot editor, while Android entries are still exported when present.
    extension = target / "bin/opencv_aruco.gdextension"
    lines = []
    for line in extension.read_text().splitlines():
        if ' = "./' in line:
            relative = line.split('"')[1]
            if not (extension.parent / relative).exists():
                continue
        lines.append(line)
    extension.write_text("\n".join(lines) + "\n")
    project = ROOT / "project.godot"
    if project.exists():
        settings = project.read_text()
        plugin = 'res://addons/opencv_aruco/plugin.cfg'
        if "[editor_plugins]" not in settings:
            project.write_text(settings + '\n[editor_plugins]\nenabled=PackedStringArray("' + plugin + '")\n')
    print(f"Staged ArUco addon with {len(native)} native binaries/frameworks.")


def stage_vendors(download: bool, archive: Path | None) -> None:
    if download:
        archive = ROOT / ".cache/godotopenxrvendorsaddon-5.1.0.zip"
        archive.parent.mkdir(parents=True, exist_ok=True)
        if not archive.exists():
            subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", VENDOR_URL, "--output", str(archive)], check=True)
    if archive:
        if hashlib.sha256(archive.read_bytes()).hexdigest() != VENDOR_SHA256:
            raise SystemExit("Vendor archive SHA256 mismatch; nothing extracted.")
        with tempfile.TemporaryDirectory() as staging, zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                path = Path(member.filename)
                if path.is_absolute() or ".." in path.parts:
                    raise SystemExit("Unsafe archive path.")
            bundle.extractall(staging)
            candidates = list(Path(staging).rglob("godotopenxrvendors"))
            addon = next((p for p in candidates if (p / "plugin.gdextension").exists()), None)
            if addon is None:
                raise SystemExit("Vendor addon missing from archive.")
            shutil.copytree(addon, ROOT / "addons/godotopenxrvendors", dirs_exist_ok=True)
        print(f"Staged SHA256-verified OpenXR Vendors {VENDOR_VERSION}.")
    source = ROOT / "third_party/godot_openxr_vendors/demo"
    for name in ("hand_controller.gd", "hand_mesh.gd"):
        copy_file(source / name, ROOT / "addons/naret_upstream/vendors" / name)
    copy_file(source.parent / "LICENSE", ROOT / "addons/naret_upstream/vendors/LICENSE")
    ignore = ROOT / "addons/naret_upstream/vendors/.gdignore"
    if (ROOT / "addons/godotopenxrvendors/plugin.gdextension").exists():
        ignore.unlink(missing_ok=True)
    else:
        ignore.touch()


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
    parser.add_argument("--aruco", action="store_true", help="Stage ArUco addon, including available native libraries")
    parser.add_argument("--download-vendors", action="store_true", help="Download pinned official vendor release")
    parser.add_argument("--vendor-zip", type=Path, help="Use a local copy of the pinned vendor zip")
    parser.add_argument("--upstream-model", action="store_true", help="Also copy the optional upstream mannequin; see provenance note")
    parser.add_argument("--android-template", type=Path, help="Install matching Godot android_source.zip, retaining an existing build tree")
    args = parser.parse_args()
    stage_avatar(args.upstream_model)
    stage_aruco(args.aruco)
    stage_vendors(args.download_vendors, args.vendor_zip)
    if args.android_template:
        stage_android_template(args.android_template)


if __name__ == "__main__":
    main()
