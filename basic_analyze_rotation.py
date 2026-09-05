"""Measure false rotation around each world axis while the body is stationary.

Run:
    python basic_analyze_rotation.py RECORDING.csv

The markers never moved during the test, so every measured rotation change is noise. The table
splits that noise into world X, Y and Z, and also gives the total 3D angle. 

"""

import csv
import sys
from pathlib import Path

import numpy as np

from aruco_pose import (
    MARKERS, combine, marker_seen, normalize_rows, quaternion_multiply, read_pose, rotate,
)
from simple_aruco_analysis import learn_offsets

# Rotation is invisible in millimetres until you say where you are measuring it. Half a metre is
# about hip to shoulder on the mannequin, so it reads as "how far the avatar's chest slides".
ROTATION_RADIUS_MM = 500.0

#Convert the marker's pose from camera space into world space. #

def world_pose(row, marker):
  return combine(read_pose(row, "camera"), read_pose(row, marker))

##Return the one combined pose when fused pose find each
#called bz next function,fuse
def fuse(poses):
    position = np.mean([pose[0] for pose in poses], axis=0)#just mean
    first = poses[0][1]#first elements quartenion
    # q and -q are the same rotation, so unaligned signs would cancel into nonsense.
    rotation = sum((q if first @ q > 0 else -q) for q in (pose[1] for pose in poses))
    return position, rotation / np.linalg.norm(rotation)

##Collect all marker‑based ID0 poses,If just on e,find it out
def fused_pose(row, offsets):
    """Every visible marker's estimate of ID0, fused. None if nothing was seen."""
    views = []#Create an empty list to store each marker’s ID0 estimate.
    for marker in MARKERS:
        if not marker_seen(row, marker):
            continue#skip
        base = world_pose(row, marker)
        offset = offsets.get(marker)#Get the marker→ID0 offset from the learned offset dictionarz,IT IS CONSTANT
        views.append(base if offset is None else combine(base, offset))
    return fuse(views) if views else None

def rotation_centre(rotations):
    """
    Find the MOST CENTRAL quaternion (the medoid) among all ID0 rotations.
    
    Input:
        rotations : Nx4 array of unit quaternions (ID0 world rotations)

    Output:
        A single quaternion that is closest to all others.
    """

    # 1. Compute NxN similarity matrix using quaternion dot products.
    #    High dot → rotations are similar. Low dot → rotations differ.
    similarity = rotations @ rotations.T

    # 2. Fix quaternion sign ambiguity.
    #    q and -q represent the SAME rotation, but their dot product flips sign.
    #    abs() ensures similarity is correct even if some quaternions are flipped.
    similarity = np.abs(similarity)

    # 3. Convert similarity → distance.
    #    Distance = 1 - similarity.
    #    If similarity = 1.0 (identical), distance = 0.
    #    If similarity is small, distance is large.
    distance = 1.0 - similarity

    # 4. Sum distances for each quaternion.
    #    This gives one number per rotation:
    #    “How far is this rotation from all other rotations?”
    total_distance = np.sum(distance, axis=1)

    # 5. Pick the quaternion with the smallest total distance.
    #    This is the medoid — the rotation closest to all others.
    centre_index = int(np.argmin(total_distance))

    # 6. Return the most central rotation.
    return rotations[centre_index]


def body_rotation_vector(quaternion, centre):
    """
    PURPOSE:ID0’s world‑space rotation → rotation expressed in ID0’s own body axes.
        

        Output is a 3‑component rotation vector:
            X = left–right tilt
            Y = forward–back bend
            Z = twist

        The LENGTH of this vector is the TOTAL rotation angle.

    INPUTS:
        quaternion : the ID0 WORLD rotation for this frame
        centre     : the ID0 BASELINE rotation (the medoid of all ID0 rotations)

        centre is NOT from markers.
        centre is NOT from offsets.
        centre is NOT from calibration.

        centre comes from:
            rotation_centre(all_id0_world_rotations)

        i.e., the most central ID0 rotation across the entire session.
    """

    # 1. Compute inverse(centre)
    #    This "undoes" the baseline rotation so that all rotation is expressed
    #    in the BODY's own coordinate system-the ID0 rotation that represents the body’s neutral, baseline, “origin” (ID0 axes).
    #
    #    If we did NOT invert centre first, the rotation would be expressed
    #    in WORLD axes — which change when XR origin changes.
    inverse_centre = centre * np.array([-1.0, -1.0, -1.0, 1.0])

    # 2. Compute delta rotation: centre⁻¹ * quaternion
    #    This answers:
    #        "How much rotation happened relative to the body's baseline in this frame?"
    #
    #    This is the rotation difference between:
    #        - ID0 baseline orientation
    #        - ID0 orientation in this frame
    delta = quaternion_multiply(inverse_centre, quaternion)

    # 3. Ensure shortest path around quaternion sphere
    #    If w < 0, flip the quaternion so the angle is never reported as 350°.
    #    This keeps angles continuous and avoids sudden jumps.
    if delta[3] < 0.0:#x,z,y,w,3 is w
        delta = -delta

    # 4. Compute axis magnitude
    #    If axis_norm == 0 → rotations are identical → return zero vector.
    axis_norm = np.linalg.norm(delta[:3])
    if axis_norm < 1e-12:
        return np.zeros(3)

    # 5. computing actual roataion angle from quartenion.(radians).
    #    angle = 2 * atan2(|axis|, w)
    angle = 2.0 * np.arctan2(axis_norm, np.clip(delta[3], -1.0, 1.0))#w is between -1 and1,but floating point eroors.

    # 6. Convert axis × angle → degrees
    #    axis is normalized, so axis * angle gives the rotation vector.
    return np.degrees(delta[:3] / axis_norm * angle)#get rx ,ry,rz



# Compute rotation difference from the recording's own centre for each frame.
def measure_noise(rows, offsets):
    """
    Compute the median rotation wander of ID0 about its own baseline orientation.

    This function:
        1. Reconstructs ID0's world rotation for every frame.
        2. Finds  (the medoid) across the whole recording.
        3. Computes per‑frame rotation difference relative to that baseline.
        4. Returns the median X/Y/Z tilt and median total rotation angle.

    Position noise has been removed.
    """

    # Reconstruct ID0 pose for each row (fusing markers + offsets).
    fused = [pose for pose in (fused_pose(row, offsets) for row in rows) if pose is not None]
    if not fused:
        raise SystemExit("No row produced a pose - no markers were seen.")

    # Extract all ID0 world rotations.
    rotations = np.array([pose[1] for pose in fused])

    #  the medoid of all ID0 rotations.
    centre = rotation_centre(rotations)

    # Compute rotation difference from centre for each frame.
    # ABSOLUTE values: rotation wander is symmetric (+/-), so signed medians
    components = np.abs(np.array([body_rotation_vector(q, centre) for q in rotations]))

    # The total rotation vector's length IS the total rotation angle.
    # Length ignores sign, so absolute-value choice does not matter here.
    total = np.linalg.norm(components, axis=1)

    # Return three statistics per axis and for the total, each answering its own question:
    #   median = the TYPICAL frame (spikes cannot drag it; the README's numbers)
    #   mean   = average error INCLUDING the spike mass (bigger than median when tails exist)
    #   p95    = the bad-but-not-worst frame (where the spikes live)
    return (
        len(fused),
        np.median(components, axis=0), float(np.median(total)),
        components.mean(axis=0), float(total.mean()),
        np.percentile(components, 95, axis=0), float(np.percentile(total, 95)),
    )



def main():
    name = "data/today/headmotion_1785761051.csv"   # markers still, head moving - the wander test

    with open(Path(name), newline="", encoding="utf-8-sig") as file:
        rows = normalize_rows(list(csv.DictReader(file)))

    (count, med_axes, med_total,
     mean_axes, mean_total,
     p95_axes, p95_total) = measure_noise(rows, learn_offsets(rows))

    print(f"\n{name}: {count} poses, rotation repeatability error (degrees):\n")

    print(f"  {'axis':<10}{'median':>9}{'mean':>9}{'p95':>9}"
          f"{'mm at ' + str(int(ROTATION_RADIUS_MM)) + ' mm':>16}")
    for label, med, mean, p95 in zip(("Body X", "Body Y", "Body Z"),
                                     med_axes, mean_axes, p95_axes):
        mm = np.radians(med) * ROTATION_RADIUS_MM  # the mm column converts the MEDIAN
        print(f"  {label:<10}{med:9.2f}{mean:9.2f}{p95:9.2f}{mm:16.2f}")

    total_mm = np.radians(med_total) * ROTATION_RADIUS_MM
    print(f"  {'Total 3D':<10}{med_total:9.2f}{mean_total:9.2f}{p95_total:9.2f}{total_mm:16.2f}")
    print("\n  median = typical frame, mean = average incl. spikes, p95 = bad frame.")


if __name__ == "__main__":
    main()
