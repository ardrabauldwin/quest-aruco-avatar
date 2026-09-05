"""The lying-flat SANITY CHECK: phantom detections betray themselves by impossible tilt.

Run (the CSV names are set in main):
    python basic_tilt_gate_check.py

The idea (suggested as "sanity check"): a mannequin lying on the floor cannot be
tilted far out of the floor plane. So ask every detection "how tilted do you claim
the mannequin is?" - and if the answer is impossible, reject the WHOLE detection,
position included. A detection that lies about tilt is lying about everything.

Why this gate matters more than the others: the ruler check needs 2 visible markers,
and the max-speed check only fires on the FIRST frame of a jump. The sustained
12-row phantom in walk_final (single marker, self-consistent) walks past both. The
tilt check judges every row independently and needs only one marker.

walk_final is the disease, headmotion is the control (no phantoms - the gate should
fire rarely there).
"""

from pathlib import Path

import numpy as np

from basic_tune_filter import flatten_to_yaw, load_poses, settle_prior
from filter_errors import angle_deg

# A detection further than this from the mannequin's true spot is a phantom. The
# markers never moved during the recordings, so the overall median position is truth.
PHANTOM_MM = 100.0

GATES_DEG = (5.0, 10.0, 15.0, 20.0, 30.0)


def main():
    for name in ("data/today/walk_final_1785760244.csv",
                 "data/today/headmotion_1785761051.csv"):
        positions, rotations, avg_gap = load_poses(Path(name))
        pos_prior, rot_prior = settle_prior(positions, rotations, avg_gap)

        # Tilt claimed by each detection = angle between its rotation and the same
        # rotation with the impossible (out-of-plane) part removed.
        tilt = np.array([angle_deg(q, flatten_to_yaw(q, rot_prior))
                         for q in rotations])

        distance_mm = np.linalg.norm(
            positions - np.median(positions, axis=0), axis=1) * 1000
        phantom = distance_mm > PHANTOM_MM

        print(f"\n{name}")
        print(f"  detections: {len(positions)},"
              f" phantom rows (>{PHANTOM_MM:.0f} mm off): {phantom.sum()}")
        print(f"  tilt of honest rows : median {np.median(tilt[~phantom]):5.1f} deg,"
              f" p95 {np.percentile(tilt[~phantom], 95):5.1f} deg")
        if phantom.any():
            print(f"  tilt of phantom rows: median {np.median(tilt[phantom]):5.1f} deg,"
                  f" min {tilt[phantom].min():5.1f} deg")

        print(f"\n  {'gate':>7} {'phantoms caught':>16} {'honest rejected':>16}")
        for threshold in GATES_DEG:
            caught = ("-" if not phantom.any()
                      else f"{(tilt[phantom] > threshold).mean() * 100:14.0f}%")
            lost = (tilt[~phantom] > threshold).mean() * 100
            print(f"  {threshold:5.0f}deg {caught:>16} {lost:15.1f}%")

    print("\n  A rejected row is harmless: the avatar holds its last pose one frame,"
          "\n  exactly what already happens when no marker is seen.")


if __name__ == "__main__":
    main()
