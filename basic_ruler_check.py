"""How wrong is each row, judged against the tape measure?

Run:
    python basic_ruler_check.py RECORDING.csv

The markers are glued to one rigid body, so the distance between any two of them is a constant
the tape already told us: 135, 158 and 160 mm. Every row measures those same three distances
again from the camera. Whatever it gets that is not the tape value is error, row by row.

Nothing is learned or fitted here - no offsets, no calibration, no fusing. That is the point:
this is the one check that does not depend on anything the pipeline decided, so it still works
when the calibration is wrong, and it is usually what tells you the calibration is wrong.

Distances are measured in camera space, which is fine because a distance between two points does
not care what frame it is expressed in - moving the head cannot change it. Only mismeasuring can.

Rows over BAD_DETECTION_MM are marked BAD. Nothing filters them out anywhere anymore -
load_csv() keeps every row - so this is the one place they become visible.
"""

import sys
from pathlib import Path

import numpy as np

from aruco_pose import marker_seen, read_pose
from simple_aruco_analysis import RULER_MM, load_csv

# A row whose measured marker distance is this far from the tape cannot be right - the markers
# are glued to one rigid body. Lives here now: this script is the one place that flags them.
BAD_DETECTION_MM = 30.0

PAIRS = list(RULER_MM)  # ("common","chest"), ("common","navel"), ("chest","navel")
LABEL = {"common": "ID0", "chest": "ID1", "navel": "ID2"}


def pair_error_mm(row, first, second):
    """Measured minus tape, in millimetres. None if either marker was not seen this row."""
    if not (marker_seen(row, first) and marker_seen(row, second)):
        return None
    measured = np.linalg.norm(read_pose(row, first)[0] - read_pose(row, second)[0]) * 1000
    return measured - RULER_MM[(first, second)]


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Run: python basic_ruler_check.py RECORDING.csv")

    path = Path(sys.argv[1])
    rows = load_csv(path)
    if not rows:
        raise SystemExit(f"{path} has no rows.")

    heading = "  ".join(f"{LABEL[a]}-{LABEL[b]:<6}" for a, b in PAIRS)
    print(f"\n{path.name}: {len(rows)} rows, error against the tape in mm\n")
    print(f"  {'row':>5}  {heading}  note")

    errors = {pair: [] for pair in PAIRS}
    bad_rows = 0
    for number, row in enumerate(rows, start=1):
        cells, worst = "", 0.0
        for pair in PAIRS:
            error = pair_error_mm(row, *pair)
            if error is None:
                cells += f"{'-':>9}  "  # Marker not seen: no opinion, not a zero error.
                continue
            errors[pair].append(error)
            worst = max(worst, abs(error))
            cells += f"{error:+9.1f}  "
        # A row over the threshold is a bad detection, not a measurement.
        bad = worst > BAD_DETECTION_MM
        bad_rows += bad
        print(f"  {number:5d}  {cells}{'BAD' if bad else ''}")

    print(f"\n  {'pair':<10}{'rows':>7}{'median':>10}{'worst':>10}")
    for pair in PAIRS:
        values = np.abs(errors[pair])
        name = f"{LABEL[pair[0]]}-{LABEL[pair[1]]}"
        if not len(values):
            print(f"  {name:<10}{0:>7}{'-':>10}{'-':>10}")
            continue
        print(f"  {name:<10}{len(values):>7}{np.median(values):>10.1f}{values.max():>10.1f}")

    print(f"\n  {bad_rows} of {len(rows)} rows are over {BAD_DETECTION_MM:.0f} mm - physically")
    print("  impossible detections. A large share means the calibration is off, not the data.")


if __name__ == "__main__":
    main()
