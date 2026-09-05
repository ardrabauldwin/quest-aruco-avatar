"""Read a stationary recording directly from the Quest and replay the active pose filter."""

import argparse
import csv
import io
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from aruco_pose import average_poses, combine, read_pose
from filter_errors import angle_deg
from tune_filter import medoid_targets, robust_pose, startup_rest, stabilize


MARKERS = ("common", "chest", "navel")


def adb_bytes(adb, package, *args):
    return subprocess.check_output([adb, "exec-out", "run-as", package, *args])


def matrix_to_quaternion(matrix):
    # Stable branch form, returned as Godot/Python xyzw.
    m = matrix
    trace = float(np.trace(m))
    if trace > 0.0:
        s = np.sqrt(trace + 1.0) * 2.0
        q = np.array([(m[2, 1] - m[1, 2]) / s,
                      (m[0, 2] - m[2, 0]) / s,
                      (m[1, 0] - m[0, 1]) / s, 0.25 * s])
    else:
        i = int(np.argmax(np.diag(m)))
        if i == 0:
            s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2.0
            q = np.array([0.25 * s, (m[0, 1] + m[1, 0]) / s,
                          (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s])
        elif i == 1:
            s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2.0
            q = np.array([(m[0, 1] + m[1, 0]) / s, 0.25 * s,
                          (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s])
        else:
            s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2.0
            q = np.array([(m[0, 2] + m[2, 0]) / s,
                          (m[1, 2] + m[2, 1]) / s, 0.25 * s,
                          (m[1, 0] - m[0, 1]) / s])
    return q / np.linalg.norm(q)


def parse_offsets(text):
    offsets = {}
    for index, marker in enumerate(MARKERS):
        match = re.search(rf"aruco_patch{index}=Transform3D\(([^)]*)\)", text)
        if not match:
            raise ValueError(f"Calibration has no offset for marker {index}")
        values = np.array([float(value.strip()) for value in match.group(1).split(",")])
        # Godot serializes Basis as its three column vectors.
        matrix = values[:9].reshape(3, 3).T
        offsets[marker] = (values[9:12], matrix_to_quaternion(matrix))
    return offsets


def fuse_row(row, offsets):
    camera = read_pose(row, "camera")
    estimates = []
    for marker in MARKERS:
        if not row.get(f"{marker}_x"):
            continue
        estimates.append(combine(combine(camera, read_pose(row, marker)), offsets[marker]))
    if not estimates:
        return None
    if len(estimates) == 1:
        return estimates[0]
    if len(estimates) == 2:
        return average_poses(estimates[0], estimates[1])
    return robust_pose(np.array([p for p, _ in estimates]),
                       np.array([q for _, q in estimates]))


def metrics(positions, rotations):
    centre_p, centre_q = robust_pose(positions, rotations)
    steps_p = np.linalg.norm(np.diff(positions, axis=0), axis=1) * 1000.0
    steps_r = np.array([angle_deg(a, b) for a, b in zip(rotations[:-1], rotations[1:])])
    drift_p = np.linalg.norm(positions - centre_p, axis=1) * 1000.0
    drift_r = np.array([angle_deg(q, centre_q) for q in rotations])
    return (np.median(steps_p), np.percentile(steps_p, 95), np.percentile(drift_p, 95),
            np.median(steps_r), np.percentile(steps_r, 95), np.percentile(drift_r, 95))


def rest_trace(target_p, target_q, rest_index, initial_rest, count, pos_limit, rot_limit,
               pos_dead=0.006, rot_dead=0.5, min_position_mm=0.0, min_rotation_deg=0.0):
    rest_p, rest_q = initial_rest[0].copy(), initial_rest[1].copy()
    recent = []
    position_events = []
    rotation_events = []
    for i in range(rest_index + 1, len(target_p)):
        recent.append(i)
        recent = recent[-count:]
        if len(recent) < count:
            continue
        position_stable = all(np.linalg.norm(target_p[j] - target_p[i]) <= pos_limit
                              for j in recent)
        rotation_stable = all(angle_deg(target_q[j], target_q[i]) <= rot_limit
                              for j in recent)
        if (position_stable and np.linalg.norm(target_p[i] - rest_p)
                > max(pos_dead, min_position_mm / 1000.0)):
            position_events.append(np.linalg.norm(target_p[i] - rest_p) * 1000.0)
            rest_p = target_p[i].copy()
        if (rotation_stable and angle_deg(target_q[i], rest_q)
                > max(rot_dead, min_rotation_deg)):
            rotation_events.append(angle_deg(target_q[i], rest_q))
            rest_q = target_q[i].copy()
    return rest_p, rest_q, position_events, rotation_events


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_name")
    parser.add_argument("--adb", required=True)
    parser.add_argument("--package", default="de.unigreifswald.opencvaruco")
    args = parser.parse_args()

    csv_text = adb_bytes(args.adb, args.package, "cat", f"files/{args.csv_name}").decode()
    cfg_text = adb_bytes(args.adb, args.package, "cat", "files/navel_calibration.cfg").decode()
    rows = list(csv.DictReader(io.StringIO(csv_text)))
    poses = [fuse_row(row, parse_offsets(cfg_text)) for row in rows]
    kept = [(row, pose) for row, pose in zip(rows, poses) if pose is not None]
    rows = [row for row, _ in kept]
    positions = np.array([pose[0] for _, pose in kept])
    rotations = np.array([pose[1] for _, pose in kept])
    times = np.array([float(row["logger_ms"]) / 1000.0 for row in rows])
    gaps = np.r_[np.median(np.diff(times)), np.diff(times)]

    rest_index, rest = startup_rest(positions, rotations)
    print(f"poses={len(positions)} duration_s={times[-1]-times[0]:.3f} "
          f"median_detection_gap_s={np.median(np.diff(times)):.3f}")
    print(f"startup_rest_detection={rest_index + 1} startup_rest_time_s={times[rest_index]-times[0]:.3f}")

    raw = metrics(positions, rotations)
    print("raw_fused step_med_mm={:.3f} step_p95_mm={:.3f} drift_p95_mm={:.3f} "
          "rot_step_med_deg={:.3f} rot_step_p95_deg={:.3f} rot_drift_p95_deg={:.3f}".format(*raw))

    for radius in (0.10, 0.20, 0.2864789, 0.40, 0.75):
        targets = medoid_targets(positions, rotations, gaps, 7, radius)
        output = stabilize((positions, rotations), targets, gaps, 0.006, 0.5, 0.8,
                           rest_index, rest, 8.0, 0.3, 0.002, 0.5, 7)
        target_values = metrics(targets[0], targets[1])
        output_values = metrics(output[0][rest_index:], output[1][rest_index:])
        final_p, final_q, pos_events, rot_events = rest_trace(
            targets[0], targets[1], rest_index, rest, 7, 0.002, 0.5)
        rest_dp = np.linalg.norm(final_p - rest[0]) * 1000.0
        rest_dr = angle_deg(final_q, rest[1])
        print("radius={:.7g} target_step_p95_mm={:.3f} target_rot_p95_deg={:.3f} "
              "display_step_p95_mm={:.3f} display_drift_p95_mm={:.3f} "
              "display_rot_step_p95_deg={:.3f} display_rot_drift_p95_deg={:.3f} "
              "rest_pos_events={} rest_rot_events={} rest_net_mm={:.3f} rest_net_deg={:.3f}".format(
                  radius, target_values[1], target_values[4], output_values[1], output_values[2],
                  output_values[4], output_values[5], len(pos_events), len(rot_events), rest_dp, rest_dr))

    targets = medoid_targets(positions, rotations, gaps, 7, 0.2864789)
    post = slice(rest_index + 1, None)
    target_rest_mm = np.linalg.norm(targets[0][post] - rest[0], axis=1) * 1000.0
    target_rest_deg = np.array([angle_deg(q, rest[1]) for q in targets[1][post]])
    print("stationary_target_from_rest pos_p95_mm={:.3f} pos_p99_mm={:.3f} pos_max_mm={:.3f} "
          "rot_p95_deg={:.3f} rot_p99_deg={:.3f} rot_max_deg={:.3f}".format(
              np.percentile(target_rest_mm, 95), np.percentile(target_rest_mm, 99),
              np.max(target_rest_mm), np.percentile(target_rest_deg, 95),
              np.percentile(target_rest_deg, 99), np.max(target_rest_deg)))
    fixed_output = stabilize((positions, rotations), targets, gaps, 0.006, 0.5, 0.8,
                             rest_index, rest, 8.0, 0.3, 0.002, 0.5,
                             len(positions) + 1)
    fixed_values = metrics(fixed_output[0][rest_index:], fixed_output[1][rest_index:])
    current_output = stabilize((positions, rotations), targets, gaps, 0.006, 0.5, 0.8,
                               rest_index, rest, 8.0, 0.3, 0.002, 0.5, 7)
    current_values = metrics(current_output[0][rest_index:], current_output[1][rest_index:])
    print("reanchor_ab mode,step_p95_mm,drift_p95_mm,rot_step_p95_deg,rot_drift_p95_deg")
    print("fixed,{:.3f},{:.3f},{:.3f},{:.3f}".format(
        fixed_values[1], fixed_values[2], fixed_values[4], fixed_values[5]))
    print("current,{:.3f},{:.3f},{:.3f},{:.3f}".format(
        current_values[1], current_values[2], current_values[4], current_values[5]))
    print("endpoint_grid count,pos_mm,rot_deg,pos_events,rot_events,rest_net_mm,rest_net_deg")
    for count in (5, 7, 10, 14):
        for pos_mm in (1.0, 2.0, 3.0):
            for rot_deg in (0.25, 0.5, 0.75):
                final_p, final_q, pe, revents = rest_trace(
                    targets[0], targets[1], rest_index, rest, count, pos_mm / 1000.0, rot_deg)
                print(f"{count},{pos_mm:.2f},{rot_deg:.2f},{len(pe)},{len(revents)},"
                      f"{np.linalg.norm(final_p-rest[0])*1000:.3f},{angle_deg(final_q,rest[1]):.3f}")

    print("relocation_threshold_grid min_position_mm,min_rotation_deg,false_pos_events,false_rot_events")
    for min_position_mm in (0.0, 10.0, 15.0, 20.0, 25.0, 30.0, 40.0):
        for min_rotation_deg in (0.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0):
            _, _, pe, revents = rest_trace(
                targets[0], targets[1], rest_index, rest, 7, 0.002, 0.5,
                min_position_mm=min_position_mm, min_rotation_deg=min_rotation_deg)
            print(f"{min_position_mm:.1f},{min_rotation_deg:.1f},{len(pe)},{len(revents)}")


if __name__ == "__main__":
    main()
