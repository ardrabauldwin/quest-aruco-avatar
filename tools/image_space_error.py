"""Marker position error vs. where the marker sat in the image, and vs. range.

The CSV's marker columns are the detector's output: the marker pose in the HEAD
reference frame (lens pose already applied in C++). camera_* is the head transform
sampled at capture time. So world = cam_R @ p_cam + cam_p, and the image position
comes straight from p_cam.
"""
import csv, sys, math
import numpy as np

# Full-resolution intrinsics as used in project/main_3d.gd (before the 0.5 downscale).
FX, FY, CX, CY = 877.06583568, 878.33004836, 645.36226952, 642.24557861
MARKERS = ["common", "chest", "navel"]

def quat_to_mat(x, y, z, w):
    n = math.sqrt(x*x + y*y + z*z + w*w)
    if n == 0: return np.eye(3)
    x, y, z, w = x/n, y/n, z/n, w/n
    return np.array([
        [1-2*(y*y+z*z), 2*(x*y-z*w),   2*(x*z+y*w)],
        [2*(x*y+z*w),   1-2*(x*x+z*z), 2*(y*z-x*w)],
        [2*(x*z-y*w),   2*(y*z+x*w),   1-2*(x*x+y*y)],
    ])

def load(path):
    rows = []
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            try:
                cam_p = np.array([float(r["camera_x"]), float(r["camera_y"]), float(r["camera_z"])])
                cam_R = quat_to_mat(float(r["camera_qx"]), float(r["camera_qy"]),
                                    float(r["camera_qz"]), float(r["camera_qw"]))
            except (ValueError, KeyError):
                continue
            e = {"phase": r["phase_label"], "cam_p": cam_p, "cam_R": cam_R}
            for m in MARKERS:
                try:
                    e[m] = np.array([float(r[m+"_x"]), float(r[m+"_y"]), float(r[m+"_z"])])
                except (ValueError, KeyError):
                    e[m] = None
            rows.append(e)
    return rows

def image_coords(p_cam):
    """Pixel position of the marker, full resolution. p_cam is head-relative (Godot: -Z forward)."""
    X, Y, Z = p_cam[0], -p_cam[1], -p_cam[2]     # -> OpenCV frame (matches the C++ sign flips)
    if Z <= 1e-6:
        return None, None, None
    return FX * X / Z + CX, FY * Y / Z + CY, float(np.linalg.norm(p_cam))

def analyse(path):
    rows = load(path)
    print(f"\n=== {path}  ({len(rows)} rows) ===")
    for m in MARKERS:
        s = []
        for r in rows:
            if r[m] is None: continue
            u, v, rng = image_coords(r[m])
            if u is None: continue
            s.append((r["phase"], r["cam_R"] @ r[m] + r["cam_p"], u, v, rng, r["cam_p"]))
        if len(s) < 50:
            print(f"  {m:7s}: only {len(s)} samples, skipped"); continue
        front = [x for x in s if x[0] == "front"]
        if len(front) < 20:
            print(f"  {m:7s}: no front reference, skipped"); continue
        ref = np.median(np.array([x[1] for x in front]), axis=0)

        rad, err, along, perp, rngs, phs = [], [], [], [], [], []
        for phase, p, u, v, rng, cam_p in s:
            e = p - ref
            ray = p - cam_p
            n = np.linalg.norm(ray)
            if n < 1e-6: continue
            ray = ray / n
            a = float(e @ ray)
            rad.append(math.hypot(u - CX, v - CY)); err.append(float(np.linalg.norm(e)))
            along.append(abs(a)); perp.append(float(np.linalg.norm(e - a * ray)))
            rngs.append(rng); phs.append(phase)
        rad, err, along, perp, rngs = map(np.array, (rad, err, along, perp, rngs))

        def corr(a, b):
            if a.std() < 1e-9 or b.std() < 1e-9: return float("nan")
            return float(np.corrcoef(a, b)[0, 1])

        print(f"  {m:7s}  n={len(err):5d}  image-radius {rad.min():5.0f}-{rad.max():5.0f}px  "
              f"range {rngs.min():.2f}-{rngs.max():.2f}m")
        print(f"           |err| median {np.median(err)*100:5.2f}cm   depth(along-ray) "
              f"{np.median(along)*100:5.2f}cm   lateral {np.median(perp)*100:5.2f}cm")
        print(f"           corr(|err|,image-radius) = {corr(err, rad):+.3f}   "
              f"corr(|err|,range) = {corr(err, rngs):+.3f}")
        edges = np.percentile(rad, [0, 25, 50, 75, 100])
        print("             radius bin           n   median|err|   depth  lateral")
        for i in range(4):
            lo, hi = edges[i], edges[i+1]
            sel = (rad >= lo) & ((rad <= hi) if i == 3 else (rad < hi))
            if sel.sum() < 10: continue
            print(f"             {lo:5.0f}-{hi:5.0f}px  {sel.sum():5d}   "
                  f"{np.median(err[sel])*100:8.2f}cm {np.median(along[sel])*100:7.2f} {np.median(perp[sel])*100:7.2f}")
        # per-phase, for comparison with the README's displacement table
        print("             per phase:", end=" ")
        for ph in ["front", "left", "right", "far_front", "far_left", "far_right", "front_return"]:
            sel = np.array([p == ph for p in phs])
            if sel.sum() < 10: continue
            print(f"{ph}={np.median(err[sel])*100:.1f}cm(r={np.median(rad[sel]):.0f}px)", end="  ")
        print()

for p in sys.argv[1:]:
    analyse(p)
