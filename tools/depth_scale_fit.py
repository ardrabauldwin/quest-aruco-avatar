"""If the drift is a pure depth-scale error, one scalar s applied to the detector's
camera-frame translation should collapse the marker's world position across all views.

pos_i(s) = cam_p_i + s * (cam_R_i @ p_cam_i).  Least-squares s, closed form.
s = fx_true/fx_used = marker_size_true/marker_size_used, so it also tells us which.
"""
import csv, sys, math
import numpy as np

MARKERS = ["common", "chest", "navel"]
FX_USED, SIZE_USED = 877.06583568, 0.10

def quat_to_mat(x, y, z, w):
    n = math.sqrt(x*x+y*y+z*z+w*w)
    if n == 0: return np.eye(3)
    x, y, z, w = x/n, y/n, z/n, w/n
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])

def spread(P):
    """90th-percentile distance from the median position, in cm."""
    med = np.median(P, axis=0)
    return float(np.percentile(np.linalg.norm(P - med, axis=1), 90)) * 100

def analyse(path):
    C, D = {m: [] for m in MARKERS}, {m: [] for m in MARKERS}
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            try:
                cam_p = np.array([float(r["camera_x"]), float(r["camera_y"]), float(r["camera_z"])])
                cam_R = quat_to_mat(float(r["camera_qx"]), float(r["camera_qy"]),
                                    float(r["camera_qz"]), float(r["camera_qw"]))
            except (ValueError, KeyError):
                continue
            for m in MARKERS:
                try:
                    p = np.array([float(r[m+"_x"]), float(r[m+"_y"]), float(r[m+"_z"])])
                except (ValueError, KeyError):
                    continue
                C[m].append(cam_p); D[m].append(cam_R @ p)
    print(f"\n=== {path} ===")
    for m in MARKERS:
        if len(C[m]) < 100:
            print(f"  {m:7s}: {len(C[m])} samples, skipped"); continue
        c, d = np.array(C[m]), np.array(D[m])
        A, B = c - c.mean(0), d - d.mean(0)
        s = -float((A*B).sum() / (B*B).sum())
        before, after = spread(c + d), spread(c + s*d)
        print(f"  {m:7s}  n={len(c):5d}   best scale s = {s:.4f}   "
              f"spread {before:5.2f}cm -> {after:5.2f}cm  ({100*(1-after/before):+.0f}%)")
        print(f"           implies fx {FX_USED:.1f} -> {FX_USED*s:.1f}  "
              f"OR marker size {SIZE_USED*100:.1f}cm -> {SIZE_USED*s*100:.2f}cm")

for p in sys.argv[1:]:
    analyse(p)
