"""Show WHY the filter aims at a moving medoid, not a moving average.

Run (the CSV name is set in main):
    python basic_medoid_check.py

The demonstration: find the worst single jump in the recording - a pose flip, where one
detection lands over a metre from where the markers really were - and look at the window
of 5 detections around it, the same window the filter sees.

An outlier DRAGS an average: every sample contributes 1/5th, so a 1400 mm phantom pulls
the target ~280 mm toward a place the mannequin never was. The same outlier can only LOSE
a medoid vote: it is far from everyone, so it scores worst and a real detection wins.

Control: run the same script on headmotion (no outliers) and the two targets tie - the
medoid costs nothing on clean data. The rig's _medoid() comment says it in one line:
"the medoid can only ever return a pose that was really detected"
(project/simple_pose_stabilizer.gd:130-132).
"""

from pathlib import Path

import numpy as np

from basic_analyze_rotation import rotation_centre
from basic_tune_filter import load_poses

WINDOW = 5


def main():
    name = "data/today/walk_final_1785760244.csv"  # the recording WITH flip rows

    positions, rotations, avg_gap = load_poses(Path(name))

    # The worst frame-to-frame jump marks the outlier; make it the window's newest sample,
    # which is exactly how the filter meets it.
    steps = np.linalg.norm(np.diff(positions, axis=0), axis=1) * 1000
    newest = int(np.argmax(steps)) + 1
    first = newest - WINDOW + 1
    near_p = positions[first:newest + 1]
    near_r = rotations[first:newest + 1]

    print(f"\n{name}")
    print(f"worst jump: {steps.max():.1f} mm, at detection {newest} of {len(positions)}\n")
    print(f"the window of {WINDOW} detections (distance from the window's first sample):")
    for k, p in enumerate(near_p):
        d = np.linalg.norm(p - near_p[0]) * 1000
        print(f"  sample {k}: {d:8.1f} mm" + ("   <-- the outlier" if d > 100 else ""))

    # Where would each rule aim the filter? Judged against the cluster of honest samples
    # (their per-axis median).
    cluster = np.median(near_p, axis=0)
    average_target = near_p.mean(axis=0)
    centre = rotation_centre(near_r)
    winner = int(np.argmax(np.abs(near_r @ centre)))

    print(f"\n  moving AVERAGE target: {np.linalg.norm(average_target - cluster) * 1000:7.1f} mm"
          " from the honest cluster")
    print(f"  moving MEDOID  target: {np.linalg.norm(near_p[winner] - cluster) * 1000:7.1f} mm"
          f" from the honest cluster (sample {winner} won the vote)")
    print("\n  An outlier drags an average by outlier/5. It can only LOSE a medoid vote.")


if __name__ == "__main__":
    main()
