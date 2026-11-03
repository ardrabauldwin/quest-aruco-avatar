"""Line up QCPR manikin compressions with the presses the Quest app counted.

Inputs:
  compressions  <stem>_compressions.csv from tools/qcpr_probe.py (unix_ms = PC clock)
  logcat        `adb logcat -v epoch` capture of the headset during the same session
  --offset-ms   headset clock minus PC clock (tools/qcpr_quest_compare.py --measure-offset)

A compression's time is its deepest point on the live depth curve (0027) from
<stem>_raw.csv, moved to the PC clock with the least-delayed sample. The 0028
message describing it arrives 0.4-0.6 s later, when the next compression begins,
so its arrival time must not be used. Each compression is paired with the nearest
unused Quest "CPR press" within --window-ms. Output: <out>.csv, one row per
compression or unmatched Quest press, in time order.

  python tools/qcpr_quest_compare.py --measure-offset
  python tools/qcpr_quest_compare.py run_compressions.csv quest_logcat.txt --offset-ms 37 --out compare
"""
import argparse
import csv
import re
import subprocess
import time

PRESS = re.compile(r"^\s*(\d+\.\d+)\s.*CPR press #(\d+)\s+travel=([\d.]+) cm\s+(\S+)\s+interval=([\d.]+) s\s+hand=(\w+)")


def measure_offset(samples: int = 7) -> int:
    """Headset clock minus PC clock in ms, from the adb round trip with the least delay."""
    best = None
    for _ in range(samples):
        before = time.time()
        out = subprocess.run(["adb", "shell", "date", "+%s.%N"], capture_output=True, text=True, check=True).stdout
        after = time.time()
        quest = float(out.strip())
        trip = after - before
        if best is None or trip < best[0]:
            best = (trip, quest - (before + after) / 2)
    return round(best[1] * 1000)


def quest_presses(path: str, offset_ms: int) -> list:
    presses = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = PRESS.match(line)
            if m:
                presses.append({"pc_ms": round(float(m[1]) * 1000) - offset_ms, "number": int(m[2]),
                                "travel_cm": float(m[3]), "quality": m[4], "interval_s": float(m[5]), "hand": m[6]})
    return presses


def clock(ms: int) -> str:
    return time.strftime("%H:%M:%S", time.localtime(ms / 1000)) + f".{ms % 1000:03d}"


def manikin_compressions(raw_path: str) -> list:
    """(pc_ms of the deepest point, depth mm, rate/min) per compression, from <stem>_raw.csv."""
    raw = list(csv.DictReader(open(raw_path, encoding="utf-8")))
    wave = [(int(r["unix_ms"]), bytes.fromhex(r["raw_hex"])) for r in raw if r["characteristic"] == "0027"]
    samples = [(pc, int.from_bytes(b[:4], "little"), b[4]) for pc, b in wave]
    # The manikin clock runs ~0.7 % slow and BLE delays samples by up to ~250 ms: fit PC time as a
    # line through the least-delayed sample of each 2 s window (the lower envelope).
    windows = {}
    for pc, mt, _ in samples:
        windows.setdefault(mt // 2000, []).append((pc - mt, mt))
    lows = [min(v) for v in windows.values()]
    n = len(lows)
    mean_m = sum(m for _, m in lows) / n
    mean_d = sum(d for d, _ in lows) / n
    var = sum((m - mean_m) ** 2 for _, m in lows)
    slope = sum((m - mean_m) * (d - mean_d) for d, m in lows) / var if var else 0.0
    to_pc = lambda mt: round(mt + mean_d + slope * (mt - mean_m))
    peaks = [(mt, d) for i, (_, mt, d) in enumerate(samples[1:-1], 1)
             if d >= samples[i - 1][2] and d > samples[i + 1][2]]
    result = []
    for r in raw:
        if r["characteristic"] != "0028":
            continue
        b = bytes.fromhex(r["raw_hex"])
        end, depth, rate = int.from_bytes(b[:4], "little"), b[6], b[9]
        bottom = max((p for p in peaks if p[0] <= end and p[1] == depth), default=None, key=lambda p: p[0])
        result.append((to_pc(bottom[0] if bottom else end), depth, rate))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("compressions", nargs="?")
    parser.add_argument("logcat", nargs="?")
    parser.add_argument("--offset-ms", type=int, default=0)
    parser.add_argument("--window-ms", type=int, default=300)
    parser.add_argument("--out", default="qcpr_quest_compare")
    parser.add_argument("--measure-offset", action="store_true")
    args = parser.parse_args()
    if args.measure_offset:
        print(measure_offset())
        return

    manikin = manikin_compressions(args.compressions.replace("_compressions.csv", "_raw.csv"))
    presses = quest_presses(args.logcat, args.offset_ms)
    used = set()
    rows = []
    for number, (t, depth, rate) in enumerate(manikin, 1):
        candidates = [(abs(p["pc_ms"] - t), i) for i, p in enumerate(presses) if i not in used]
        gap, index = min(candidates, default=(None, None))
        press = presses[index] if gap is not None and gap <= args.window_ms else None
        if press:
            used.add(index)
        quest_mm = round(press["travel_cm"] * 10) if press else ""
        quest_rate = round(60 / press["interval_s"]) if press and press["interval_s"] > 0 else ""
        rows.append((t, [clock(t), number, depth, quest_mm, quest_mm - depth if press else "", rate, quest_rate,
                         quest_rate - rate if quest_rate != "" else "",
                         press["number"] if press else "", press["quality"] if press else "",
                         (press["pc_ms"] - t) if press else ""]))
    for i, p in enumerate(presses):
        if i not in used:
            rows.append((p["pc_ms"], [clock(p["pc_ms"]), "", "", round(p["travel_cm"] * 10), "", "",
                                      round(60 / p["interval_s"]) if p["interval_s"] > 0 else "", "",
                                      p["number"], p["quality"], "quest only"]))
    rows = [r for _, r in sorted(rows, key=lambda r: r[0])]
    with open(f"{args.out}.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time", "manikin_number", "manikin_depth_mm", "quest_depth_mm", "depth_diff_mm",
                    "manikin_rate_bpm", "quest_rate_bpm", "rate_diff_bpm",
                    "quest_press", "quest_quality", "quest_minus_manikin_ms"])
        w.writerows(rows)
    matched = sum(1 for r in rows if r[1] != "" and r[8] != "")
    print(f"manikin compressions {len(manikin)}, quest presses {len(presses)}, matched {matched}, "
          f"missed by quest {len(manikin) - matched}, quest only {len(presses) - matched} -> {args.out}.csv")


if __name__ == "__main__":
    main()
