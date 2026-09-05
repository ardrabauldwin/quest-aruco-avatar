"""Calculate position and rotation errors from a recorded pose sequence."""

import numpy as np

#Shortest angle between two quaternion
def angle_deg(first_rotation, second_rotation):
    """Return the shortest angle between two quaternions, in degrees."""
    dot = abs(float(np.dot(first_rotation, second_rotation)))
    return np.degrees(2.0 * np.arccos(np.clip(dot, 0.0, 1.0)))
#Floating‑point rounding can push dot slightly outside [0,1].Clipping avoids NaNs.

def three_errors(steps, distances_from_centre):
    """Return ordinary wobble, bad-frame jump, and centre drift."""
    wobble = float(np.median(steps))
    jump = float(np.percentile(steps, 95))
    drift = float(np.median(distances_from_centre))
    return wobble, jump, drift


def measure_errors(positions, rotations):
    """Return wobble, jump and drift for position (mm) and rotation (degrees).

    Result order:
        position_wobble_mm, position_jump_mm, position_drift_mm,
        rotation_wobble_deg, rotation_jump_deg, rotation_drift_deg
    """#he movement between every pair of consecutive frames, in millimetres.
    #wobble + jump
    position_steps_mm = np.linalg.norm(np.diff(positions, axis=0), axis=1) * 1000.0
    position_centre = np.median(positions, axis=0)
    #position_distances_mm → drift
    position_distances_mm = np.linalg.norm(positions - position_centre, axis=1) * 1000.0

    rotation_steps_deg = np.array([
        angle_deg(first, second) for first, second in zip(rotations, rotations[1:])
    ])#A list of rotation differences between every consecutive row in your CSV.

    # Choose the recorded rotation with the smallest total distance to all others.
    distances = 1.0 - np.abs(rotations @ rotations.T)
    rotation_centre = rotations[int(np.argmin(np.sum(distances, axis=1)))]
    rotation_distances_deg = np.array([
        angle_deg(rotation, rotation_centre) for rotation in rotations
    ])

    return (
        *three_errors(position_steps_mm, position_distances_mm),
        *three_errors(rotation_steps_deg, rotation_distances_deg),
    )
