"""Summarise a replay CSV (tests/replay_recording.gd): per still phase, how much the AVATAR
wobbled while the viewer stood still (p90 of distance from the phase median, cm; yaw p90 deg),
how far it sat from its front position (drift, cm / deg), and how often it jumped."""
import csv, sys, numpy as np
STILL = ["front", "left", "right", "far_front", "far_left", "far_right", "front_return"]
def wrap(d): return (d + 180.0) % 360.0 - 180.0
def main(path):
    rows = list(csv.DictReader(open(path, newline="")))
    rows = [r for r in rows if r["ready"] == "1"]
    def P(rs, k): return np.array([[float(r[k+"_x"]), float(r[k+"_y"]), float(r[k+"_z"])] for r in rs])
    def Y(rs, k): return np.array([float(r[k+"_yaw"]) for r in rs])
    front = [r for r in rows if r["phase"] == "front"]
    if not front: print("no ready front rows"); return
    ref = np.median(P(front, "avatar"), axis=0); refy = np.median(Y(front, "avatar"))
    # jumps: consecutive avatar rows further apart than 1.5 cm
    A = P(rows, "avatar"); jumps = np.linalg.norm(np.diff(A, axis=0), axis=1) > 0.015
    print(path)
    print(f"{'phase':13s}{'n':>5s}{'avatar wobble p90 cm':>22s}{'yaw p90 deg':>13s}{'drift cm':>10s}{'drift deg':>11s}{'raw wobble cm':>15s}{'jumps':>7s}")
    for ph in STILL:
        rs = [r for r in rows if r["phase"] == ph]
        if len(rs) < 5: continue
        a = P(rs, "avatar"); ya = Y(rs, "avatar"); rw = P(rs, "raw")
        med = np.median(a, axis=0)
        wob = np.percentile(np.linalg.norm(a - med, axis=1), 90) * 100
        ywob = np.percentile(np.abs(wrap(ya - np.median(ya))), 90)
        rwob = np.percentile(np.linalg.norm(rw - np.median(rw, axis=0), axis=1), 90) * 100
        idx = [i for i, r in enumerate(rows) if r["phase"] == ph]
        nj = int(sum(jumps[i-1] for i in idx if i > 0))
        print(f"{ph:13s}{len(rs):5d}{wob:22.1f}{ywob:13.1f}{np.linalg.norm(med-ref)*100:10.1f}{wrap(np.median(ya)-refy):11.1f}{rwob:15.1f}{nj:7d}")
    print(f"total rows {len(rows)}, avatar jumps > 1.5 cm between rows: {int(jumps.sum())}, rejected flips: {rows[-1]['rejected_flips']}")
if __name__ == "__main__":
    for p in sys.argv[1:]: main(p)
