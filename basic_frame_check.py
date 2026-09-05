"""Show that the filter-tuning scores do not depend on the world frame.

Run (the CSV name is set in main):
    python basic_frame_check.py

The experiment: re-express the whole recording in a different fixed frame - rotate every
pose 37 degrees about a tilted axis, as if the mannequin was re-laid and the headset got a
new XR origin - then measure the same six errors again. Wobble, jump and drift are all
distances and angles, and those do not change when the axes turn, so the two rows should
match. (Position drift may differ by a few hundredths of a millimetre: its centre is a
per-axis median, and per-axis medians shift microscopically when the axes rotate.)

This is why basic_tune_filter.py needs no body-frame conversion: unlike the rotation
analysis, it never splits an error into X/Y/Z components, so there is no axis choice to
standardise away.
"""

from pathlib import Path

import numpy as np

from aruco_pose import quaternion_multiply, rotate
from basic_tune_filter import load_poses
from filter_errors import measure_errors

# The arbitrary frame change: 37 degrees about a tilted axis. Any angle and axis works -
# that arbitrariness is the point.
TILT_AXIS = np.array([0.36, 0.48, 0.80])  # unit length
TILT_DEG = 37.0


def main():
    name = "data/today/headmotion_1785761051.csv"  # markers still, head moving

    positions, rotations, gaps = load_poses(Path(name))

    # Rotate the whole world: p' = R0 * p, q' = R0 * q, one fixed R0 for every frame.
    half = np.radians(TILT_DEG / 2)
    frame_change = np.array([*(np.sin(half) * TILT_AXIS), np.cos(half)])
    positions_tilted = np.array([rotate(frame_change, p) for p in positions])
    rotations_tilted = np.array([quaternion_multiply(frame_change, q) for q in rotations])

    original = measure_errors(positions, rotations)
    tilted = measure_errors(positions_tilted, rotations_tilted)

    labels = ("pos wobble", "pos jump", "pos drift", "rot wobble", "rot jump", "rot drift")
    print(f"\n{name}, same six errors in two different world frames:\n")
    print(f"  {'measure':<12}{'original':>10}{'tilted':>10}")
    for label, a, b in zip(labels, original, tilted):
        print(f"  {label:<12}{a:10.3f}{b:10.3f}")
    print(f"\n  largest difference: {max(abs(a - b) for a, b in zip(original, tilted)):.4f}")
    print("  Distances and angles do not care which way the axes point.")


if __name__ == "__main__":
    main()
