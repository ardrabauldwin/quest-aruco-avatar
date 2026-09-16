"""Summarise an avatar_trace CSV (per rendered frame). Per phase: frame rate, detection cadence,
and the avatar's shake split by head state. Shake = distance from a 1 s rolling median of the
avatar position, so slow drift is removed and only movement faster than ~1 Hz remains.
usage: python tools/trace_summary.py recordings/avatar_trace_*.csv"""
import csv, sys, numpy as np
def rolling_median(A, t, win=1.0):
    out = np.empty_like(A)
    for i in range(len(A)):
        m = (t >= t[i]-win/2) & (t <= t[i]+win/2)
        out[i] = np.median(A[m], axis=0)
    return out
def main(path):
    rows = list(csv.DictReader(open(path, newline="")))
    rows = [r for r in rows if r["avatar_visible"] == "1"]
    if not rows: print(path, ": avatar never visible"); return
    t = np.array([float(r["recording_ms"]) for r in rows]) / 1000
    A = np.array([[float(r["avatar_x"]), float(r["avatar_y"]), float(r["avatar_z"])] for r in rows])
    yaw = np.array([float(r["avatar_yaw_deg"]) for r in rows])
    fps = np.array([float(r["fps"]) for r in rows]); dt = np.array([float(r["delta_ms"]) for r in rows])
    spd = np.array([float(r["head_speed_mps"]) for r in rows]); trn = np.array([float(r["head_turn_dps"]) for r in rows])
    age = np.array([float(r["result_age_ms"]) for r in rows]); ph = np.array([r["phase_label"] for r in rows])
    shake = np.linalg.norm(A - rolling_median(A, t), axis=1) * 100
    yshake = np.abs(yaw - rolling_median(yaw[:, None], t)[:, 0])
    step = np.r_[0, np.linalg.norm(np.diff(A, axis=0), axis=1)] * 100
    still = (spd < 0.15) & (trn < 20); fast = (spd > 0.4) | (trn > 60)
    print(path)
    print(f"{'phase':22s}{'frames':>7s}{'fps med/p5':>12s}{'dt>20ms%':>9s}{'det gap ms':>11s}{'still: shake p90 cm':>21s}{'yaw p90':>8s}{'fast head: shake p90':>21s}{'step p99 cm':>12s}")
    for p in dict.fromkeys(ph):
        m = ph == p
        if m.sum() < 30: continue
        gaps = np.diff(t[m][np.r_[True, np.diff(age[m]) < 0]]) * 1000 if (np.diff(age[m]) < 0).sum() > 2 else np.array([np.nan])
        s_st = np.percentile(shake[m & still], 90) if (m & still).sum() > 20 else np.nan
        y_st = np.percentile(yshake[m & still], 90) if (m & still).sum() > 20 else np.nan
        s_fa = np.percentile(shake[m & fast], 90) if (m & fast).sum() > 20 else np.nan
        print(f"{p:22s}{m.sum():7d}{np.median(fps[m]):7.0f}/{np.percentile(fps[m],5):4.0f}{100*(dt[m]>20).mean():8.0f}%{np.nanmedian(gaps):11.0f}{s_st:21.2f}{y_st:8.2f}{s_fa:21.2f}{np.percentile(step[m],99):12.2f}")
    print("still = head speed < 0.15 m/s and turn < 20 deg/s; fast = > 0.4 m/s or > 60 deg/s. det gap = time between new detections.")
if __name__ == "__main__":
    for p in sys.argv[1:]: main(p)
