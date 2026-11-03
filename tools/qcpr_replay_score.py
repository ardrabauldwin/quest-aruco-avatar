"""Score replayed Quest press counting against a QCPR manikin recording.

For each min_count_excursion_m value, tools/replay_cpr_trace.gd replays the headset trace and
every counted press is paired with a real compression (its deepest point, from the manikin's
live depth curve) that it follows by -150..+450 ms: the counter fires during recoil.

  python tools/qcpr_replay_score.py --godot <godot_console.exe> \
      --stem C:/Users/me/Downloads/qcpr_quest_20261103_1211 --trace <cpr_trace.csv> \
      --offset-ms -113 --values 0.016 0.025 0.03

--stem names the probe outputs (<stem>_raw.csv, <stem>_quest_logcat.txt); --offset-ms is the
headset clock minus the PC clock from qcpr_quest_compare.py --measure-offset.
"""
import argparse
import csv
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from qcpr_quest_compare import manikin_compressions  # noqa: E402

EARLY_MS, LATE_MS = 150, 450
ROOT = Path(__file__).resolve().parents[1]


def trace_to_pc(trace: str, logcat: str, offset_ms: int) -> int:
    """PC ms minus trace t_ms. Each logged "CPR press #n" is the trace row where count reaches n;
    the count restarts with the app, so take the offset most presses agree on (10 ms bins)."""
    logged = {}
    for line in open(logcat, encoding="utf-8", errors="replace"):
        m = re.match(r"^\s*(\d+\.\d+)\s.*CPR press #(\d+)", line)
        if m:
            logged[int(m[2])] = round(float(m[1]) * 1000) - offset_ms
    votes, previous = {}, None
    for row in csv.DictReader(open(trace, encoding="utf-8")):
        count = int(row["count"])
        if previous is not None and count > previous and count in logged:
            key = (logged[count] - int(row["t_ms"])) // 10
            votes[key] = votes.get(key, 0) + 1
        previous = count
    return max(votes, key=votes.get) * 10


def replay(godot: str, trace: str, excursion: float, mode: str = "reset") -> list:
    out = subprocess.run([godot, "--headless", "--xr-mode", "off", "--path", str(ROOT), "-s",
                          "res://tools/replay_cpr_trace.gd", "--", trace, str(excursion), mode],
                         capture_output=True, text=True, timeout=120).stdout
    return [(int(a), float(b)) for a, b in re.findall(r"^PRESS (\d+) ([\d.]+)", out, re.M)]


def score(real: list, presses: list, shift: int) -> tuple:
    start, end = real[0][0] - 3000, real[-1][0] + 3000  # only the manikin session
    counted = [t + shift for t, _ in presses if start <= t + shift <= end]
    used, hits = set(), 0
    for bottom, _, _ in real:
        options = [(abs(c - bottom), i) for i, c in enumerate(counted)
                   if i not in used and -EARLY_MS <= c - bottom <= LATE_MS]
        if options:
            used.add(min(options)[1])
            hits += 1
    return hits, len(real), len(counted) - hits


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--godot", required=True)
    p.add_argument("--stem", action="append", required=True)
    p.add_argument("--trace", required=True)
    p.add_argument("--offset-ms", type=int, action="append", required=True)
    p.add_argument("--mode", default="reset", choices=["reset", "join"])
    p.add_argument("--values", type=float, nargs="+", default=[0.016, 0.02, 0.025, 0.03, 0.035, 0.04])
    a = p.parse_args()
    sessions = []
    for stem, offset in zip(a.stem, a.offset_ms):
        sessions.append((Path(stem).name, manikin_compressions(f"{stem}_raw.csv"),
                         trace_to_pc(a.trace, f"{stem}_quest_logcat.txt", offset)))
    for value in a.values:
        presses = replay(a.godot, a.trace, value, a.mode)
        parts, hit_sum, real_sum, false_sum = [], 0, 0, 0
        for name, real, shift in sessions:
            hits, total, false = score(real, presses, shift)
            parts.append(f"{name[-4:]}: {hits}/{total} real, {false} false")
            hit_sum, real_sum, false_sum = hit_sum + hits, real_sum + total, false_sum + false
        print(f"{a.mode:5} min_count_excursion {value*100:4.1f} cm -> {hit_sum}/{real_sum} real, {false_sum} false   ({'; '.join(parts)})")


if __name__ == "__main__":
    main()
