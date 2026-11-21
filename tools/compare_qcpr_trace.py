"""Compare compression depth measured by the Quest hand tracking with the QCPR manikin.

Quest presses come from the headset trace (user://cpr_trace_*.csv, columns unix_ms,
count, travel_m) or from a logcat capture with epoch timestamps ("CPR press #n travel=x cm").
Manikin compressions come from tools/qcpr_probe.py (pc_unix_ms or unix_ms, depth_mm).

  python tools/compare_qcpr_trace.py --qcpr qcpr_..._compressions.csv --trace cpr_trace_123.csv
  python tools/compare_qcpr_trace.py --qcpr qcpr_..._compressions.csv --logcat quest_logcat.txt

Both clocks are wall clocks; a small offset between PC and headset is searched for
automatically (+-3 s) by maximising the number of matched presses.
"""
import argparse
import csv
import re
import statistics
import sys

MATCH_WINDOW_S = 0.35


def read_qcpr(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            unix = row.get("pc_unix_ms") or row.get("unix_ms")
            if not unix:
                continue
            rows.append({"t": int(float(unix)) / 1000.0, "depth_mm": float(row["depth_mm"]),
                         "number": row.get("number") or ""})
    return rows


def quest_from_trace(path):
    presses = []
    previous_count = 0
    peak = 0.0
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if "unix_ms" not in reader.fieldnames:
            sys.exit("trace has no unix_ms column (old format): use --logcat instead")
        for row in reader:
            count = int(row["count"])
            peak = max(peak, float(row["travel_m"]))
            if count > previous_count:
                presses.append({"t": int(row["unix_ms"]) / 1000.0, "depth_mm": peak * 1000.0,
                                "number": count, "hand": row["hand"]})
                previous_count = count
                peak = 0.0
    return presses


def quest_from_logcat(path):
    pattern = re.compile(r"^\s*(\d+\.\d+).*CPR press #(\d+)\s+travel=([\d.]+) cm(?:\s+(\S+))?")
    presses = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = pattern.match(line)
            if match:
                presses.append({"t": float(match.group(1)), "depth_mm": float(match.group(3)) * 10.0,
                                "number": int(match.group(2)), "hand": match.group(4) or ""})
    return presses


def match(quest, manikin, offset):
    """Greedy nearest matching after shifting Quest times by `offset` seconds."""
    pairs = []
    used = set()
    for q in quest:
        best = None
        for i, m in enumerate(manikin):
            if i in used:
                continue
            gap = abs(q["t"] + offset - m["t"])
            if gap <= MATCH_WINDOW_S and (best is None or gap < best[0]):
                best = (gap, i)
        if best is not None:
            used.add(best[1])
            pairs.append((q, manikin[best[1]]))
    return pairs


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--qcpr", required=True, help="qcpr_probe compressions CSV")
    parser.add_argument("--trace", help="headset cpr_trace CSV with unix_ms")
    parser.add_argument("--logcat", help="logcat capture with epoch timestamps (older traces)")
    parser.add_argument("--offset", type=float, help="fixed Quest-minus-manikin clock offset in s (skip the search)")
    parser.add_argument("--out", help="write the matched table as CSV")
    args = parser.parse_args()
    if not args.trace and not args.logcat:
        parser.error("give --trace or --logcat")
    manikin = read_qcpr(args.qcpr)
    quest = quest_from_trace(args.trace) if args.trace else quest_from_logcat(args.logcat)
    if not manikin or not quest:
        sys.exit(f"nothing to compare: {len(manikin)} manikin compressions, {len(quest)} Quest presses")
    if args.offset is None:
        best_offset, best_pairs = 0.0, []
        step = 0.05
        for k in range(-60, 61):
            offset = k * step
            pairs = match(quest, manikin, offset)
            if len(pairs) > len(best_pairs):
                best_offset, best_pairs = offset, pairs
    else:
        best_offset, best_pairs = args.offset, match(quest, manikin, args.offset)
    print(f"manikin compressions: {len(manikin)}   Quest presses: {len(quest)}   matched: {len(best_pairs)}   "
          f"clock offset (Quest - manikin): {best_offset:+.2f} s")
    print(f"{'manikin t':>12} {'#m':>4} {'manikin mm':>10} {'quest mm':>9} {'diff mm':>8} {'ratio':>6} {'hand':>6}")
    diffs, ratios, mani, ques = [], [], [], []
    rows = []
    for q, m in sorted(best_pairs, key=lambda pair: pair[1]["t"]):
        diff = q["depth_mm"] - m["depth_mm"]
        ratio = q["depth_mm"] / m["depth_mm"] if m["depth_mm"] > 0 else float("nan")
        diffs.append(diff)
        ratios.append(ratio)
        mani.append(m["depth_mm"])
        ques.append(q["depth_mm"])
        print(f"{m['t']:12.2f} {str(m['number']):>4} {m['depth_mm']:10.0f} {q['depth_mm']:9.0f} {diff:+8.0f} {ratio:6.2f} {q.get('hand', ''):>6}")
        rows.append({"manikin_t": m["t"], "manikin_number": m["number"], "manikin_depth_mm": m["depth_mm"],
                     "quest_number": q["number"], "quest_depth_mm": round(q["depth_mm"], 1),
                     "diff_mm": round(diff, 1), "ratio": round(ratio, 3), "hand": q.get("hand", "")})
    if diffs:
        n = len(diffs)
        mean_m = sum(mani) / n
        mean_q = sum(ques) / n
        slope = (sum((a - mean_m) * (b - mean_q) for a, b in zip(mani, ques)) /
                 max(1e-9, sum((a - mean_m) ** 2 for a in mani)))
        intercept = mean_q - slope * mean_m
        print(f"\nQuest - manikin: mean {statistics.mean(diffs):+.1f} mm, median {statistics.median(diffs):+.1f} mm, "
              f"spread (sd) {statistics.pstdev(diffs):.1f} mm")
        print(f"Quest / manikin: median ratio {statistics.median(ratios):.2f}")
        print(f"fit: quest_mm = {slope:.2f} * manikin_mm {intercept:+.1f}")
    unmatched_q = len(quest) - len(best_pairs)
    unmatched_m = len(manikin) - len(best_pairs)
    print(f"unmatched: {unmatched_q} Quest presses (counted without a manikin compression), "
          f"{unmatched_m} manikin compressions (missed by the Quest)")
    if args.out and rows:
        with open(args.out, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        print("written", args.out)


if __name__ == "__main__":
    main()
