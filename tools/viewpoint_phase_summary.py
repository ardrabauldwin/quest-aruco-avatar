"""Per-phase summary of a viewpoint recording: where each marker lands in the WORLD frame
(camera pose x camera-frame marker pose, raw detector output, no fusion, no filtering) and how
its heading reads, phase by phase. Front is the reference: a marker that sits 5 cm further along
the viewing ray on the left than on the front is depth error; a heading that turns by 6 deg when
the viewer walks to the side is rotation error. The mannequin never moves during a recording.

usage: python tools/viewpoint_phase_summary.py recordings/aruco_viewpoint_*.csv
"""
import csv, sys, math
import numpy as np

MARKERS = ["common", "chest", "navel"]
STILL = {"front", "left", "right", "far_front", "far_left", "far_right", "front_return"}


def quat_to_mat(x, y, z, w):
    n = math.sqrt(x*x + y*y + z*z + w*w) or 1.0
    x, y, z, w = x/n, y/n, z/n, w/n
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


def heading_deg(R):
    """Yaw of the marker's x axis in the horizontal plane (Godot: y up, -z forward)."""
    ax = R[:, 0]
    return math.degrees(math.atan2(-ax[2], ax[0]))


def wrap(d):
    return (d + 180.0) % 360.0 - 180.0


def load(path):
    rows = {}
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            phase = r["phase_label"]
            if phase not in STILL:
                continue
            try:
                cp = np.array([float(r["camera_x"]), float(r["camera_y"]), float(r["camera_z"])])
                cR = quat_to_mat(*[float(r["camera_q" + k]) for k in "xyzw"])
            except ValueError:
                continue
            for m in MARKERS:
                try:
                    p = np.array([float(r[m + "_x"]), float(r[m + "_y"]), float(r[m + "_z"])])
                    R = quat_to_mat(*[float(r[m + "_q" + k]) for k in "xyzw"])
                except ValueError:
                    continue
                world_p = cp + cR @ p
                world_R = cR @ R
                ray = cR @ p
                rng = float(np.linalg.norm(ray))
                rows.setdefault((phase, m), []).append((world_p, heading_deg(world_R), rng, cp, ray / max(rng, 1e-9)))
    return rows


def main(path):
    rows = load(path)
    phases = [p for p in ["front", "left", "right", "far_front", "far_left", "far_right", "front_return"]
              if any(k[0] == p for k in rows)]
    print(f"{path}\n")
    for m in MARKERS:
        ref = rows.get(("front", m))
        if not ref:
            print(f"{m}: no front samples\n")
            continue
        ref_p = np.median(np.array([r[0] for r in ref]), axis=0)
        ref_h = float(np.median([r[1] for r in ref]))
        print(f"== {m}  (front median as reference, {len(ref)} samples)")
        print(f"{'phase':13s} {'n':>4s} {'range m':>8s} {'dx cm':>7s} {'dy cm':>7s} {'dz cm':>7s} {'|d| cm':>7s} {'along-ray cm':>13s} {'across cm':>10s} {'head deg':>9s} {'spread cm':>10s}")
        for ph in phases:
            rs = rows.get((ph, m))
            if not rs:
                print(f"{ph:13s} {0:4d}")
                continue
            P = np.array([r[0] for r in rs])
            med = np.median(P, axis=0)
            d = med - ref_p
            ray_dir = np.median(np.array([r[4] for r in rs]), axis=0)
            ray_dir /= max(np.linalg.norm(ray_dir), 1e-9)
            along = float(d @ ray_dir)
            across = float(np.linalg.norm(d - along * ray_dir))
            h = wrap(float(np.median([r[1] for r in rs])) - ref_h)
            rng = float(np.median([r[2] for r in rs]))
            spread = float(np.percentile(np.linalg.norm(P - med, axis=1), 90)) * 100
            print(f"{ph:13s} {len(rs):4d} {rng:8.2f} {d[0]*100:7.1f} {d[1]*100:7.1f} {d[2]*100:7.1f} {np.linalg.norm(d)*100:7.1f} {along*100:13.1f} {across*100:10.1f} {h:9.1f} {spread:10.1f}")
        print()
    print("along-ray: + means the marker is placed FURTHER from the viewer than on the front view (depth scale).")
    print("head deg: marker heading relative to the front view; the mannequin did not move, so this is error.")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
