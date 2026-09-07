"""One authoritative search for every active avatar-filter parameter.

Run:
    python tune_filter.py CALIBRATION.csv STATIONARY.csv MOVING.csv --distance-mm 100

The labelled moving recording is mandatory because stationary data alone always rewards stronger
smoothing and prior pull. The script first searches startup-rest convergence, then performs two
coordinate-grid passes over medoid radius/window, dead zones/smoothing, prior, endpoint stability and
tracking timeout. This tests every listed value without an impractical full Cartesian sweep.

The replay follows the active Quest order: partial-marker fusion, tracking-loss history reset,
combined medoid, dead zones, render-rate smoothing, startup rest, prior pull and stable-endpoint
re-anchoring.
It writes the winner to tune_filter_best.txt and every evaluated display configuration to
tune_filter_results.csv.

Three numbers each for position and rotation:

    WOBBLE  movement between detections on an ordinary frame (median)
    JUMP    movement on a bad frame (p95) - this is what reads as glitching
    DRIFT   distance from its own centre - slow wander the two step measures miss

The score gives equal top-level weight to stationary stability and moving performance. Moving
performance combines amplitude retention, normalized delay, endpoint error and return error.
"""

import argparse
import csv
from dataclasses import dataclass
from itertools import product
from pathlib import Path

import numpy as np

from aruco_pose import MARKERS, combine, marker_seen, quaternion_multiply, read_pose
from filter_errors import angle_deg, measure_errors
from simple_aruco_analysis import learn_offsets, load_csv

WINDOWS = [1, 3, 5, 7]
# Dead zone is a pair in the rig, metres and degrees, so it is swept as a pair. 20 mm / 0.3 deg is
# what the rig ran before this script was pointed at it; kept as the evidence for dropping it.
DEAD_ZONES = [(0.000, 0.00), (0.001, 0.25), (0.002, 0.50), (0.003, 1.00), (0.005, 1.50),
              (0.006, 0.50), (0.020, 0.30)]
# Not swept, and not searchable here. With the markers stationary every measure keeps improving
# as smoothing rises, so a search over it has no minimum and would always answer "smooth forever",
# which means freeze the avatar. It is a responsiveness choice - the avatar covers 95% of a real
# move in about three of these - so it is an input. Pass a different one as a third argument.
SMOOTHING_TIMES_S = [0.10, 0.25, 0.50, 0.80, 1.20]
PRIOR_TIMES_S = [2.0, 4.0, 8.0, 16.0, 30.0]
TRACKING_TIMEOUTS_S = [0.30, 0.20, 0.40, 0.50]
ENDPOINT_STABLE_COUNTS = [3, 5, 7, 10]
# A stable-looking cluster can still be stationary measurement bias. These two values require the
# candidate endpoint to be meaningfully separated from remembered rest before rest is re-anchored.
# Zero preserves the earlier behaviour and remains in the grid as a control.
REANCHOR_MIN_POSITION_MM = [0.0, 10.0, 15.0, 20.0, 25.0, 30.0, 40.0]
REANCHOR_MIN_ROTATION_DEG = [0.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

# Radius converts angular disagreement into equivalent point displacement inside the 6-DoF
# medoid. It is NOT avatar size or a dead zone. The exact old 15 mm / 3 degree balance is included
# as 0.2864789 m, but the experiment now searches rather than assuming it is best.
MEDOID_RADII_M = [0.10, 0.15, 0.20, 0.25, 0.2864789, 0.30, 0.40, 0.50, 0.75]

# The rig smooths every rendered frame but gets a new target only per detection, so each gap is
# walked in render-sized substeps. Matters once a dead zone is nonzero: a render-rate filter stops
# the moment its remaining error falls inside the zone.
RENDER_HZ = 72.0
TRACKING_LOSS_TIMEOUT_S = 0.300
# Landing margins: when the target corroborates rest but the display has not settled onto it
# (right after a re-anchor), the display closes onto rest at smoothing speed to within these.
LANDING_POSITION_M = 0.001
LANDING_ROTATION_DEG = 0.1
RUNTIME_PRIOR_TIME_S = 8.0
REST_INITIAL_DETECTIONS = 20
REST_CHECKPOINT_STEP = 5
REST_REQUIRED_STABLE_CHECKS = 3
REST_MAX_DETECTIONS = 50
REST_STABLE_POSITION_M = 0.002
REST_STABLE_ROTATION_DEG = 0.5

# Startup-rest grid. This is now part of this file; tune_rest_convergence.py is legacy.
INITIAL_DETECTION_COUNTS = [10, 15, 20, 25, 30, 40]
CHECKPOINT_STEPS = [3, 5, 8, 10]
POSITION_THRESHOLDS_MM = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]
ROTATION_THRESHOLDS_DEG = [0.10, 0.25, 0.50, 0.75, 1.00, 1.50]
STABLE_CHECK_COUNTS = [2, 3, 4]
FALLBACK_COUNTS = [40, 50, 60, 75, 100]
REST_TRIAL_STEP = 5

BEST_PATH = Path("tune_filter_best.txt")
RESULTS_PATH = Path("tune_filter_results.csv")


def slerp(a, b, amount):
    if np.dot(a, b) < 0.0:
        b = -b
    dot = float(np.clip(np.dot(a, b), -1.0, 1.0))
    if dot > 0.9995:  # Nearly identical: the great-circle formula divides by ~0, lerp does not.
        result = a + (b - a) * amount
    else:
        theta = np.arccos(dot)
        result = (a * np.sin((1 - amount) * theta) + b * np.sin(amount * theta)) / np.sin(theta)
    return result / np.linalg.norm(result)


def medoid_targets(positions, rotations, gaps_s, window, medoid_radius_m,
                   tracking_timeout_s=TRACKING_LOSS_TIMEOUT_S):
    """What the filter aims at: the most central of the last `window` detections.

    Position and rotation together, as the rig does it. Depends on the window alone, so it is
    computed once and reused for every dead zone and smoothing time.
    """
    target_positions = np.empty_like(positions)
    target_rotations = np.empty_like(rotations)

    history = []
    reacquiring = np.zeros(len(positions), dtype=bool)
    waiting_for_full_window = False
    for i in range(len(positions)):
        if i > 0 and gaps_s[i] > tracking_timeout_s:
            history.clear()
            waiting_for_full_window = window > 1
        history.append(i)
        history = history[-window:]

        if waiting_for_full_window and len(history) < window:
            reacquiring[i] = True
            target_positions[i] = target_positions[i - 1]
            target_rotations[i] = target_rotations[i - 1]
            continue

        waiting_for_full_window = False
        if len(history) < window:  # Startup: the rig takes the newest detection.
            target_positions[i], target_rotations[i] = positions[i], rotations[i]
            continue

        near_positions = positions[history]
        near_rotations = rotations[history]
        position_distance_m = np.linalg.norm(
            near_positions[:, None, :] - near_positions[None, :, :], axis=2
        )
        rotation_distance_rad = 2.0 * np.arccos(
            np.clip(np.abs(near_rotations @ near_rotations.T), 0.0, 1.0)
        )
        distance = position_distance_m + medoid_radius_m * rotation_distance_rad
        best = int(np.argmin(distance.sum(axis=1)))
        target_positions[i], target_rotations[i] = near_positions[best], near_rotations[best]

    return target_positions, target_rotations, reacquiring


def _rotation_log(base, rotation):
    """Rotation from base to rotation as an axis-angle vector in base's tangent space."""
    relative = quaternion_multiply(
        np.array([-base[0], -base[1], -base[2], base[3]]), rotation
    )
    if relative[3] < 0.0:
        relative = -relative
    w = float(np.clip(relative[3], -1.0, 1.0))
    half_sin = np.sqrt(max(1.0 - w * w, 0.0))
    if half_sin < 1e-9:
        return np.zeros(3)
    return relative[:3] / half_sin * (2.0 * np.arccos(w))


def _rotation_exp(vector):
    """Axis-angle vector back to a quaternion."""
    angle = float(np.linalg.norm(vector))
    if angle < 1e-12:
        return np.array([0.0, 0.0, 0.0, 1.0])
    axis = vector / angle
    return np.concatenate([axis * np.sin(angle / 2.0), [np.cos(angle / 2.0)]])


def robust_pose(positions, rotations):
    """Runtime rest robust pose: coordinate median plus tangent-space rotation median.

    The medoid is the base so every relative rotation is small; the per-axis median then runs in
    the flat tangent space, matching navel_provider._rotation_tangent_median exactly.
    """
    position = np.median(positions, axis=0)
    rotations = np.asarray(rotations, dtype=float)
    distance = 2.0 * np.arccos(np.clip(np.abs(rotations @ rotations.T), 0.0, 1.0))
    base = rotations[int(np.argmin(distance.sum(axis=1)))]
    vectors = np.array([_rotation_log(base, rotation) for rotation in rotations])
    rotation = quaternion_multiply(base, _rotation_exp(np.median(vectors, axis=0)))
    return position, rotation


def startup_rest(positions, rotations, rest_config=None):
    """Replay CommonPoseProvider's current checkpoint and exact-fallback rule."""
    config = rest_config or {
        "initial": REST_INITIAL_DETECTIONS,
        "step": REST_CHECKPOINT_STEP,
        "checks": REST_REQUIRED_STABLE_CHECKS,
        "fallback": REST_MAX_DETECTIONS,
        "position_mm": REST_STABLE_POSITION_M * 1000.0,
        "rotation_deg": REST_STABLE_ROTATION_DEG,
    }
    previous = None
    stable_checks = 0
    next_checkpoint = config["initial"]
    for count in range(1, min(len(positions), config["fallback"]) + 1):
        at_checkpoint = count >= next_checkpoint
        at_fallback = count >= config["fallback"]
        if not at_checkpoint and not at_fallback:
            continue
        estimate = robust_pose(positions[:count], rotations[:count])
        if at_checkpoint:
            if previous is not None:
                position_change = np.linalg.norm(estimate[0] - previous[0])
                rotation_change = angle_deg(estimate[1], previous[1])
                stable = (position_change * 1000.0 <= config["position_mm"]
                          and rotation_change <= config["rotation_deg"])
                stable_checks = stable_checks + 1 if stable else 0
            previous = estimate
            next_checkpoint += config["step"]
        if stable_checks >= config["checks"] or at_fallback:
            return count - 1, estimate
    raise ValueError(f"Need at least {config['fallback']} detected poses for rest replay.")


def stabilize(raw_poses, targets, gaps_s, dead_zone_m, dead_zone_deg, smoothing_time_s,
              rest_index, initial_rest, prior_time_s=RUNTIME_PRIOR_TIME_S,
              tracking_timeout_s=TRACKING_LOSS_TIMEOUT_S,
              endpoint_stable_position_m=0.002,
              endpoint_stable_rotation_deg=0.5,
              endpoint_stable_detections=7,
              reanchor_min_position_m=0.0,
              reanchor_min_rotation_deg=0.0):
    """Replay the active Quest order at render rate, sampled at each detection."""
    raw_positions, raw_rotations = raw_poses
    target_positions, target_rotations, reacquiring = targets
    output_positions = np.empty_like(target_positions)
    output_rotations = np.empty_like(target_rotations)
    position, rotation = target_positions[0].copy(), target_rotations[0].copy()
    rest_position, rest_rotation = initial_rest[0].copy(), initial_rest[1].copy()
    rest_active = False
    endpoint_targets = []

    def render_step(target_p, target_r, delta_s):
        nonlocal position, rotation, rest_position, rest_rotation
        smooth = (1.0 if smoothing_time_s <= 0.0
                  else 1.0 - np.exp(-delta_s / smoothing_time_s))
        if np.linalg.norm(target_p - position) > dead_zone_m:
            position = position + (target_p - position) * smooth
        if angle_deg(rotation, target_r) > dead_zone_deg:
            rotation = slerp(rotation, target_r, smooth)

        # Landing: matches SimplePoseStabilizer._landing_position/_landing_rotation.
        if rest_active:
            if (np.linalg.norm(target_p - rest_position) <= dead_zone_m
                    and np.linalg.norm(position - rest_position) > LANDING_POSITION_M):
                position = position + (rest_position - position) * smooth
            if (angle_deg(target_r, rest_rotation) <= dead_zone_deg
                    and angle_deg(rotation, rest_rotation) > LANDING_ROTATION_DEG):
                rotation = slerp(rotation, rest_rotation, smooth)

        if rest_active and prior_time_s > 0.0:
            pull = 1.0 - np.exp(-delta_s / prior_time_s)
            position = position + (rest_position - position) * pull
            rotation = slerp(rotation, rest_rotation, pull)

    for i in range(len(target_positions)):
        if reacquiring[i]:
            endpoint_targets.clear()
        position_reanchor_ready = rotation_reanchor_ready = False
        if rest_active and not reacquiring[i]:
            target_p, target_r = target_positions[i], target_rotations[i]
            endpoint_targets.append((target_p.copy(), target_r.copy()))
            endpoint_targets = endpoint_targets[-endpoint_stable_detections:]
            if len(endpoint_targets) == endpoint_stable_detections:
                position_is_stable = all(
                    np.linalg.norm(p - target_p) <= endpoint_stable_position_m
                    for p, _ in endpoint_targets)
                rotation_is_stable = all(
                    angle_deg(r, target_r) <= endpoint_stable_rotation_deg
                    for _, r in endpoint_targets)
                position_reanchor_ready = (position_is_stable and
                    np.linalg.norm(target_p - rest_position)
                    > max(dead_zone_m, reanchor_min_position_m))
                rotation_reanchor_ready = (rotation_is_stable and
                    angle_deg(target_r, rest_rotation)
                    > max(dead_zone_deg, reanchor_min_rotation_deg))

        if i > 0:
            # Before detection i arrives, Quest can only move toward detection i-1. The old replay
            # incorrectly used the future target throughout this gap and understated movement lag.
            usable_gap = min(gaps_s[i], tracking_timeout_s)
            substeps = max(int(round(usable_gap * RENDER_HZ)), 1)
            delta_s = usable_gap / substeps
            for _ in range(max(substeps - 1, 0)):
                render_step(target_positions[i - 1], target_rotations[i - 1], delta_s)

        if i == rest_index:
            rest_position, rest_rotation = initial_rest[0].copy(), initial_rest[1].copy()
            position, rotation = rest_position.copy(), rest_rotation.copy()
            rest_active = True
        elif i > 0 and not reacquiring[i]:
            delta_s = usable_gap / substeps
            render_step(target_positions[i], target_rotations[i], delta_s)

        output_positions[i], output_rotations[i] = position, rotation

        # Match Quest: update the display first, then adopt any confirmed stable endpoint.
        if position_reanchor_ready:
            rest_position = target_positions[i].copy()
        if rotation_reanchor_ready:
            rest_rotation = target_rotations[i].copy()

    return output_positions, output_rotations


def fuse_common(row, offsets):
    """Runtime marker availability and fusion, returned in world space."""
    camera = read_pose(row, "camera")
    estimates = []
    for marker in MARKERS:
        if not marker_seen(row, marker):
            continue
        marker_world = combine(camera, read_pose(row, marker))
        estimates.append(marker_world if marker == "common"
                         else combine(marker_world, offsets[marker]))
    if not estimates:
        return None
    if len(estimates) == 1:
        return estimates[0]
    # Runtime parity: navel_provider._fuse takes the sign-aligned mean for every marker count.
    positions = np.array([pose[0] for pose in estimates])
    rotations = np.array([pose[1] for pose in estimates])
    aligned = np.where((rotations @ rotations[0])[:, None] < 0.0, -rotations, rotations)
    summed = aligned.sum(axis=0)
    return positions.mean(axis=0), summed / np.linalg.norm(summed)


def row_time_s(row):
    """Seconds for this row from the logger's clock; None if the cell is empty."""
    value = row.get("logger_ms", "")
    return float(value) / 1000 if value else None


@dataclass(frozen=True)
class Recording:
    positions: np.ndarray
    rotations: np.ndarray
    gaps_s: np.ndarray
    median_gap_s: float
    times_s: np.ndarray
    labels: tuple


def load_recording(calibration_path, test_path):
    """Load every result containing at least one calibrated marker."""
    # learn_offsets skips rows that cannot teach an offset, so the recording goes in unfiltered.
    offsets = learn_offsets(load_csv(calibration_path))
    rows_and_poses = []
    for row in load_csv(test_path):
        pose = fuse_common(row, offsets)
        if pose is not None:
            rows_and_poses.append((row, pose))
    rows = [item[0] for item in rows_and_poses]
    if len(rows) < 10:
        raise SystemExit("Need at least 10 complete rows to replay.")

    poses = [item[1] for item in rows_and_poses]
    positions = np.array([pose[0] for pose in poses], dtype=float)
    rotations = np.array([pose[1] for pose in poses], dtype=float)
    if not np.all(np.isfinite(positions)) or not np.all(np.isfinite(rotations)):
        raise SystemExit("Recording contains NaN or infinite poses.")

    times = [row_time_s(row) for row in rows]
    gaps = [0.0]
    for previous, current in zip(times, times[1:]):
        gap = current - previous if previous is not None and current is not None else 0.0
        gaps.append(max(gap, 0.0))
    # A missing or backwards timestamp makes the smoothing amount meaningless; the median gap is
    # the honest stand-in for "one detection later".
    median_gap = float(np.median([gap for gap in gaps if gap > 0] or [0.08]))
    gaps = np.array([gap if gap > 0 else median_gap for gap in gaps], dtype=float)

    numeric_times = []
    elapsed = 0.0
    for index, value in enumerate(times):
        if index == 0:
            elapsed = value if value is not None else 0.0
        else:
            elapsed += gaps[index]
        numeric_times.append(elapsed)
    labels = tuple(row.get("phase_label", "") for row in rows)
    return Recording(positions, rotations, gaps, median_gap,
                     np.asarray(numeric_times, dtype=float), labels)


def load_poses(calibration_path, test_path):
    """Backward-compatible four-value loader used by older local checks."""
    recording = load_recording(calibration_path, test_path)
    return (recording.positions, recording.rotations,
            recording.gaps_s, recording.median_gap_s)


@dataclass(frozen=True)
class DisplayConfig:
    window: int = 7
    radius_m: float = 0.2864789
    dead_m: float = 0.006
    dead_deg: float = 0.5
    smoothing_s: float = 0.8
    prior_s: float = 8.0
    timeout_s: float = 0.3
    endpoint_stable: int = 7
    reanchor_min_position_mm: float = 20.0
    reanchor_min_rotation_deg: float = 6.0


def contiguous_segments(recording):
    segments = []
    for index, label in enumerate(recording.labels):
        if not segments or segments[-1][0] != label:
            segments.append([label, index, index + 1])
        else:
            segments[-1][2] = index + 1
    return segments


def rest_replay(positions, rotations, config, estimates):
    previous, stable = None, 0
    for count in range(config["initial"], min(len(positions), config["fallback"]) + 1):
        checkpoint = (count - config["initial"]) % config["step"] == 0
        fallback = count == config["fallback"]
        if not checkpoint and not fallback:
            continue
        estimate = estimates[count]
        if checkpoint:
            if previous is not None:
                dp = np.linalg.norm(estimate[0] - previous[0]) * 1000.0
                dr = angle_deg(estimate[1], previous[1])
                stable = stable + 1 if dp <= config["position_mm"] and dr <= config["rotation_deg"] else 0
            previous = estimate
        if stable >= config["checks"] or fallback:
            return estimate, stable >= config["checks"], count
    return None


def search_rest_parameters(recordings):
    length = max(FALLBACK_COUNTS)
    stationary_trials, moving_trials = [], []
    counts = set(FALLBACK_COUNTS)
    for initial, step in product(INITIAL_DETECTION_COUNTS, CHECKPOINT_STEPS):
        counts.update(range(initial, length + 1, step))

    for recording in recordings:
        for label, start, end in contiguous_segments(recording):
            positions, rotations = recording.positions[start:end], recording.rotations[start:end]
            if len(positions) < length:
                continue
            is_stationary = label.startswith("stationary")
            is_moving = label.startswith("moving")
            if not is_stationary and not is_moving:
                continue
            reference = robust_pose(positions, rotations) if is_stationary else None
            for offset in range(0, len(positions) - length + 1, REST_TRIAL_STEP):
                p, r = positions[offset:offset + length], rotations[offset:offset + length]
                estimates = {count: robust_pose(p[:count], r[:count]) for count in counts}
                trial = (p, r, estimates, reference)
                (stationary_trials if is_stationary else moving_trials).append(trial)

    if not stationary_trials:
        raise SystemExit("No stationary phase contains 100 detected poses for the rest grid.")

    ranked = []
    for initial, step, pos_mm, rot_deg, checks, fallback in product(
            INITIAL_DETECTION_COUNTS, CHECKPOINT_STEPS, POSITION_THRESHOLDS_MM,
            ROTATION_THRESHOLDS_DEG, STABLE_CHECK_COUNTS, FALLBACK_COUNTS):
        if initial + step * checks > fallback:
            continue
        config = {"initial": initial, "step": step, "position_mm": pos_mm,
                  "rotation_deg": rot_deg, "checks": checks, "fallback": fallback}
        stationary_outcomes = [rest_replay(p, r, config, e) for p, r, e, _ in stationary_trials]
        confirmed = np.mean([outcome[1] for outcome in stationary_outcomes])
        pos_errors = [np.linalg.norm(outcome[0][0] - trial[3][0]) * 1000.0
                      for outcome, trial in zip(stationary_outcomes, stationary_trials)]
        rot_errors = [angle_deg(outcome[0][1], trial[3][1])
                      for outcome, trial in zip(stationary_outcomes, stationary_trials)]
        false = [rest_replay(p, r, config, e)[1] for p, r, e, _ in moving_trials]
        false_rate = float(np.mean(false)) if false else 1.0
        valid = confirmed >= 0.95 and false_rate <= 0.05
        score = (0 if valid else 1, false_rate, np.percentile(pos_errors, 95),
                 np.percentile(rot_errors, 95), np.median([o[2] for o in stationary_outcomes]))
        ranked.append((score, config))
    ranked.sort(key=lambda item: item[0])
    if ranked[0][0][0] != 0:
        raise SystemExit("No rest grid cell met 95% stationary confirmation and 5% moving false acceptance.")
    return ranked[0][1], ranked[:15]


def replay_recording(recording, config, rest_config):
    rest_index, rest = startup_rest(recording.positions, recording.rotations, rest_config)
    targets = medoid_targets(recording.positions, recording.rotations, recording.gaps_s,
                             config.window, config.radius_m, config.timeout_s)
    output = stabilize((recording.positions, recording.rotations), targets, recording.gaps_s,
                       config.dead_m, config.dead_deg, config.smoothing_s, rest_index, rest,
                       prior_time_s=config.prior_s,
                       tracking_timeout_s=config.timeout_s,
                       endpoint_stable_position_m=rest_config["position_mm"] / 1000.0,
                       endpoint_stable_rotation_deg=rest_config["rotation_deg"],
                       endpoint_stable_detections=config.endpoint_stable,
                       reanchor_min_position_m=config.reanchor_min_position_mm / 1000.0,
                       reanchor_min_rotation_deg=config.reanchor_min_rotation_deg)
    return output, rest_index


def stationary_metrics(recording, output, rest_index, config):
    skip = rest_index + int(np.ceil(((config.window - 1) / 2 * recording.median_gap_s
                                     + 3 * config.smoothing_s) / recording.median_gap_s))
    filtered = measure_errors(output[0][skip:], output[1][skip:])
    raw = measure_errors(recording.positions[skip:], recording.rotations[skip:])
    indices = (1, 2, 4, 5)
    score = float(np.mean([filtered[i] / max(raw[i], 1e-12) for i in indices]))
    return score, filtered


def crossing_time(positions, times, origin, direction, distance_m):
    progress = ((positions - origin) @ direction) / max(distance_m, 1e-9)
    hits = np.flatnonzero(progress >= 0.90)
    return float(times[hits[0]]) if hits.size else float("inf")


def movement_metrics(recording, output, physical_distance_mm):
    segments = contiguous_segments(recording)
    if len(segments) < 5:
        raise ValueError("Moving recording needs stationary/moving/stationary/moving/stationary phases.")
    chosen = segments[:5]
    label_pattern = ["stationary", "moving", "stationary", "moving", "stationary"]
    if not all(item[0].startswith(prefix) for item, prefix in zip(chosen, label_pattern)):
        raise ValueError("Moving phase labels are not in the required five-phase order.")

    def centre(array, segment):
        start, end = segment[1], segment[2]
        start += (end - start) // 2
        return np.median(array[start:end], axis=0)

    raw_a = centre(recording.positions, chosen[0])
    raw_b = centre(recording.positions, chosen[2])
    out_a = centre(output[0], chosen[0])
    out_b = centre(output[0], chosen[2])
    out_return = centre(output[0], chosen[4])
    direction = raw_b - raw_a
    norm = np.linalg.norm(direction)
    if norm < 1e-6:
        raise ValueError("Moving recording has no measurable A-to-B direction.")
    direction /= norm
    distance_m = physical_distance_mm / 1000.0
    retained_out = float(np.dot(out_b - out_a, direction) / distance_m)
    retained_back = float(np.dot(out_return - out_b, -direction) / distance_m)
    retained = (retained_out + retained_back) / 2.0
    expected_b = raw_a + direction * distance_m
    endpoint_mm = float(np.linalg.norm(out_b - expected_b) * 1000.0)
    return_mm = float(np.linalg.norm(out_return - raw_a) * 1000.0)

    delays, durations = [], []
    for move_index, next_stationary, origin, axis in (
            (1, 2, raw_a, direction), (3, 4, raw_b, -direction)):
        start, end = chosen[move_index][1], chosen[next_stationary][2]
        raw_time = crossing_time(recording.positions[start:end], recording.times_s[start:end],
                                 origin, axis, distance_m)
        filtered_time = crossing_time(output[0][start:end], recording.times_s[start:end],
                                      origin, axis, distance_m)
        delays.append(max(0.0, filtered_time - raw_time) if np.isfinite(filtered_time) else 1e6)
        durations.append(recording.times_s[chosen[move_index][2] - 1]
                         - recording.times_s[chosen[move_index][1]])
    delay_s = float(np.mean(delays))
    duration_s = max(float(np.mean(durations)), 0.1)
    movement_score = float(np.mean([
        abs(retained - 1.0), delay_s / duration_s,
        endpoint_mm / physical_distance_mm, return_mm / physical_distance_mm,
    ]))
    return movement_score, retained, delay_s, endpoint_mm, return_mm


def evaluate_config(stationary, moving, distance_mm, rest_config, config):
    stationary_output, stationary_rest = replay_recording(stationary, config, rest_config)
    stationary_score, errors = stationary_metrics(stationary, stationary_output,
                                                  stationary_rest, config)
    moving_output, _ = replay_recording(moving, config, rest_config)
    movement = movement_metrics(moving, moving_output, distance_mm)
    total = (stationary_score + movement[0]) / 2.0
    return {"total_score": total, "stationary_score": stationary_score,
            "movement_score": movement[0], "retained": movement[1], "delay_s": movement[2],
            "endpoint_mm": movement[3], "return_mm": movement[4],
            "position_jump_mm": errors[1], "position_drift_mm": errors[2],
            "rotation_jump_deg": errors[4], "rotation_drift_deg": errors[5]}


def search_display_parameters(stationary, moving, distance_mm, rest_config):
    current = DisplayConfig()
    cache = {}

    def evaluate(config):
        if config not in cache:
            cache[config] = evaluate_config(stationary, moving, distance_mm, rest_config, config)
        return cache[config]

    # Coordinate-grid passes test every value while avoiding a 100,000-cell Cartesian explosion.
    # Repeat until a complete pass changes no parameter (a proven fixed point), capped at 5 passes.
    for pass_index in range(5):
        pass_start = current
        candidates = [DisplayConfig(**{**current.__dict__, "window": window, "radius_m": radius})
                      for window, radius in product(WINDOWS, MEDOID_RADII_M)]
        current = min(candidates, key=lambda config: evaluate(config)["total_score"])

        candidates = [DisplayConfig(**{**current.__dict__, "dead_m": dead_m,
                                       "dead_deg": dead_deg, "smoothing_s": smoothing})
                      for (dead_m, dead_deg), smoothing in product(DEAD_ZONES, SMOOTHING_TIMES_S)]
        current = min(candidates, key=lambda config: evaluate(config)["total_score"])

        candidates = [DisplayConfig(**{**current.__dict__, "prior_s": prior})
                      for prior in PRIOR_TIMES_S]
        current = min(candidates, key=lambda config: evaluate(config)["total_score"])

        candidates = [DisplayConfig(**{**current.__dict__, "endpoint_stable": stable})
                      for stable in ENDPOINT_STABLE_COUNTS]
        current = min(candidates, key=lambda config: evaluate(config)["total_score"])

        candidates = [DisplayConfig(**{**current.__dict__,
                                       "reanchor_min_position_mm": position_mm,
                                       "reanchor_min_rotation_deg": rotation_deg})
                      for position_mm, rotation_deg in product(
                          REANCHOR_MIN_POSITION_MM, REANCHOR_MIN_ROTATION_DEG)]
        current = min(candidates, key=lambda config: evaluate(config)["total_score"])

        candidates = [DisplayConfig(**{**current.__dict__, "timeout_s": timeout})
                      for timeout in TRACKING_TIMEOUTS_S]
        current = min(candidates, key=lambda config: evaluate(config)["total_score"])

        if current == pass_start:
            print(f"Display search converged: pass {pass_index + 1} changed nothing.")
            break
        print(f"Display search pass {pass_index + 1} changed parameters; continuing.")
    else:
        print("Display search hit the 5-pass cap without a no-change pass.")

    return current, evaluate(current), cache


def write_results(cache):
    fields = list(DisplayConfig.__dataclass_fields__) + list(next(iter(cache.values())).keys())
    with RESULTS_PATH.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for config, metrics in sorted(cache.items(), key=lambda item: item[1]["total_score"]):
            writer.writerow({**config.__dict__, **metrics})


def main():
    parser = argparse.ArgumentParser(description="One search for every active filter parameter.")
    parser.add_argument("calibration", type=Path)
    parser.add_argument("stationary", type=Path)
    parser.add_argument("moving", type=Path)
    parser.add_argument("--distance-mm", type=float, required=True,
                        help="Physically measured common-marker A-to-B displacement")
    args = parser.parse_args()
    if args.distance_mm <= 0:
        raise SystemExit("--distance-mm must be positive.")

    stationary = load_recording(args.calibration, args.stationary)
    moving = load_recording(args.calibration, args.moving)
    rest_config, rest_ranked = search_rest_parameters([stationary, moving])
    best, metrics, cache = search_display_parameters(
        stationary, moving, args.distance_mm, rest_config
    )
    write_results(cache)

    lines = [
        "UNIFIED FILTER SEARCH", "", "REST PARAMETERS",
        f"  initial_detections       {rest_config['initial']}",
        f"  checkpoint_step          {rest_config['step']}",
        f"  stable_position_mm       {rest_config['position_mm']}",
        f"  stable_rotation_deg      {rest_config['rotation_deg']}",
        f"  stable_checks            {rest_config['checks']}",
        f"  fallback_detections      {rest_config['fallback']}", "",
        "DISPLAY PARAMETERS",
        f"  medoid_window            {best.window}",
        f"  medoid_radius_m          {best.radius_m}",
        f"  position_dead_zone_mm    {best.dead_m * 1000:.1f}",
        f"  rotation_dead_zone_deg   {best.dead_deg}",
        f"  smoothing_time_s         {best.smoothing_s}",
        f"  prior_time_s             {best.prior_s}",
        f"  endpoint_stable_count    {best.endpoint_stable}",
        f"  reanchor_min_position_mm {best.reanchor_min_position_mm}",
        f"  reanchor_min_rotation_deg {best.reanchor_min_rotation_deg}",
        f"  tracking_timeout_ms      {best.timeout_s * 1000:.0f}", "",
        "VALIDATION METRICS",
        f"  total_score              {metrics['total_score']:.4f}",
        f"  stationary_score         {metrics['stationary_score']:.4f}",
        f"  movement_score           {metrics['movement_score']:.4f}",
        f"  movement_retained        {metrics['retained'] * 100:.1f}%",
        f"  movement_delay_s         {metrics['delay_s']:.3f}",
        f"  endpoint_error_mm        {metrics['endpoint_mm']:.2f}",
        f"  return_error_mm          {metrics['return_mm']:.2f}", "",
        "Score = mean(stationary normalized jump/drift, movement normalized amplitude/delay/endpoint/return).",
        "The grid is staged and repeated until a complete pass changes nothing (max 5 passes).",
        "Tracking-timeout evidence is weak unless a labelled hiding/loss recording is also analysed.",
    ]
    text = "\n".join(lines)
    print("\n" + text)
    BEST_PATH.write_text(text + "\n", encoding="utf-8")
    print(f"\nWritten to {BEST_PATH} and {RESULTS_PATH}")


if __name__ == "__main__":
    main()
