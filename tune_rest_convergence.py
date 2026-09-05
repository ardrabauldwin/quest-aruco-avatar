"""LEGACY: grid-search the runtime rest-pose convergence rule.

Use tune_filter.py for the authoritative combined rest and display-filter search.

The search can first rank stationary candidates from a stationary CSV. A later moving CSV adds
movement validation:

* stationary phases: the mannequin stays fixed while the headset changes viewpoint
* moving_left / moving_right phases: the mannequin deliberately moves during settling

Run after recording a current-layout `moving` experiment:

    python tune_rest_convergence.py recording.csv

The script searches the initial count, checkpoint interval, position/rotation stability limits,
consecutive stable checks, and fallback count. Stationary-only output is explicitly labelled as a
candidate; it becomes a validated recommendation only when usable stationary and moving segments
are both supplied.
"""

import argparse
from itertools import product
from pathlib import Path

import numpy as np

from basic_analyze_rotation import fused_pose
from filter_errors import angle_deg
from simple_aruco_analysis import learn_offsets, load_csv


INITIAL_DETECTION_COUNTS = [10, 15, 20, 25, 30, 40]
CHECKPOINT_STEPS = [3, 5, 8, 10]
POSITION_THRESHOLDS_MM = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]
ROTATION_THRESHOLDS_DEG = [0.10, 0.25, 0.50, 0.75, 1.00, 1.50]
STABLE_CHECK_COUNTS = [2, 3, 4]
FALLBACK_COUNTS = [40, 50, 60, 75, 100]
# Spacing between replay start points; this is not a runtime checkpoint parameter.
TRIAL_START_STEP = 5
GATE_POSITION_THRESHOLDS_MM = [8, 10, 12, 15, 20, 25, 30]
GATE_ROTATION_THRESHOLDS_DEG = [4, 5, 6, 7.5, 10, 12.5, 15]
ENABLE_POSITION_THRESHOLDS_MM = [2, 4, 6, 8, 10, 12, 15]
ENABLE_ROTATION_THRESHOLDS_DEG = [0.5, 1, 2, 3, 4, 5]
GATE_CONFIRMATION_COUNT = 2


def rotation_medoid(rotations):
    rotations = np.asarray(rotations)
    distances = 1.0 - np.abs(rotations @ rotations.T)
    return rotations[int(np.argmin(np.sum(distances, axis=1)))]


def robust_estimate(positions, rotations):
    return np.median(positions, axis=0), rotation_medoid(rotations)


def load_segments(path):
    rows = load_csv(path)
    offsets = learn_offsets(rows)
    labelled = []
    for row in rows:
        pose = fused_pose(row, offsets)
        if pose is not None:
            labelled.append((row.get("phase_label", ""), pose[0], pose[1]))

    segments = []
    for label, position, rotation in labelled:
        if not segments or segments[-1][0] != label:
            segments.append([label, [], []])
        segments[-1][1].append(position)
        segments[-1][2].append(rotation)
    return [
        (label, np.asarray(positions), np.asarray(rotations))
        for label, positions, rotations in segments
    ]


def replay(positions, rotations, initial, checkpoint_step, pos_mm, rot_deg,
           required_checks, fallback, estimates=None):
    previous = None
    stable = 0
    if len(positions) < initial:
        return None

    limit = min(len(positions), fallback)
    for count in range(initial, limit + 1):
        is_checkpoint = (count - initial) % checkpoint_step == 0
        if is_checkpoint:
            estimate = (
                estimates[count] if estimates is not None
                else robust_estimate(positions[:count], rotations[:count])
            )
            if previous is not None:
                dp_mm = np.linalg.norm(estimate[0] - previous[0]) * 1000.0
                dr_deg = angle_deg(estimate[1], previous[1])
                stable = stable + 1 if dp_mm <= pos_mm and dr_deg <= rot_deg else 0
            previous = estimate
            if stable >= required_checks:
                return estimate, True, count

        # Fallback is an exact sample budget even when it falls between two checkpoints.
        if count == fallback:
            estimate = (
                estimates[count] if estimates is not None
                else robust_estimate(positions[:count], rotations[:count])
            )
            return estimate, False, count

    return None


def required_estimate_counts():
    counts = set(FALLBACK_COUNTS)
    largest = max(FALLBACK_COUNTS)
    for initial, checkpoint_step in product(INITIAL_DETECTION_COUNTS, CHECKPOINT_STEPS):
        counts.update(range(initial, largest + 1, checkpoint_step))
    return sorted(counts)


def precompute_estimates(positions, rotations):
    """Robust estimates depend on sample count, not on any acceptance threshold."""
    return {
        count: robust_estimate(positions[:count], rotations[:count])
        for count in required_estimate_counts()
        if count <= len(positions)
    }


def stationary_trials(segments, length):
    trials = []
    for label, positions, rotations in segments:
        if label != "stationary" or len(positions) < length:
            continue
        reference = robust_estimate(positions, rotations)
        # Several start points prevent one fortunate prefix from deciding the grid.
        for start in range(0, len(positions) - length + 1, TRIAL_START_STEP):
            trials.append((positions[start:start + length], rotations[start:start + length], reference))
    return trials


def moving_trials(segments, length):
    trials = []
    for label, positions, rotations in segments:
        if not label.startswith("moving_") or len(positions) < length:
            continue
        for start in range(0, len(positions) - length + 1, TRIAL_START_STEP):
            trials.append((positions[start:start + length], rotations[start:start + length]))
    return trials


def pose_errors(positions, rotations, reference):
    pos_mm = np.linalg.norm(positions - reference[0], axis=1) * 1000.0
    rot_deg = np.array([angle_deg(rotation, reference[1]) for rotation in rotations])
    return pos_mm, rot_deg


def gate_evidence(segments):
    """Stationary errors and moving errors relative to the preceding stationary pose."""
    stationary_errors = []
    moving_errors = []
    preceding_stationary = None
    for label, positions, rotations in segments:
        if label == "stationary":
            preceding_stationary = robust_estimate(positions, rotations)
            stationary_errors.append(pose_errors(positions, rotations, preceding_stationary))
        elif label.startswith("moving_") and preceding_stationary is not None:
            moving_errors.append(pose_errors(positions, rotations, preceding_stationary))
    return stationary_errors, moving_errors


def movement_cycles(segments):
    """Find labelled stationary A -> move -> stationary B -> return -> stationary A cycles."""
    cycles = []
    for index in range(len(segments) - 4):
        labels = [segments[index + offset][0] for offset in range(5)]
        if not (
            labels[0] == "stationary"
            and labels[1].startswith("moving_")
            and labels[2] == "stationary"
            and labels[3].startswith("moving_")
            and labels[4] == "stationary"
            and labels[1] != labels[3]
        ):
            continue

        reference = robust_estimate(segments[index][1], segments[index][2])
        cycles.append([
            pose_errors(segments[index + offset][1], segments[index + offset][2], reference)
            for offset in range(5)
        ])
    return cycles


def apply_gate(active, pos_error, rot_error, disable_pos, disable_rot,
               enable_pos, enable_rot):
    """Replay the runtime's OR-to-disable and AND-to-enable hysteresis exactly."""
    if active:
        if pos_error >= disable_pos or rot_error >= disable_rot:
            return False
    elif pos_error <= enable_pos and rot_error <= enable_rot:
        return True
    return active


def apply_confirmed_gate(active, disable_run, enable_run, pos_error, rot_error,
                         disable_pos, disable_rot, enable_pos, enable_rot):
    """Gate step with consecutive evidence counters, matching the proposed Quest runtime."""
    if active:
        enable_run = 0
        if pos_error >= disable_pos or rot_error >= disable_rot:
            disable_run += 1
        else:
            disable_run = 0
        if disable_run >= GATE_CONFIRMATION_COUNT:
            active = False
            disable_run = 0
    else:
        disable_run = 0
        if pos_error <= enable_pos and rot_error <= enable_rot:
            enable_run += 1
        else:
            enable_run = 0
        if enable_run >= GATE_CONFIRMATION_COUNT:
            active = True
            enable_run = 0
    return active, disable_run, enable_run


def consecutive_stationary_rate(stationary_errors, pos_limit, rot_limit, count):
    """Share of stationary count-sample windows that could falsely disable the prior."""
    hits = 0
    windows = 0
    for pos_error, rot_error in stationary_errors:
        evidence = (pos_error >= pos_limit) | (rot_error >= rot_limit)
        if len(evidence) < count:
            continue
        run_sums = np.convolve(evidence.astype(int), np.ones(count, dtype=int), mode="valid")
        hits += np.count_nonzero(run_sums == count)
        windows += len(run_sums)
    return hits / windows if windows else float("inf")


def replay_gate_cycle(cycle, disable_pos, disable_rot, enable_pos, enable_rot):
    """Measure outbound disable, false activation at B, and activation after returning to A."""
    active = True
    disable_run = 0
    enable_run = 0
    outbound_delay = None
    false_enable_at_b = False

    # Initial stationary A establishes the reference; start the runtime gate active there.
    for sample_index, (pos_error, rot_error) in enumerate(zip(*cycle[1])):
        was_active = active
        active, disable_run, enable_run = apply_confirmed_gate(
            active, disable_run, enable_run, pos_error, rot_error,
            disable_pos, disable_rot, enable_pos, enable_rot
        )
        if was_active and not active:
            outbound_delay = sample_index + 1

    for pos_error, rot_error in zip(*cycle[2]):
        was_active = active
        active, disable_run, enable_run = apply_confirmed_gate(
            active, disable_run, enable_run, pos_error, rot_error,
            disable_pos, disable_rot, enable_pos, enable_rot
        )
        if not was_active and active:
            false_enable_at_b = True

    return_delay = None
    for sample_index, (pos_error, rot_error) in enumerate(zip(*cycle[3])):
        was_active = active
        active, disable_run, enable_run = apply_confirmed_gate(
            active, disable_run, enable_run, pos_error, rot_error,
            disable_pos, disable_rot, enable_pos, enable_rot
        )
        if not was_active and active:
            return_delay = sample_index + 1
        elif was_active and not active:
            return_delay = None

    return_segment_length = len(cycle[3][0])
    for sample_index, (pos_error, rot_error) in enumerate(zip(*cycle[4])):
        was_active = active
        active, disable_run, enable_run = apply_confirmed_gate(
            active, disable_run, enable_run, pos_error, rot_error,
            disable_pos, disable_rot, enable_pos, enable_rot
        )
        if not was_active and active:
            return_delay = return_segment_length + sample_index + 1
        # A later false disable cancels that success unless the gate re-enables again.
        elif was_active and not active:
            return_delay = None

    return outbound_delay, false_enable_at_b, return_delay if active else None


def print_hysteresis_grid(segments, stationary_errors):
    cycles = movement_cycles(segments)
    if not cycles:
        print(" No complete stationary A -> move -> stationary B -> return -> stationary A cycle;")
        print(" re-enable thresholds cannot yet be validated.")
        return

    false_stationary_cache = {
        (disable_pos, disable_rot): consecutive_stationary_rate(
            stationary_errors, disable_pos, disable_rot, GATE_CONFIRMATION_COUNT
        )
        for disable_pos, disable_rot in product(
            GATE_POSITION_THRESHOLDS_MM,
            GATE_ROTATION_THRESHOLDS_DEG,
        )
    }

    rows = []
    for disable_pos, disable_rot, enable_pos, enable_rot in product(
        GATE_POSITION_THRESHOLDS_MM,
        GATE_ROTATION_THRESHOLDS_DEG,
        ENABLE_POSITION_THRESHOLDS_MM,
        ENABLE_ROTATION_THRESHOLDS_DEG,
    ):
        # Preserve hysteresis: the re-enable boundary must be strictly inside the disable boundary.
        if enable_pos >= disable_pos or enable_rot >= disable_rot:
            continue

        false_stationary = false_stationary_cache[(disable_pos, disable_rot)]
        outcomes = [
            replay_gate_cycle(cycle, disable_pos, disable_rot, enable_pos, enable_rot)
            for cycle in cycles
        ]
        outbound_delays = [outcome[0] for outcome in outcomes if outcome[0] is not None]
        outbound_rate = len(outbound_delays) / len(outcomes)
        median_outbound_delay = (
            float(np.median(outbound_delays)) if outbound_delays else float("inf")
        )
        false_b_rate = np.mean([outcome[1] for outcome in outcomes])
        returned = [outcome[2] for outcome in outcomes if outcome[2] is not None]
        return_rate = len(returned) / len(outcomes)
        median_return_delay = float(np.median(returned)) if returned else float("inf")

        valid = (
            false_stationary <= 0.01
            and outbound_rate >= 0.95
            and false_b_rate == 0.0
            and return_rate >= 0.95
        )
        score = (
            0 if valid else 1,
            false_b_rate,
            -return_rate,
            median_outbound_delay + median_return_delay,
            false_stationary,
        )
        rows.append((score, disable_pos, disable_rot, enable_pos, enable_rot,
                     false_stationary, outbound_rate, false_b_rate,
                     return_rate, median_outbound_delay, median_return_delay))

    rows.sort(key=lambda row: row[0])
    print("\nTop complete adaptive-prior hysteresis settings")
    print(" valid disable(mm/deg) enable(mm/deg) false_stat move_off false_at_B return_on off_n on_n")
    for row in rows[:15]:
        (score, disable_pos, disable_rot, enable_pos, enable_rot, false_stationary,
         outbound_rate, false_b_rate, return_rate, off_delay, on_delay) = row
        off_text = "never" if not np.isfinite(off_delay) else f"{off_delay:.1f}"
        on_text = "never" if not np.isfinite(on_delay) else f"{on_delay:.1f}"
        print(f" {score[0] == 0!s:>5} {disable_pos:5.1f}/{disable_rot:<5.1f} "
              f"{enable_pos:5.1f}/{enable_rot:<5.1f} "
              f"{false_stationary:10.2%} "
              f"{outbound_rate:8.1%} {false_b_rate:10.1%} {return_rate:9.1%} "
              f"{off_text:>5} {on_text:>5}")

    best = rows[0]
    if best[0][0] != 0:
        print(" No full gate met: <=1% stationary false disable, >=95% movement disable,")
        print(" 0% false re-enable at B, and >=95% re-enable after returning to A.")
        return

    (_, disable_pos, disable_rot, enable_pos, enable_rot, false_stationary,
     outbound_rate, false_b_rate, return_rate, off_delay, on_delay) = best
    print(f"\nRecommended hysteresis: disable after {GATE_CONFIRMATION_COUNT} consecutive detections "
          f"at {disable_pos:g} mm OR {disable_rot:g} deg; re-enable after "
          f"{GATE_CONFIRMATION_COUNT} consecutive detections at "
          f"{enable_pos:g} mm AND {enable_rot:g} deg")
    print(f" false stationary {false_stationary:.2%}, movement disable {outbound_rate:.1%}, "
          f"false at B {false_b_rate:.1%}, return enable {return_rate:.1%}, "
          f"median delays off/on {off_delay:.1f}/{on_delay:.1f} detections")


def print_gate_grid(segments):
    stationary, moving = gate_evidence(segments)
    stationary_pos = np.concatenate([errors[0] for errors in stationary])
    stationary_rot = np.concatenate([errors[1] for errors in stationary])
    print("\nAdaptive-prior gate evidence")
    print(f" stationary position p95/p99: {np.percentile(stationary_pos, 95):.2f} / "
          f"{np.percentile(stationary_pos, 99):.2f} mm")
    print(f" stationary rotation p95/p99: {np.percentile(stationary_rot, 95):.2f} / "
          f"{np.percentile(stationary_rot, 99):.2f} deg")

    if not moving:
        print(" No moving_left/moving_right evidence: gate values cannot yet be validated.")
        return

    rows = []
    total_stationary = len(stationary_pos)
    for pos_limit, rot_limit in product(
        GATE_POSITION_THRESHOLDS_MM, GATE_ROTATION_THRESHOLDS_DEG
    ):
        false_samples = np.count_nonzero(
            (stationary_pos >= pos_limit) | (stationary_rot >= rot_limit)
        )
        false_rate = false_samples / total_stationary

        detected = 0
        delays = []
        for pos_error, rot_error in moving:
            hits = np.flatnonzero((pos_error >= pos_limit) | (rot_error >= rot_limit))
            if hits.size:
                detected += 1
                delays.append(int(hits[0]) + 1)
        detection_rate = detected / len(moving)
        median_delay = float(np.median(delays)) if delays else float("inf")

        # A valid gate almost never suspends on stationary evidence and detects nearly every
        # deliberate movement segment. Rank valid cells by delay, then false suspension.
        valid = false_rate <= 0.01 and detection_rate >= 0.95
        score = (0 if valid else 1, median_delay, false_rate, pos_limit, rot_limit)
        rows.append((score, pos_limit, rot_limit, false_rate, detection_rate, median_delay))

    rows.sort(key=lambda row: row[0])
    print("\nTop disable thresholds (one-detection preview only)")
    print(" valid posmm rotdeg false_stationary move_detect median_delay_n")
    for score, pos_limit, rot_limit, false_rate, detection_rate, delay in rows[:15]:
        delay_text = "never" if not np.isfinite(delay) else f"{delay:.1f}"
        print(f" {score[0] == 0!s:>5} {pos_limit:5.1f} {rot_limit:6.1f} "
              f"{false_rate:16.2%} {detection_rate:11.1%} {delay_text:>14}")

    best = rows[0]
    if best[0][0] != 0:
        print(" No gate met <=1% stationary false suspension and >=95% movement detection.")
        print_hysteresis_grid(segments, stationary)
        return
    _, pos_limit, rot_limit, false_rate, detection_rate, delay = best
    print(f"\nBest one-detection threshold preview: {pos_limit:g} mm OR {rot_limit:g} deg "
          f"(false stationary {false_rate:.2%}, movement detection {detection_rate:.1%}, "
          f"median delay {delay:.1f} detections)")

    print_hysteresis_grid(segments, stationary)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("recordings", nargs="+", type=Path)
    args = parser.parse_args()

    segments = []
    for path in args.recordings:
        segments.extend(load_segments(path))

    stationary = stationary_trials(segments, max(FALLBACK_COUNTS))
    moving = moving_trials(segments, max(FALLBACK_COUNTS))
    if not stationary:
        raise SystemExit("No stationary segment has enough detections for the grid.")
    has_moving_validation = bool(moving)

    # The expensive median/medoid estimates are identical across thousands of threshold cells.
    stationary = [
        (positions, rotations, reference, precompute_estimates(positions, rotations))
        for positions, rotations, reference in stationary
    ]
    moving = [
        (positions, rotations, precompute_estimates(positions, rotations))
        for positions, rotations in moving
    ]

    results = []
    for initial, checkpoint_step, pos_mm, rot_deg, checks, fallback in product(
        INITIAL_DETECTION_COUNTS,
        CHECKPOINT_STEPS,
        POSITION_THRESHOLDS_MM,
        ROTATION_THRESHOLDS_DEG,
        STABLE_CHECK_COUNTS,
        FALLBACK_COUNTS,
    ):
        if initial + checkpoint_step * checks > fallback:
            continue

        stationary_runs = []
        for positions, rotations, reference, estimates in stationary:
            result = replay(
                positions, rotations, initial, checkpoint_step,
                pos_mm, rot_deg, checks, fallback, estimates
            )
            if result is None:
                continue
            estimate, converged, accepted_at = result
            stationary_runs.append((
                converged,
                accepted_at,
                np.linalg.norm(estimate[0] - reference[0]) * 1000.0,
                angle_deg(estimate[1], reference[1]),
            ))

        false_accepts = 0
        usable_moving = 0
        for positions, rotations, estimates in moving:
            result = replay(
                positions, rotations, initial, checkpoint_step,
                pos_mm, rot_deg, checks, fallback, estimates
            )
            if result is not None:
                usable_moving += 1
                false_accepts += int(result[1])  # convergence while moving is a false accept

        confirm_rate = np.mean([run[0] for run in stationary_runs])
        false_rate = false_accepts / usable_moving if usable_moving else float("nan")
        pos_p95 = np.percentile([run[2] for run in stationary_runs], 95)
        rot_p95 = np.percentile([run[3] for run in stationary_runs], 95)
        median_count = np.median([run[1] for run in stationary_runs])

        # With moving evidence, enforce both validation constraints. Stationary-only mode ranks
        # candidates by confirmation, accepted-pose error and speed; it deliberately does not
        # claim that movement behaviour has been validated.
        valid = (
            confirm_rate >= 0.95
            and (not has_moving_validation or false_rate <= 0.05)
        )
        if has_moving_validation:
            score = (0 if valid else 1, false_rate, pos_p95, rot_p95, median_count)
        else:
            score = (0 if valid else 1, pos_p95, rot_p95, median_count, fallback)
        results.append((score, initial, checkpoint_step, pos_mm, rot_deg, checks, fallback,
                        confirm_rate, false_rate, pos_p95, rot_p95, median_count))

    results.sort(key=lambda row: row[0])
    mode = "validated" if has_moving_validation else "stationary candidate"
    print(f"\nTop rest-convergence settings ({mode} mode)")
    print(" valid init step posmm rotdeg checks fallback stat_ok false_move pos_p95 rot_p95 median_n")
    for row in results[:15]:
        (score, initial, checkpoint_step, pos_mm, rot_deg, checks, fallback,
         stat, false, pos95, rot95, count) = row
        false_text = f"{false:10.1%}" if has_moving_validation else f"{'n/a':>10}"
        print(f" {score[0] == 0!s:>5} {initial:4d} {checkpoint_step:4d} "
              f"{pos_mm:5.1f} {rot_deg:6.2f} {checks:6d} {fallback:8d} "
              f"{stat:7.1%} {false_text} {pos95:8.2f} "
              f"{rot95:8.2f} {count:8.1f}")

    best = results[0]
    if best[0][0] != 0:
        requirement = (
            ">=95% stationary confirmation and <=5% moving false acceptance"
            if has_moving_validation else ">=95% stationary confirmation"
        )
        raise SystemExit(f"\nNo grid cell met {requirement}.")
    _, initial, checkpoint_step, pos_mm, rot_deg, checks, fallback, *_ = best
    label = "Recommended" if has_moving_validation else "Best stationary candidate"
    earliest = initial + checkpoint_step * checks
    print(f"\n{label}: initial {initial}, step {checkpoint_step}, {pos_mm:g} mm, "
          f"{rot_deg:g} deg, {checks} stable checks, fallback {fallback} detections")
    print(f" Earliest confirmation: {initial} + {checkpoint_step} x {checks} "
          f"= {earliest} detections")
    if not has_moving_validation:
        print("Movement has not been tested; validate this candidate later with a moving recording.")

if __name__ == "__main__":
    main()
