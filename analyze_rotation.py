"""Measure false rotation around each world axis while the body is stationary.

Run:
    python analyze_rotation.py CALIBRATION.csv TEST.csv

The mannequin and markers never moved during the test, so every measured rotation change is noise.
The table splits that noise into world X, Y (up/yaw), and Z components and also reports the total
3D rotation error. The rig avoids all of it by holding the rotation captured during calibration and
re-measuring only after the body has demonstrably been moved.

Scored by repeatability: variation is error because the true rotation change is zero. This does not
measure absolute angular bias; that would require an independent known-angle reference.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from aruco_pose import (
    MARKERS,
    combine,
    marker_seen,
    pose_difference,
    read_pose,
)
from simple_aruco_analysis import learn_offsets, load_csv

FIGURE_PATH = Path(__file__).with_name("ritation.png")
ROTATION_RADIUS_MM = 500.0


def world_pose(row, marker):
    return combine(read_pose(row, "camera"), read_pose(row, marker))


def fuse(poses):
    position = np.mean([p[0] for p in poses], axis=0)
    first = poses[0][1]
    rotation = sum((q if first @ q > 0 else -q) for q in (p[1] for p in poses))
    return position, rotation / np.linalg.norm(rotation)


def today(row, offsets):
    views = []
    for marker in MARKERS:
        if not marker_seen(row, marker):
            continue
        offset = offsets.get(marker)
        views.append(world_pose(row, marker) if offset is None
                     else combine(world_pose(row, marker), offset))
    return fuse(views) if views else None


def quaternion_multiply(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])


def world_rotation_vector(quaternion, centre):
    """Signed XYZ rotation vector taking centre to quaternion, in world coordinates."""
    inverse_centre = centre * np.array([-1.0, -1.0, -1.0, 1.0])
    delta = quaternion_multiply(quaternion, inverse_centre)
    if delta[3] < 0:
        delta = -delta
    vector_norm = np.linalg.norm(delta[:3])
    if vector_norm < 1e-12:
        return np.zeros(3)
    angle = 2.0 * np.arctan2(vector_norm, np.clip(delta[3], -1.0, 1.0))
    return np.degrees(delta[:3] / vector_norm * angle)


def write_figure(rotation_axes, rotation_total, position_axes, position_total):
    """Write rotation and position repeatability charts alongside this script."""
    labels = ["World X", "World Y", "World Z", "Total 3D"]
    rotation_mm = np.radians(np.r_[rotation_axes, rotation_total]) * ROTATION_RADIUS_MM
    millimetres = np.r_[position_axes, position_total]
    colors = ["#e76f51", "#f4a261", "#2a9d8f", "#264653"]

    def font(size, bold=False):
        try:
            return ImageFont.truetype("arialbd.ttf" if bold else "arial.ttf", size)
        except OSError:
            return ImageFont.load_default(size=size)

    image = Image.new("RGB", (1980, 1510), "#ffffff")
    draw = ImageDraw.Draw(image)
    title_font, body_font = font(48, True), font(30)
    value_font, label_font = font(30, True), font(30, True)
    draw.text((990, 45), "Stationary-body pose error", font=title_font,
              fill="#17252a", anchor="ma")
    draw.text((990, 110), "Measured change when true position and rotation change = 0",
              font=body_font, fill="#555555", anchor="ma")

    def chart(values, top, bottom, heading, unit, chart_max):
        left, right = 190, 1860
        draw.line((left, top, left, bottom), fill="#777777", width=3)
        draw.line((left, bottom, right, bottom), fill="#777777", width=3)
        for tick in range(6):
            tick_value = chart_max * tick / 5
            y = bottom - (bottom - top) * tick / 5
            draw.line((left, y, right, y), fill="#dddddd", width=2)
            draw.text((left - 25, y), f"{tick_value:g}{unit}", font=body_font,
                      fill="#555555", anchor="rm")
        draw.text((left, top - 42), heading, font=body_font, fill="#333333", anchor="ls")
        slot = (right - left) / len(labels)
        for index, (label, value, color) in enumerate(zip(labels, values, colors)):
            cx = left + slot * (index + 0.5)
            bar_top = bottom - (bottom - top) * value / chart_max
            draw.rounded_rectangle((cx - 115, bar_top, cx + 115, bottom),
                                   radius=14, fill=color)
            draw.text((cx, bar_top - 22), f"{value:.2f}{unit}", font=value_font,
                      fill="#17252a", anchor="ms")
            draw.text((cx, bottom + 25), label, font=label_font, fill="#17252a", anchor="ma")

    shared_max = max(10.0, np.ceil(max(max(rotation_mm), max(millimetres)) / 10.0) * 10.0)
    chart(rotation_mm, 235, 735,
          f"Rotation-equivalent wander at {ROTATION_RADIUS_MM:.0f} mm radius", " mm",
          shared_max)
    chart(millimetres, 930, 1400, "Position wander (same scale)", " mm", shared_max)
    image.save(FIGURE_PATH, optimize=True)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Run: python analyze_rotation.py CALIBRATION.csv TEST.csv")

    # learn_offsets skips rows that cannot teach an offset, so the recording goes in unfiltered.
    offsets = learn_offsets(load_csv(Path(sys.argv[1])))
    rows = load_csv(Path(sys.argv[2]))
    phases, seen = [], set()
    for row in rows:
        if row["phase_label"] not in seen:
            seen.add(row["phase_label"])
            phases.append(row["phase_label"])

    print("\nMarkers never moved, so every value below is repeatability error.\n")
    print(f"Rotation is converted to equivalent movement at a {ROTATION_RADIUS_MM:.0f} mm radius.\n")
    print(f"  {'phase':<12}{'rows':>6}{'ROT X':>10}{'ROT Y':>10}{'ROT Z':>10}"
          f"{'ROT 3D':>10}{'POS X':>10}{'POS Y':>10}{'POS Z':>10}{'POS 3D':>10}")

    all_wander = None
    for phase in phases + ["ALL"]:
        subset = rows if phase == "ALL" else [r for r in rows if r["phase_label"] == phase]
        fused = [(r, today(r, offsets)) for r in subset]
        fused = [(r, p) for r, p in fused if p is not None]
        if len(fused) < 20:
            continue

        positions = np.array([p[0] for _, p in fused])
        rotations = [p[1] for _, p in fused]
        position_centre = np.median(positions, axis=0)
        position_components = np.abs(positions - position_centre) * 1000.0
        position_total = np.linalg.norm(positions - position_centre, axis=1) * 1000.0
        centre = rotations[int(np.argmin(
            np.sum(1 - np.abs(np.array(rotations) @ np.array(rotations).T), axis=1)))]
        components = np.abs(np.array([world_rotation_vector(q, centre) for q in rotations]))
        full = np.array([pose_difference((np.zeros(3), q), (np.zeros(3), centre))[1]
                         for q in rotations])

        cells = ""
        for values in (components[:, 0], components[:, 1], components[:, 2], full):
            equivalent_mm = np.radians(float(np.median(values))) * ROTATION_RADIUS_MM
            cells += f"{equivalent_mm:8.2f}mm"
        for values in (position_components[:, 0], position_components[:, 1],
                       position_components[:, 2], position_total):
            cells += f"{float(np.median(values)):8.2f}mm"
        print(f"  {phase:<12}{len(fused):6d}{cells}")
        if phase == "ALL":
            all_wander = (np.median(components, axis=0), float(np.median(full)),
                          np.median(position_components, axis=0),
                          float(np.median(position_total)))

    print("\n  Lower is better. These values measure wander, not absolute angular bias.")
    print("  The rig holds all three calibrated angles, so runtime rotation wander is 0.00")
    print("  by construction. TOTAL 3D is the noise that holding removes.")
    if all_wander is not None:
        write_figure(*all_wander)
        print(f"  Figure written to {FIGURE_PATH}")


if __name__ == "__main__":
    main()
