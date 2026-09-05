"""LEGACY grid search for the two numbers that were CHOSEN instead of measured.

This script predates the active combined 6-DoF medoid and render-rate Quest replay. Keep its old
results only as historical evidence; do not copy its winner into the APK. The authoritative replay
is now tune_filter.py, whose stabilizer accepts prior_time_s and rest_heal_time_s for the combined
stationary + moving experiment.

Run:
    python basic_prior_search.py

basic_median_filter.py searches window, dead zone and smoothing - 64 settings - but
the runtime PRIOR_TIME_S (1 s) and rest-healing time (600 s) are typed in by hand.
This script sweeps those two as well, and for every pair reports the best of the
same 64 settings.

    PRIOR_TIME_S   how hard the anchor pulls the estimate back
    SLOW_TIME_S    how fast the anchor itself learns the estimate

READ THE ANSWER CAREFULLY. What matters is not just which cell wins, but WHERE it
sits. If the winner is in the MIDDLE of the grid, the recording genuinely prefers
that value. If the winner is at the EDGE, the recording is only saying "more,
please" and the grid cannot choose for you - it means the cost of that direction is
invisible in this data, not that it is zero.

That is the trap with a stationary recording: a pull that is too strong shows no
cost at all, because nothing ever moves for it to lag behind. So an edge winner on
stationary data must NOT be copied into the headset.
"""

import argparse
from itertools import product
from pathlib import Path

import numpy as np

from basic_median_filter import run_filter, settle_prior, window_targets
from basic_tune_filter import POSITION_DEAD_ZONES_M, SMOOTHING_TIMES_S, WINDOWS, load_poses
from filter_errors import measure_errors

DEFAULT_RECORDINGS = ["data/today/headmotion_1785761051.csv",
                      "data/today/walk_final_1785760244.csv"]

# inf = the step is switched off: no pull at all / an anchor that never learns.
PRIOR_TIMES_S = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 30.0, np.inf]
SLOW_TIMES_S = [1.0, 2.0, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0, 600.0, np.inf]

# Values currently shipped in avatar_rig_navel.gd and navel_provider.gd.
# Values currently enabled in the runtime.
RUNTIME_PRIOR_TIME_S = 8.0
RUNTIME_SLOW_TIME_S = 600.0


def best_of_the_grid(cache, avg_gap, raw, prior_p, prior_r, prior_time, slow_time):
    """Best score over the usual 64 settings, for one (prior, slow) pair."""
    prior_amount = 1 - np.exp(-avg_gap / prior_time)
    slow_amount = 1 - np.exp(-avg_gap / slow_time)
    best = np.inf

    for window in WINDOWS:
        targets = cache[window]
        for dead_m, smooth in product(POSITION_DEAD_ZONES_M, SMOOTHING_TIMES_S):
            amount = 1 - np.exp(-avg_gap / smooth)
            filtered_p, filtered_r = run_filter(
                targets, amount, dead_m, prior_p, prior_r, prior_amount, slow_amount)

            skip = window + int(smooth / avg_gap)
            if len(filtered_p) - skip < 20:
                continue
            errors = measure_errors(filtered_p[skip:], filtered_r[skip:])
            best = min(best, float(np.mean([a / b for a, b in zip(errors, raw)])))
    return best


def label(value):
    return "off" if np.isinf(value) else f"{value:g}"


def main():
    parser = argparse.ArgumentParser(
        description="Sweep rest-pull and rest-healing times for one or more recordings.")
    parser.add_argument(
        "recordings", nargs="*", default=DEFAULT_RECORDINGS,
        help="CSV recordings (defaults to the two data/today recordings)")
    args = parser.parse_args()

    for name in args.recordings:
        positions, rotations, avg_gap = load_poses(Path(name))
        raw = measure_errors(positions, rotations)
        prior_p, prior_r = settle_prior(positions, rotations, avg_gap)

        # The targets do not depend on either swept number, so build them once.
        cache = {w: window_targets(positions, rotations, w) for w in WINDOWS}

        print(f"\n{Path(name).name}   {len(positions)} detections, "
              f"{1 / avg_gap:.1f} Hz")
        print("  rows = PRIOR_TIME_S (pull), columns = SLOW_TIME_S (healing)\n")
        print(f"{'prior':>7} " + " ".join(f"{label(s):>7}" for s in SLOW_TIMES_S))

        table = {}
        for prior_time in PRIOR_TIMES_S:
            row = []
            for slow_time in SLOW_TIMES_S:
                score = best_of_the_grid(cache, avg_gap, raw, prior_p, prior_r,
                                         prior_time, slow_time)
                table[(prior_time, slow_time)] = score
                row.append(score)
            print(f"{label(prior_time):>7} " + " ".join(f"{s:7.3f}" for s in row))

        (best_prior, best_slow), best_score = min(table.items(), key=lambda kv: kv[1])
        on_prior_edge = best_prior in (PRIOR_TIMES_S[0], PRIOR_TIMES_S[-1])
        on_slow_edge = best_slow in (SLOW_TIMES_S[0], SLOW_TIMES_S[-1])

        print(f"\n  best {best_score:.3f} at prior {label(best_prior)} s, "
              f"slow {label(best_slow)} s")
        runtime_score = table[(RUNTIME_PRIOR_TIME_S, RUNTIME_SLOW_TIME_S)]
        print(f"  runtime {label(RUNTIME_PRIOR_TIME_S)} s / "
              f"{label(RUNTIME_SLOW_TIME_S)} s scores {runtime_score:.3f}"
              f"  ({runtime_score - best_score:+.3f})")
        for axis, edge, chosen in (("prior", on_prior_edge, best_prior),
                                   ("slow ", on_slow_edge, best_slow)):
            where = "AT THE EDGE - the recording cannot choose, it only wants more"
            print(f"  {axis}: {label(chosen):>4} s  "
                  f"{where if edge else 'inside the grid - a real optimum'}")


if __name__ == "__main__":
    main()
