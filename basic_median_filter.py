"""The same filter with NO physics assumption, and the median used everywhere.

Run (the recordings are listed in main):
    python basic_median_filter.py

basic_tune_filter.py assumes the mannequin is lying flat: it throws away detections
that claim too much tilt (the 30 degree gate) and deletes the tilt from the ones it
keeps (flatten_to_yaw). Both of those are beliefs about the body, not measurements.

This script has neither. Nothing in it knows how the mannequin is lying. It would
work the same on a body standing up, on a table, or hanging from a rope - and it
keeps all three rotation axes from the first line to the last.

One idea, used everywhere: THE MIDDLE VALUE.

    target  = median position + medoid rotation of the last few detections
    anchor  = median position + medoid rotation of the first second
    filter  = drift back toward that anchor  (mean-reverting)

For rotations the median is called the MEDOID: quaternions cannot be sorted, so
"the middle one" means the sample closest to all the others. Same idea, and like a
median it can only ever return a pose that was really measured - an average can be
dragged somewhere no detection ever claimed.

Measured cost of dropping the physics, best of the 64 settings, against
basic_tune_filter.py on the same recordings:

    headmotion   0.078 -> 0.123
    walk_final   0.116 -> 0.263

Almost all of it is DRIFT, not wobble. Wobble and jump still come out 88-96%
removed here; what collapses is position drift (82% -> 31% on walk_final) and
rotation drift (70% -> 41%). That is exactly what the two deleted steps were for:
the gate stopped a phantom detection from teaching the anchor, and the flat lock
stopped the tilt from wandering. Without them the anchor slowly learns the noise.
"""

from itertools import product
from pathlib import Path

import numpy as np

from basic_tune_filter import (
    POSITION_DEAD_ZONES_M,
    PRIOR_TIME_S,
    SLOW_TIME_S,
    SMOOTHING_TIMES_S,
    WINDOWS,
    blend_rotation,
    load_poses,
)
from filter_errors import angle_deg, measure_errors

RECORDINGS = ["data/today/headmotion_1785761051.csv",
              "data/today/walk_final_1785760244.csv"]


# =========================================================================
# 1. THE MIDDLE VALUE  (one helper; position already has np.median)
# =========================================================================

def medoid_rotation(block):
    """The most central rotation of the block - the median, for things you can't sort.

    Every candidate scores the total angle to all the others; the smallest wins.
    """
    best, best_score = block[0], np.inf
    for candidate in block:
        score = sum(angle_deg(candidate, other) for other in block)
        if score < best_score:
            best_score, best = score, candidate
    return best


# =========================================================================
# 2. THE ANCHOR  (the filter's belief of where the mannequin lives)
# =========================================================================

def settle_prior(positions, rotations, avg_gap):
    """Middle pose of the first second - about 4 detections on these recordings."""
    count = max(1, int(round(1.0 / avg_gap)))
    return (np.median(positions[:count], axis=0),
            medoid_rotation(rotations[:count]))


# =========================================================================
# 3. THE TARGETS  (where the filter aims, one target pose per detection)
# =========================================================================

def window_targets(positions, rotations, window):
    """Middle pose of the last `window` detections. All three rotation axes kept."""
    target_p = positions.copy()
    target_r = rotations.copy()

    for i in range(window - 1, len(positions)):
        first = i - window + 1
        target_p[i] = np.median(positions[first : i + 1], axis=0)
        target_r[i] = medoid_rotation(rotations[first : i + 1])

    return target_p, target_r


# =========================================================================
# 4. THE FILTER  (one full replay)
# =========================================================================

def run_filter(targets, amount, dead_zone_m, prior_p, prior_r, prior_amount,
               slow_amount):
    """Dead zone + easing, then mean-reverting pull, then the anchor heals."""
    target_p, target_r = targets
    position = target_p[0]
    rotation = target_r[0]
    out_p, out_r = [], []

    for i in range(len(target_p)):
        # POSITION: hold inside the dead zone, otherwise ease toward the target.
        if np.linalg.norm(target_p[i] - position) > dead_zone_m:
            position = position + (target_p[i] - position) * amount

        # ROTATION: ease toward the target. All three axes, nothing deleted.
        rotation = blend_rotation(rotation, target_r[i], amount)

        # MEAN-REVERTING: drift back toward the anchor, position and rotation.
        position = position + (prior_p - position) * prior_amount
        rotation = blend_rotation(rotation, prior_r, prior_amount)

        # The anchor heals: it follows the estimate as a very slow EMA, so a
        # mannequin that genuinely moved is accepted in a couple of minutes.
        prior_p = prior_p + (position - prior_p) * slow_amount
        prior_r = blend_rotation(prior_r, rotation, slow_amount)

        out_p.append(position)
        out_r.append(rotation)

    return np.array(out_p), np.array(out_r)


# =========================================================================
# 5. THE TEST BENCH  (try all 64 settings, print the ten best + the winner)
# =========================================================================

def main():
    for name in RECORDINGS:
        positions, rotations, avg_gap = load_poses(Path(name))
        raw = measure_errors(positions, rotations)

        prior_p, prior_r = settle_prior(positions, rotations, avg_gap)
        prior_amount = 1 - np.exp(-avg_gap / PRIOR_TIME_S)
        slow_amount = 1 - np.exp(-avg_gap / SLOW_TIME_S)

        results = []
        for window in WINDOWS:
            targets = window_targets(positions, rotations, window)
            for dead_m, smooth in product(POSITION_DEAD_ZONES_M, SMOOTHING_TIMES_S):
                amount = 1 - np.exp(-avg_gap / smooth)
                filtered_p, filtered_r = run_filter(
                    targets, amount, dead_m, prior_p, prior_r, prior_amount,
                    slow_amount)

                # Skip the frames the window and the smoothing are still filling.
                skip = window + int(smooth / avg_gap)
                if len(filtered_p) - skip < 20:
                    continue

                errors = measure_errors(filtered_p[skip:], filtered_r[skip:])
                score = float(np.mean([a / b for a, b in zip(errors, raw)]))
                results.append((score, window, dead_m, smooth, errors))

        results.sort(key=lambda r: r[0])

        print(f"\n{Path(name).name}   {len(positions)} detections, "
              f"{1 / avg_gap:.1f} Hz")
        print(f"{'score':>6} {'window':>7} {'pos mm':>7} {'smooth s':>9}")
        for score, window, dead_m, smooth, _ in results[:5]:
            print(f"{score:6.3f} {window:7d} {dead_m * 1000:7.1f} {smooth:9.2f}")

        score, window, dead_m, smooth, errors = results[0]
        names = ["position wobble", "position jump  ", "position drift ",
                 "rotation wobble", "rotation jump  ", "rotation drift "]
        units = ["mm", "mm", "mm", "deg", "deg", "deg"]
        print(f"  best: window {window}, dead zone {dead_m * 1000:.0f} mm, "
              f"smoothing {smooth:.2f} s")
        for label, unit, before, after in zip(names, units, raw, errors):
            print(f"    {label} {before:7.2f} -> {after:5.2f} {unit:<4}"
                  f"({(1 - after / before) * 100:3.0f}% removed)")


if __name__ == "__main__":
    main()
