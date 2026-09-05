"""Does where you stand change what the camera measures? It should not, and it does.

    python analyze_viewpoints_distance.py LABELLED_WALK.csv

The markers are taped to the mannequin. The distance between them is a fixed physical fact, and a
tape measure says what it is: 135 mm and 158 mm. So every viewpoint should measure the same thing.

The script does four steps:

    1. learn the marker-to-ID0 offset from the WHOLE walk        - this is what ships to the headset
    2. learn it again from each viewpoint on its own             - near, far, crouch, standing, ...
    3. compare each one against the tape measure                 - the tape is the outside judge
    4. plot that error against how far away the headset was      - and see whether it follows range

If the viewpoints agreed, the error would be random and more samples from anywhere would help. They
do not agree, and the disagreement follows RANGE. That is the finding, and it says the fix is
physical - bigger markers, further apart - rather than more code.
"""

import sys
from pathlib import Path
from typing import NamedTuple

import numpy as np

from aruco_plot import save_scatter
from aruco_pose import (
    marker_seen,
    pose_difference,
    read_pose,
    relative_pose,
    stable_reference,
)
from simple_aruco_analysis import RULER_MM, load_csv

# What the tape measure says, in millimetres. The only lengths here that no camera produced, which
# is what makes them the judge rather than another opinion.
TAPE = {"chest": RULER_MM[("common", "chest")], "navel": RULER_MM[("common", "navel")]}

TITLE = {"chest": "ID1 chest", "navel": "ID2 navel"}
PAIR = {"chest": "Chest marker pair", "navel": "Navel marker pair"}

# Chart-only names. The printed tables keep the raw phase labels because those are what the logger
# wrote and what anyone searching the CSV will look for; the chart wants words that read at a
# glance, and "stand_tall" beside a dot reads as a variable name rather than as a person standing.
SHORT = {
    "near": "Near", "far": "Far", "left_side": "Left",
    "right_side": "Right", "crouch": "Crouch", "stand_tall": "Standing",
}

# Below this, a viewpoint has not seen enough to have an opinion worth printing.
MIN_ROWS = 15


class View(NamedTuple):
    """What one viewpoint concluded, and from how far away it concluded it."""

    name: str
    rows: int
    range_m: float          # Median headset-to-ID0 distance while standing there.
    arm_mm: float           # Marker-to-ID0 distance this viewpoint learned.
    off_tape_mm: float      # ...minus what the tape says. This is the error.
    off_average_mm: float   # ...and how far it sits from the offset that actually ships.
    off_average_deg: float


def teachable_rows(rows, marker):
    """Rows where BOTH ID0 and this marker were seen.

    An offset says where ID0 is relative to a marker, so a row that is missing either of them
    cannot teach one. Every count printed later is a count of these, not of raw rows.
    """
    return [r for r in rows if marker_seen(r, "common") and marker_seen(r, marker)]


def learn_offset(rows, marker):
    """Where ID0 sits as seen from this marker, learned from these rows. None if too few.

    stable_reference picks a robust centre rather than a mean, so one badly decoded frame cannot
    drag the answer - which matters here because a viewpoint may only have forty rows to work with.
    """
    usable = teachable_rows(rows, marker)
    if len(usable) < MIN_ROWS:
        return None
    return stable_reference(
        [relative_pose(read_pose(r, marker), read_pose(r, "common")) for r in usable]
    )


def arm_mm(offset):
    """The marker-to-ID0 distance an offset implies, in millimetres - the number the tape judges."""
    return float(np.linalg.norm(offset[0])) * 1000


def median_range_m(rows):
    """How far the headset was from ID0, typically, over these rows.

    Marker poses are stored relative to the CAMERA, so the camera is the origin of that frame and
    the range to ID0 is simply the length of ID0's position. Median rather than mean because the
    walk pauses and turns, and a few frames of leaning in should not move it.
    """
    seen = [np.linalg.norm(read_pose(r, "common")[0]) for r in rows if marker_seen(r, "common")]
    return float(np.median(seen))


def survey(rows, marker, whole):
    """One View per viewpoint - step 2 and 3 of the four at the top.

    Measures everything and prints nothing, so the table and the chart below are two renderings of
    one set of numbers rather than two calculations that could quietly drift apart.
    """
    views = []
    # dict.fromkeys keeps first-seen order, which is the order the viewpoints were walked in.
    for phase in dict.fromkeys(r["phase_label"] for r in rows):
        here = [r for r in rows if r["phase_label"] == phase]
        offset = learn_offset(here, marker)
        if offset is None:
            continue
        drift_mm, drift_deg = pose_difference(offset, whole)
        views.append(View(
            name=phase,
            rows=len(teachable_rows(here, marker)),
            range_m=median_range_m(here),
            arm_mm=arm_mm(offset),
            off_tape_mm=arm_mm(offset) - TAPE[marker],
            off_average_mm=drift_mm,
            off_average_deg=drift_deg,
        ))
    return views


def print_table(marker, whole, views):
    """One row per viewpoint: what it measured, and how wrong that was.

    'vs tape' is the error. 'vs all' is how far this viewpoint sits from the offset that actually
    ships to the headset - measured against that rather than against the worst other viewpoint,
    because the shipped average is what a bad viewpoint actually costs you.
    """
    print(f"\n=== {TITLE[marker]}  (tape says ID0 is {TAPE[marker]:.0f} mm away) ===\n")
    print(f"  {'viewpoint':<14}{'rows':>6}{'range m':>9}{'arm mm':>9}{'vs tape':>9}"
          f"{'pos vs all':>12}{'rot vs all':>12}")
    for view in views:
        print(f"  {view.name:<14}{view.rows:6d}{view.range_m:9.2f}{view.arm_mm:9.1f}"
              f"{view.off_tape_mm:+9.1f}{view.off_average_mm:12.1f}{view.off_average_deg:12.2f}")
    print(f"  {'ALL VIEWPOINTS':<14}{'':>6}{'':>9}{arm_mm(whole):9.1f}"
          f"{arm_mm(whole) - TAPE[marker]:+9.1f}")

    if views:
        arms = [v.arm_mm for v in views]
        print(f"\n  Arm length across viewpoints: {min(arms):.1f} to {max(arms):.1f} mm "
              f"(spread {max(arms) - min(arms):.1f} mm) - about markers that cannot move")
        print(f"  Closest to the tape: {min(views, key=lambda v: abs(v.off_tape_mm)).name}")


def draw_chart(path, series):
    """Step 4: the whole argument as one picture - distance across, error up.

    The slopes are deliberately NOT written on the chart. A chart answers "is there a trend and
    roughly how big"; the exact figure belongs in the table above, where it can carry the caveat
    that print_trend just measured.
    """
    save_scatter(
        path,
        "Measurement error increases with camera distance across viewpoints",
        series,
        "Headset distance from ID0 (m)",
        "Marker-distance error relative to tape measurement (mm)",
        zero_note="0 mm = perfect agreement with tape measurement",
        subtitle=("Each point is one calibration from a different viewpoint: crouching, standing, "
                  "near, far, left, or right. The mannequin and marker spacing stayed fixed; only "
                  "the headset position changed."),
        caption=("Each viewpoint produced a separate calibration while the mannequin and physical "
                 "marker distances remained unchanged. Despite differences in height and viewing "
                 "direction, measurement error generally increased with headset distance. The "
                 "effect was stronger for the ID0-ID2 distance than for ID0-ID1."),
    )


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Run: python analyze_viewpoints_distance.py LABELLED_WALK.csv")

    csv_path = Path(sys.argv[1])
    rows = load_csv(csv_path)
    if len(set(r["phase_label"] for r in rows)) < 2:
        raise SystemExit("This recording has no phase labels - nothing to compare.")

    series = {}
    for marker in ("chest", "navel"):
        whole = learn_offset(rows, marker)          # 1. the offset that ships
        if whole is None:
            print(f"\n{TITLE[marker]}: too few rows.")
            continue
        views = survey(rows, marker, whole)         # 2. and one per viewpoint
        print_table(marker, whole, views)           # 3. judged against the tape
        series[PAIR[marker]] = [
            (v.range_m, v.off_tape_mm, SHORT.get(v.name, v.name)) for v in views
        ]

    if series:
        draw_chart(csv_path.with_name(csv_path.stem + "_viewpoints.png"), series)  # 4.


if __name__ == "__main__":
    main()
