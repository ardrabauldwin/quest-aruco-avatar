"""Try every filter setting on one recording and print the ten best.

Run (the CSV name is set in main):
    python basic_tune_filter.py

Replays the fused ID0 pose through a Python copy of simple_pose_stabilizer.gd, once per
setting. Score = share of the unfiltered wobble, jump and drift left over (0 = perfect,
1 = the filter did nothing).

The filter, in order: tilt GATE (reject impossible detections) -> median target ->
dead zone + easing -> pull toward the anchor -> flat LOCK (delete impossible tilt)
-> the anchor itself heals slowly (self-healing prior).

If the winner's position wobble is ~0.00 it is FROZEN - prefer a non-zero row.
"""

from itertools import product
from pathlib import Path

import numpy as np

from aruco_pose import quaternion_multiply
from basic_analyze_rotation import fused_pose
from filter_errors import angle_deg, measure_errors
from simple_aruco_analysis import learn_offsets, load_csv

# The grid. Every combination is tried: 4 x 4 x 4 = 64 settings.
# (No rotation dead zone: it measurably changed nothing once the pull and the
# flat lock guarded rotation, so it was removed.)
WINDOWS = [1, 3, 5, 7]
POSITION_DEAD_ZONES_M = [0.000, 0.002, 0.004, 0.006]
SMOOTHING_TIMES_S = [0.1, 0.25, 0.5, 0.8]

# The ANCHOR pull (mean-reverting): every detection drifts gently back toward the
# settled anchor. An INPUT, not searched: a stationary recording always votes for a
# stronger pull, so the sweep cannot price its real cost (lag after a genuine move).
PRIOR_TIME_S = 1.0

# Self-healing: the anchor itself follows the estimate as a very slow EMA, so a
# genuinely moved mannequin is accepted in ~2-4 minutes - no button, no re-settle.
SLOW_TIME_S = 60.0

# Physics of a lying mannequin: it cannot tilt out of the floor plane. A detection
# claiming more tilt than this is a lie - rejected before filtering. Chosen between
# the two measured piles (honest rows reach ~28 deg on walk_final, phantoms all
# claim 37+); re-check with basic_tilt_gate_check.py on every new recording.
GATE_TILT_DEG = 30.0


# =========================================================================
# 1. LOADING THE RECORDING  (CSV rows -> one fused ID0 pose per frame)
# =========================================================================

#time to second
def row_time_s(row):
    """Seconds for this row from the logger's clock; None if the cell is empty."""
    value = row.get("logger_ms", "")
    return float(value) / 1000 if value else None

#fused ido pose per row
def load_poses(path):
    """Fused ID0 world pose per row, plus the average time between detections.

    # The offset is "how far ID0 is FROM THIS MARKER" - it stays true only while the marker and the body move TOGETHER; re-glue the marker and the stored number becomes a constant bias no filter can catch
    """
    rows = load_csv(path)
    offsets = learn_offsets(rows)#JUST ONE TIME

    detections = []  # (row FULL AS DICTIONARZ,, pose) for every row where at least one marker was seen
    for row in rows:
        pose = fused_pose(row, offsets)#IF ONE SAME,IF MORE AVG
        if pose is not None:
            detections.append((row, pose))


    positions = np.array([pose[0] for _, pose in detections])
    rotations = np.array([pose[1] for _, pose in detections])

    first, last = row_time_s(detections[0][0]), row_time_s(detections[-1][0])
    if first is None or last is None or last <= first:
        raise SystemExit(f"{path}: timestamps are missing or not increasing.")
    avg_gap = (last - first) / (len(detections) - 1)
    return positions, rotations, avg_gap


# =========================================================================
# 2. avg of 1 sec detections.
# THE ANCHOR  (the filter's belief of the mannequin's home pose)
#    Averaged from the first second = about 4 detections on these recordings
#    (645 rows over 145 s = 4.5 per second), so roughly 2x steadier than one.
# =========================================================================

def settle_prior(positions, rotations, avg_gap):
    """The anchor pose: position mean + sign-aligned rotation average of the first second.
    """
    count = int(round(1.0 / avg_gap))  # how many detections fit in one second
    position_prior = np.mean(positions[:count], axis=0)

    first = rotations[0]
    total = sum(q if first @ q > 0 else -q for q in rotations[:count])
    rotation_prior = total / np.linalg.norm(total)
    return position_prior, rotation_prior


# =========================================================================
# 3. ROTATION HELPERS 
# =========================================================================
#
# WHAT DOES yaw_of DO?
#  Line by line:
#
#   conjugate = rest * [-1,-1,-1, 1]
#       The conjugate of a unit quaternion (flip x,y,z; keep w) is its INVERSE:
#       the rotation that undoes rest.
#
#   delta = quaternion_multiply(q, conjugate)
#       q x rest^-1 = the DIFFERENCE rotation: what extra turn, applied in WORLD
#       axes, takes the rest pose to q. The order matters - this order gives the
#       difference in world axes, which is what we need because "vertical" is a
#       world direction. (The other order, rest^-1 x q, gives it in BODY axes -
#       that is what body_rotation_vector in basic_analyze_rotation.py uses.)
#
#   if delta[3] < 0: delta = -delta
#       The q/-q trap again: force w positive so the angle reads the short way
#       around (-5 deg), never the long way (+355 deg).
#
#   return 2.0 * arctan2(delta[1], delta[3])
#       The measurement. Key fact: a PURE YAW by angle t has the quaternion
#           [ 0, sin(t/2), 0, cos(t/2) ]
#               ^ y slot      ^ w slot
#       So y and w together encode the yaw: arctan2(delta[1], delta[3]) recovers
#       t/2 (with its sign - that is why the result is signed) and the 2.0 x
#       gives t in radians. The x and z slots - the TILT content - are simply not
#       consulted: whatever tilt noise the detection carries, this function looks
#       past it and reads only the yaw.
#
# 
#
# SIBLINGS: flatten_to_yaw and yaw_of are the SAME decomposition for two purposes.
# flatten_to_yaw KEEPS the yaw part and rebuilds a full quaternion (repair tool);
# yaw_of just MEASURES the yaw part as a number (measuring tool). 

'''how much has this sample rotated, compared to the anchor or prior or avg, about the vertical (Y) axis'''
def yaw_of(q, rest):#rest is prior or anchor
    """Signed yaw angle (radians) of q relative to rest, about world Y."""
    conjugate = rest * np.array([-1.0, -1.0, -1.0, 1.0])#The conjugate of a unit quaternion (flip x,y,z; keep w) is its INVERSE:
#       the rotation that undoes rest.
    delta = quaternion_multiply(q, conjugate)
    if delta[3] < 0.0:
        delta = -delta
    return 2.0 * np.arctan2(delta[1], delta[3])#the code zeroes two quaternion slots (delta.x and delta.z) while keeping delta.y and delta.w.


def blend_rotation(a, b, amount):
    """
    Move rotation quaternion `a` toward quaternion `b` by a fraction `amount`.
    """

    # Flip b if needed so we interpolate along the shortest arc.
    if np.dot(a, b) < 0:
        b = -b

    # Move a fraction `amount` toward b.
    mixed = a + (b - a) * amount#final target

    # Keep quaternion valid (unit length).
    return mixed / np.linalg.norm(mixed)


def flatten_to_yaw(q, rest):
    """keep only its yaw relative to rest.
# 
#
#   1. delta = how much this sample rotated compared to rest prior (world axes)
#   2. delete the x and z parts of delta  -> the tilt (IMPOSSIBLE for a resting body)
#   3. keep the y and w parts             -> the yaw  (possible: spinning on the floor)
#   4. rebuild: rest tilt + the sample's OWN yaw on top
##since x,z has most noise it got removed

    """
    conjugate = rest * np.array([-1.0, -1.0, -1.0, 1.0])
    delta = quaternion_multiply(q, conjugate)
    if delta[3] < 0.0:
        delta = -delta
    twist = np.array([0.0, delta[1], 0.0, delta[3]])  # the world-Y (yaw) part only
    norm = np.linalg.norm(twist)
    if norm < 1e-12:
        return rest.copy()  # pure sideways tilt, no yaw content at all
    return quaternion_multiply(twist / norm, rest)


# =========================================================================
# 4. THE TARGETS  (where the filter aims, one target pose per frame)
# =========================================================================

def window_targets(positions, rotations, window, rest):
    """
    Compute the target pose for each sample from a sliding window.

    POSITION target = per-axis MEDIAN 

    ROTATION target = the MEDIAN YAW .
    """

    # Start with targets equal to raw detections.
    # We will overwrite targets only AFTER the window is full.
    target_p = positions.copy()
    target_r = rotations.copy()

    # Each detection's yaw angle relative to the rest orientation.
    yaws = np.array([yaw_of(q, rest) for q in rotations])

    # Loop from the first frame where the window is full:
    # Example: window = 5 → start at i = 4
    for i in range(window - 1, len(positions)):

        # The sliding window covers frames:
        # first, first+1, ..., i
        first = i - window + 1

        # Per-axis median of the last `window` positions.
        target_p[i] = np.median(positions[first : i + 1], axis=0)
## WHY the / 2 ?  A quaternion rotates a point by SANDWICHING it:
        #     rotated = q ⊗ v ⊗ q⁻¹     (q acts twice - from left and right)
        # Each of the two touches contributes the stored angle, so for a total
        # turn of θ the quaternion must STORE only θ/2.
        # Rule: writing a quaternion -> sin/cos of θ/2 (here);
        #       reading one          -> 2 * atan2(...)  (in yaw_of).
        # Side effect: at θ = 360° the stored half is 180°, w = cos(180°) = -1,
        # so a full turn lands on MINUS identity -> q and -q are the SAME
        # rotation. Every sign-flip line in this file exists because of this.
        # Median yaw of the window, rebuilt as a rotation about world Y.
        half = np.median(yaws[first : i + 1]) / 2.0
        twist = np.array([0.0, np.sin(half), 0.0, np.cos(half)])
        target_r[i] = quaternion_multiply(twist, rest)

    return target_p, target_r


# =========================================================================
# 5. THE FILTER  (one full replay; the part that becomes GDScript later)
# =========================================================================

def run_filter(targets, amount, dead_zone_m, prior_p, prior_r, prior_amount,
               slow_amount):
    """One full replay of the stabilizer over every detection
    """

    # Unpack the targets:
    #   target_p[i] = target position at frame i
    #   target_r[i] = target rotation at frame i
    target_p, target_r = targets

    #  the first detection.
    position = target_p[0]
    rotation = target_r[0]

    # Output arrays for filtered positions and rotations.
    out_p = []
    out_r = []

    # Process each detection one-by-one.
    for i in range(len(target_p)):

        # ---------------------------------------------------------
        # 1. Smoothing amount
        # ---------------------------------------------------------
        #
        # amount = how much of the remaining distance we move per detection.
        # It is CONSTANT for the whole replay (frame-based smoothing): main()
        # computes it once per setting from the average detection gap, so no
        # per-frame timestamps are needed here.

        # ---------------------------------------------------------
        # 2. POSITION FILTERING (dead zone + easing)
        # ---------------------------------------------------------
        #
        # Compute how far the target position is from the current filtered position.
        #
        pos_error = np.linalg.norm(target_p[i] - position)

        # If the error is larger than the dead zone → move toward target.
        # If inside dead zone → HOLD (do nothing).
        #
        if pos_error > dead_zone_m:
            # Move a fraction "amount" toward the target.
            position = position + (target_p[i] - position) * amount

        # ---------------------------------------------------------
        # 3. ROTATION FILTERING (easing)
        # ---------------------------------------------------------
        #
        rotation = blend_rotation(rotation, target_r[i], amount)

        # ---------------------------------------------------------
        # 3b. MEAN-REVERTING PULL (position + rotation)
        # ---------------------------------------------------------
        #
        # Every detection, drift gently back toward the anchor 
        position = position + (prior_p - position) * prior_amount
        rotation = blend_rotation(rotation, prior_r, prior_amount)

        # ---------------------------------------------------------
        # 3c. PHYSICS LOCK + SELF-HEALING ANCHOR
        # ---------------------------------------------------------
        #
        # A resting mannequin cannot tilt out of the floor plane: delete that
        # part of the estimate outright (its own yaw is kept - see
        # flatten_to_yaw). Position keeps ALL THREE axes free: no floor pin,
        # so a real height change (compressions, a lift) still gets through.
        rotation = flatten_to_yaw(rotation, prior_r)

        # The anchor heals: it follows the estimate as a very slow EMA, so a
        # genuinely moved mannequin is accepted in minutes.
        #
        # NOTE what this does and does not heal. It heals toward `rotation`,
        # which was just flat-locked, so its tilt IS prior_r's tilt - meaning
        # only the YAW of the anchor moves here. The TILT reference stays
        # frozen at the first-second average for the whole replay (measured:
        # it moves 0.00 deg). That is deliberate, not an oversight: healing the
        # tilt toward the raw detection instead makes things clearly worse
        # (walk_final 0.130 -> 0.182), because raw tilt is the very noise the
        # flat lock exists to delete. The rig does heal it, but slowly on
        # purpose - see rest_heal_time_s in navel_provider.gd.
        prior_p = prior_p + (position - prior_p) * slow_amount
        prior_r = blend_rotation(prior_r, rotation, slow_amount)

        # ---------------------------------------------------------
        # 4. Save filtered pose for this frame
        # ---------------------------------------------------------
        out_p.append(position)
        out_r.append(rotation)

    # Return filtered positions and rotations as numpy arrays.
    return np.array(out_p), np.array(out_r)


# =========================================================================
# 6. THE TEST BENCH  (try all 64 settings, print the ten best + the winner)
# =========================================================================

def main():
    # Load the recording: positions, rotations, and average time between detections.
    name = "data/today/headmotion_1785761051.csv"
    positions, rotations, avg_gap = load_poses(Path(name))

    # Baseline error (unfiltered)
    raw = measure_errors(positions, rotations)

    # avg_gap = typical time per detection (seconds)
    # smooth is in seconds → convert to per-frame smoothing amount:
    #     amount = fraction of remaining distance covered per detection
    #     frames_to_settle = how many frames smoothing needs to stabilize

    # The anchor: settled once from the first second, shared by every setting.
    prior_p, prior_r = settle_prior(positions, rotations, avg_gap)
    prior_amount = 1 - np.exp(-avg_gap / PRIOR_TIME_S)
    slow_amount = 1 - np.exp(-avg_gap / SLOW_TIME_S)

    # THE TILT GATE (sanity check): a lying mannequin cannot tilt far out of the
    # floor plane, so a detection claiming impossible tilt is a lie - position
    # included. Rejecting it here keeps it out of the targets, the pulls AND the
    # healing anchor's education.
    tilt = np.array([angle_deg(q, flatten_to_yaw(q, prior_r)) for q in rotations])
    keep = tilt <= GATE_TILT_DEG
    print(f"tilt gate: rejected {int((~keep).sum())} of {len(keep)} detections")
    positions, rotations = positions[keep], rotations[keep]

    results = []

    # Try each window size
    for window in WINDOWS:

        # Precomputed targets for this window (median position, median yaw)
        targets = window_targets(positions, rotations, window, prior_r)

        # Try all combinations of dead zones + smoothing times
        for dead_m, smooth in product(POSITION_DEAD_ZONES_M, SMOOTHING_TIMES_S):

            # Constant smoothing amount for this setting
            amount = 1 - np.exp(-avg_gap / smooth)

            # Run stabilizer with this parameter set
            filtered_p, filtered_r = run_filter(
                targets, amount, dead_m, prior_p, prior_r, prior_amount, slow_amount
            )

            # --------------------------------------------------
            # SKIP LOGIC (clean version)
            #
            # Skip:
            #   • window frames (the median vote needs this many frames)
            #   • frames_to_settle (smoothing needs this many frames)
            #
            # After skip, the filter output is stable enough to score.
            # --------------------------------------------------
            frames_to_settle = int(smooth / avg_gap)
            skip = window + frames_to_settle

            # If skip exceeds total frames, nothing left to evaluate
            if skip >= len(positions):
                continue

            # Measure filtered error after skip
            errors = measure_errors(
                filtered_p[skip:], filtered_r[skip:]
            )

            # Score = share of unfiltered error left (0 = perfect)
            score = float(np.mean([
                after / before for after, before in zip(errors, raw)
            ]))

            results.append((score, window, dead_m, smooth, errors))

    # Sort by score (best first)
    results.sort(key=lambda r: r[0])

    # Print top 10 settings
    print(f"\n{'score':>6} {'window':>7} {'pos mm':>7} {'smooth s':>9}")
    for score, window, dead_m, smooth, _ in results[:10]:
        print(f"{score:6.3f} {window:7d} {dead_m * 1000:7.1f} {smooth:9.2f}")

    # Best setting
    score, window, dead_m, smooth, errors = results[0]
    print(f"\nBest setting (window {window}, dead zone {dead_m * 1000:.0f} mm, "
          f"smoothing {smooth:.2f} s):")

    names = ["position wobble", "position jump  ", "position drift ",
             "rotation wobble", "rotation jump  ", "rotation drift "]
    units = ["mm", "mm", "mm", "deg", "deg", "deg"]

    # Print before → after and % removed
    for label, unit, before, after in zip(names, units, raw, errors):
        percent_removed = (1 - after / before) * 100
        print(f"  {label} {before:7.2f} -> {after:5.2f} {unit:<4}"
              f"({percent_removed:3.0f}% removed)")


if __name__ == "__main__":
    main()
