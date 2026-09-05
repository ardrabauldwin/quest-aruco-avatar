"""Build the headset's calibration file from a recorded walk instead of from one button press.

Run:
    python make_calibration.py LABELLED_WALK.csv OLD.cfg NEW.cfg

Pressing B calibrates from a single frame at a single viewpoint, so whatever pose error that one
viewpoint had is baked into the offset permanently. Measured on 3 August, that produced an ID2
offset of 174.5 mm against a 158 mm tape - 16.5 mm wrong, and wrong in a way no filter can undo.

This learns the same offsets from a whole walk instead, keeping only the CLOSEST quarter of the
samples. Distance is what drives the error: it grows about 11 mm per metre of range, correlation
+0.95 across the six viewpoints. Leave-one-viewpoint-out cross validation put the closest quarter
at 20.5 mm against 35.3 mm for using every sample equally - so selecting beats averaging, and both
beat one frame.

This is one user-facing command. Internally it gives the learned quaternions to Godot, which writes
Transform3D values in its own basis convention and preserves the body's existing rest orientation.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

from aruco_pose import (
    MARKERS,
    marker_seen,
    read_pose,
    relative_pose,
    stable_reference,
)
from simple_aruco_analysis import RULER_MM, load_csv

# Marker name in the CSV -> node name in the scene, which is what the .cfg is keyed on.
NODE = {"common": "aruco_patch0", "chest": "aruco_patch1", "navel": "aruco_patch2"}
CLOSEST_FRACTION = 0.25


def learn(rows, marker):
    """The marker-to-ID0 offset, from the closest quarter of the samples."""
    usable = [r for r in rows if marker_seen(r, "common") and marker_seen(r, marker)]
    if len(usable) < 20:
        raise SystemExit(f"Only {len(usable)} rows show both ID0 and {marker}.")
    samples = [relative_pose(read_pose(r, marker), read_pose(r, "common")) for r in usable]
    ranges = np.array([np.linalg.norm(read_pose(r, marker)[0]) for r in usable])
    keep = np.argsort(ranges)[: max(20, int(len(ranges) * CLOSEST_FRACTION))]
    return stable_reference([samples[i] for i in keep]), ranges[keep].max() * 1000


def main():
    if len(sys.argv) != 4:
        raise SystemExit(
            "Run: python make_calibration.py LABELLED_WALK.csv OLD.cfg NEW.cfg"
        )

    rows = [r for r in load_csv(Path(sys.argv[1]))
            if all(marker_seen(r, m) for m in MARKERS)]

    out = {}
    print(f"\n  {'marker':<8}{'offset':>10}{'tape':>8}{'error':>9}   learned within")
    for marker in MARKERS:
        offset, furthest = learn(rows, marker)
        out[NODE[marker]] = {
            "quaternion": [float(v) for v in offset[1]],
            "origin": [float(v) for v in offset[0]],
        }
        if marker == "common":
            continue
        length = float(np.linalg.norm(offset[0])) * 1000
        tape = RULER_MM[("common", marker)]
        print(f"  {marker:<8}{length:8.1f} mm{tape:8.0f}{length - tape:+9.1f}"
              f"   {furthest:.0f} mm of the markers")

    # The body's orientation is NOT rigid the way the offsets are - it changes if the mannequin is
    # moved. So it is deliberately left out here and the value already on the headset is kept.
    print(f"\n  Learned from the closest {int(CLOSEST_FRACTION * 100)}% of {len(rows)} rows.")
    print("  The body's rest orientation is not written: it belongs to wherever the mannequin is")
    print("  standing now, not to when this walk was recorded.")

    godot = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
    if godot is None:
        raise SystemExit("Godot was not found on PATH; it is required to write Transform3D safely.")

    converter = Path(__file__).resolve().parent / "project" / "write_calibration.gd"
    old_cfg = Path(sys.argv[2]).resolve()
    new_cfg = Path(sys.argv[3]).resolve()
    with tempfile.TemporaryDirectory(prefix="aruco_calibration_") as temporary:
        offsets_json = Path(temporary) / "offsets.json"
        offsets_json.write_text(json.dumps(out), encoding="utf-8")
        result = subprocess.run([
            godot, "--headless", "--script", str(converter), "--",
            str(offsets_json), str(old_cfg), str(new_cfg),
        ])
    if result.returncode != 0:
        raise SystemExit(result.returncode)
    print(f"  Wrote {new_cfg}")


if __name__ == "__main__":
    main()
