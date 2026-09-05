"""Shared loading and offset-learning for the ArUco analysis scripts.

Three jobs, nothing else: the tape-measure constants, reading a recording, and learning the
marker-to-ID0 offsets. Everything more specialised lives in the script that needs it.
"""

import csv

from aruco_pose import (
    MARKERS,
    marker_seen,
    normalize_rows,
    read_pose,
    relative_pose,
    stable_reference,
)

#no need-old
RULER_MM = {
    ("common", "chest"): 134.0,   # ID0 - ID1
    ("common", "navel"): 162.0,   # ID0 - ID2
    ("chest", "navel"): 170.0,    # ID1 - ID2
}


def all_seen(row):
    """True when ID0, ID1 and ID2 were all detected in this row."""
    return all(marker_seen(row, marker) for marker in MARKERS)


def load_csv(path):
    """Read a recording into a list of row dicts. Every row is kept, nothing is filtered.

    utf-8-sig, not utf-8: the logger writes a byte-order mark on some recordings, and utf-8
    leaves it attached to the first column name, so "sample_id" silently becomes qffsampleid unfindable.
    Reading as utf-8-sig strips it and behaves identically on files that have none.
    """
    with open(path, newline="", encoding="utf-8-sig") as file:#newline for cross-platform consistency of creating newlines
        return normalize_rows(list(csv.DictReader(file)))


def learn_offsets(rows):
    """Learn the fixed chest-to-ID0 and navel-to-ID0 poses.

    ID0 itself needs no offset - it is the reference the other two are measured against, so
    with N markers there are always N-1 learned offsets. Rows that cannot teach an offset
    (ID0 or the marker missing) are skipped here, so callers can pass a recording unfiltered.
    """
    offsets = {}

    for marker in ("chest", "navel"):
        marker_rows = [
            row for row in rows
            if marker_seen(row, "common") and marker_seen(row, marker)
        ]
        if not marker_rows:
            raise SystemExit(f"No rows contain common and {marker} for offset finding.")

        measured_offsets = [
            relative_pose(read_pose(row, marker), read_pose(row, "common"))
            for row in marker_rows
        ]
        offsets[marker] = stable_reference(measured_offsets)

    return offsets
