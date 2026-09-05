"""Shared parts of the ArUco analysis: reading the CSV and pose arithmetic.

A pose is a pair: (position xyz in metres, rotation quaternion xyzw).

Matched to the format of the kept recordings (data/today/walk_final_*.csv and
headmotion_*.csv). Their columns are:

    sample_id, logger_ms, recording_ms, test_type, phase_label,
    then x, y, z, qx, qy, qz, qw for camera, common, chest and navel.

A marker that was not detected in a row simply has empty pose cells.
"""

import numpy as np


# Marker names as the CSV uses them. "navel" is ID2's historical column name; the data is ID2.
MARKERS = ("common", "chest", "navel")


# ---------------------------------------------------------------------------
# Reading a CSV row
# ---------------------------------------------------------------------------

def normalize_row(row):
    """Guarantee every expected CSV field exists, so lookups never KeyError.

    Missing fields become empty strings, which read_pose() and marker_seen() treat
    as "not detected". The field list matches the recordings' actual header.
    """
    normalized = dict(row or {})#each row is a dict,but the csv.dict reader can read a blank line as none,so we default to emptz dict
    for body in MARKERS + ("camera",):
        for axis in "xyz":
            normalized.setdefault(f"{body}_{axis}", "")
        for axis in "xyzw":
            normalized.setdefault(f"{body}_q{axis}", "")
    for field in ("sample_id", "logger_ms", "recording_ms", "test_type", "phase_label"):
        normalized.setdefault(field, "")
    return normalized


def normalize_rows(rows):
    """normalize_row() over a whole recording."""
    return [normalize_row(row) for row in rows]


def marker_seen(row, marker):
    """True if this row detected the marker: the logger leaves pose cells empty otherwise."""
    return (row.get(f"{marker}_x") or "") != ""


def read_pose(row, marker):
    """The marker's (position, quaternion) from one row.

    Camera poses are in world space; marker poses are relative to the camera.
    
    """
    position_values = [row.get(f"{marker}_{axis}", "") for axis in "xyz"]#get position
    if any(value in ("", None) for value in position_values):
        return np.zeros(3), np.array([0.0, 0.0, 0.0, 1.0])

    rotation_values = [row.get(f"{marker}_q{axis}", "") for axis in "xyzw"]
    if any(value in ("", None) for value in rotation_values):
        return np.array(position_values, dtype=float), np.array([0.0, 0.0, 0.0, 1.0])

    position = np.array(position_values, dtype=float)
    rotation = np.array(rotation_values, dtype=float)
    norm = np.linalg.norm(rotation)
    if norm == 0:
        return position, np.array([0.0, 0.0, 0.0, 1.0])
    return position, rotation / norm


# ---------------------------------------------------------------------------
# Pose arithmetic
# ---------------------------------------------------------------------------

def quaternion_multiply(a, b):
    """Compose two rotations: first b, then a. Renormalised against rounding drift."""
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    result = np.array([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])
    return result / np.linalg.norm(result)

#no neeed-old code
def rotate(rotation, vector):
    """Turn a vector by a quaternion - e.g. a marker-frame offset into world direction."""
    xyz = rotation[:3]
    w = rotation[3]
    return vector + 2 * (
        w * np.cross(xyz, vector) + np.cross(xyz, np.cross(xyz, vector))
    )

#returns common’s pose in marker’s local coordinate system.
# Later, we multiply marker‑world × marker‑local‑offset
#to get ID0 in world space.
def relative_pose(source, target):
    """Where target sits as seen from source: inverse(source) * target.
    """
    #the marker becomes the origin of the coordinate system.
    inverse_rotation = source[1] * [-1, -1, -1, 1]#Undo the marker’s rotation so we can express things in the marker’s local coordinate system.
    #This gives:common in MARKER’S LOCAL COORDINATE SYSTEM.  COMMON’s position as seen from the MARKER.This is the position offset.
    #Where is common relative to marker, in world coordinates,#
    # rotate that vector into marker’s local frame-This gives:
    position = rotate(inverse_rotation, target[0] - source[0])
#How much rotation you need to go from marker’s orientation to common’s orientation.”This is the rotation offset.R inverse amrker multiplied by R common
    rotation = quaternion_multiply(inverse_rotation, target[1])
    return position, rotation


def combine(parent, child):
    """Chain two poses: parent * child.

    combine(camera_in_world, marker_in_camera) -> marker in world, and
    combine(marker_in_world, stored_offset)    -> ID0 in world.
    """
    position = parent[0] + rotate(parent[1], child[0])
    rotation = quaternion_multiply(parent[1], child[1])
    return position, rotation


def average_poses(first, second):
    """Midpoint of two poses: mean position, sign-aligned mean rotation.

    q and -q are the same rotation, so the signs are lined up first - otherwise
    two nearly identical rotations could average into nonsense.
    """
    position = (first[0] + second[0]) / 2
    rotation_a, rotation_b = first[1], second[1]
    if np.dot(rotation_a, rotation_b) < 0:
        rotation_b = -rotation_b
    rotation = rotation_a + rotation_b
    return position, rotation / np.linalg.norm(rotation)

#median ,medoid
def stable_reference(poses):
    """A robust centre: median position plus the most central measured rotation.

    The rotation is a medoid, not an average - the winner is always a rotation
    that was really detected, so one bad detection cannot drag the reference.
    """
    positions = np.array([pose[0] for pose in poses])
    rotations = np.array([pose[1] for pose in poses])

    position = np.median(positions, axis=0)
    # |dot| because q and -q are the same rotation; the smallest summed
    #how a medoid rotation is found,gives a vector like total distance of rot 1,total r´distance of rot 2
    rotation_scores = np.sum(1 - np.abs(rotations @ rotations.T), axis=1)
    #How noisy is rotation i compared to all other frames?
    rotation = rotations[np.argmin(rotation_scores)]
    #his picks the quaternion with the lowest total noise.
    return position, rotation

#no need-old code
def pose_difference(first, second):
    """Distance in millimetres and angle in degrees between two poses."""
    position_mm = np.linalg.norm(first[0] - second[0]) * 1000
    quaternion_dot = abs(np.dot(first[1], second[1]))
    rotation_deg = np.degrees(2 * np.arccos(np.clip(quaternion_dot, 0, 1)))
    return position_mm, rotation_deg
