"""Should calibration treat every viewpoint equally, or trust the close ones more?

Run:
    python analyze_calibration_weighting.py LABELLED_WALK.csv

Measured on this walk, the error in a marker distance grows by about 11 mm per metre of range,
with a correlation of +0.95 across the six viewpoints. Standing at 1.2 m the three distances come
out right to a few tenths of a millimetre; at 1.85 m they are 7 mm out.

Calibration currently averages every sample equally. If distant samples really are worse, then
averaging them in does not cancel anything - it imports their error. A physical constant is best
estimated from the least noisy measurements of it, not from the most measurements of it.

Four ways of learning the offset are compared:

    all rows            what happens today: one robust centre over everything
    closest half        throw away the noisier half by range
    closest quarter     throw away three quarters
    weighted 1/range^2  keep everything, but let near samples dominate

Scored by LEAVE-ONE-VIEWPOINT-OUT cross validation. For each viewpoint in turn, the offset is
learned from the OTHER five and then used to rebuild ID0 on the held-out one. That matters: an
offset scored on the rows that produced it always looks good, and the question here is whether it
generalises to a viewpoint it has never seen - which is exactly what it must do in use.

ID0 is the target and only ID1 and ID2 are inputs, so nothing is scored against its own input.
"""

import sys
from pathlib import Path

import numpy as np

from aruco_pose import (
    MARKERS,
    combine,
    marker_seen,
    pose_difference,
    read_pose,
    relative_pose,
    stable_reference,
)
from simple_aruco_analysis import load_csv

LABEL = {"chest": "ID1", "navel": "ID2"}


def range_mm(row, marker):
    """How far the camera was from this marker when the row was recorded."""
    return float(np.linalg.norm(read_pose(row, marker)[0])) * 1000


def weighted_median(values, weights):
    """The value where half the WEIGHT lies either side, rather than half the count."""
    order = np.argsort(values)
    cumulative = np.cumsum(weights[order])
    return float(values[order][np.searchsorted(cumulative, cumulative[-1] / 2.0)])


def weighted_centre(samples, weights):
    """A robust weighted centre, matching stable_reference but letting samples carry weight.

    It must be robust for the comparison to be fair. A plain weighted MEAN would differ from the
    unweighted schemes in two ways at once - the weighting and the loss of outlier rejection -
    and a worse result could not be attributed to either.
    """
    weights = np.asarray(weights, dtype=float)
    weights = weights / weights.sum()
    positions = np.array([s[0] for s in samples])
    rotations = np.array([s[1] for s in samples])

    position = np.array([weighted_median(positions[:, axis], weights) for axis in range(3)])
    # Same "most central rotation" rule as stable_reference, with each vote weighted.
    scores = (1 - np.abs(rotations @ rotations.T)) @ weights
    return position, rotations[int(np.argmin(scores))]


def learn(rows, marker, scheme):
    """The marker-to-ID0 offset, learned from these rows under one weighting scheme."""
    usable = [r for r in rows if marker_seen(r, "common") and marker_seen(r, marker)]
    if len(usable) < 20:
        return None
    samples = [relative_pose(read_pose(r, marker), read_pose(r, "common")) for r in usable]
    ranges = np.array([range_mm(r, marker) for r in usable])

    if scheme == "all rows":
        return stable_reference(samples)
    if scheme.startswith("closest"):
        fraction = 0.5 if "half" in scheme else 0.25
        keep = np.argsort(ranges)[: max(20, int(len(ranges) * fraction))]
        return stable_reference([samples[i] for i in keep])
    if scheme.startswith("weighted"):
        return weighted_centre(samples, 1.0 / np.square(ranges))
    raise ValueError(scheme)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Run: python analyze_calibration_weighting.py LABELLED_WALK.csv")

    rows = [r for r in load_csv(Path(sys.argv[1]))
            if all(marker_seen(r, m) for m in MARKERS)]
    phases, seen = [], set()
    for row in rows:
        if row["phase_label"] not in seen:
            seen.add(row["phase_label"])
            phases.append(row["phase_label"])
    if len(phases) < 3:
        raise SystemExit("Need at least three labelled viewpoints to cross validate.")

    schemes = ("all rows", "closest half", "closest quarter", "weighted 1/range^2")
    results = {(s, m): [] for s in schemes for m in LABEL}

    for held_out in phases:
        train = [r for r in rows if r["phase_label"] != held_out]
        test = [r for r in rows if r["phase_label"] == held_out]
        for scheme in schemes:
            for marker in LABEL:
                offset = learn(train, marker, scheme)
                if offset is None:
                    continue
                for row in test:
                    results[(scheme, marker)].append(pose_difference(
                        combine(read_pose(row, marker), offset), read_pose(row, "common")))

    print(f"\nLeave-one-viewpoint-out over {len(phases)} viewpoints, {len(rows)} rows.")
    print("Rebuilding ID0 on a viewpoint the calibration never saw:\n")
    print(f"  {'how the offset was learned':<24}{'marker':>8}{'pos med':>10}{'pos p95':>10}"
          f"{'rot med':>10}{'rot p95':>10}")
    print(f"  {'':<24}{'':>8}{'mm':>10}{'mm':>10}{'deg':>10}{'deg':>10}")
    for scheme in schemes:
        for marker in LABEL:
            errors = results[(scheme, marker)]
            if not errors:
                continue
            e = np.array(errors)
            print(f"  {scheme:<24}{LABEL[marker]:>8}{np.median(e[:,0]):10.2f}"
                  f"{np.percentile(e[:,0],95):10.2f}{np.median(e[:,1]):10.2f}"
                  f"{np.percentile(e[:,1],95):10.2f}")

    print("\nLower is better. If 'all rows' wins, distant samples are not actually harmful and")
    print("calibration should keep averaging everything. If a closest-only scheme wins, the")
    print("headset should weight its calibration samples by range instead of counting them.")


if __name__ == "__main__":
    main()
