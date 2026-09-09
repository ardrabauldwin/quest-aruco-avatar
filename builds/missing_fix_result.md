# Missing-marker common-point fix

The active provider previously appended synthesized missing-marker poses to a list of common-point poses. These origins represent different physical points. Furthermore, inferred markers add no independent measurements and can overweight their source detection. The fix uses each genuinely detected marker once, transformed into the common frame by its calibration. The inverse-offset synthesis path was removed from fusion.

Controlled geometry regression: before the fix, perfect marker poses produced common-point errors up to 10.05 cm as visibility changed. After the fix, all seven nonempty marker subsets recover the common pose within 0.01 mm numerical tolerance. A two-source noise example verifies equal independent-source weights; an empty observation preserves the previous pose. Existing filter/rest/floor tests pass.

Offline replay of recordings/aruco_viewpoint_1788955119.csv, 72 Hz assumed, cold start, actual current temporal filter, calibration matched to the Quest. Pre-fix provider is pinned in project/tests/provider_before_missing_fix.gd, replay in project/tests/replay_missing_fix.gd. CSVs are builds/replay_missing_before72.csv and builds/replay_missing_after72.csv; metrics in builds/missing_fix_metrics.json. This is not logged online avatar output or absolute accuracy.

| View | Displacement before/after (cm) | Spread before/after (cm) |
|---|---:|---:|
| Front | 0.11 / 0.11 | 0 / 0 |
| Left | 4.42 / 4.42 | 0.13 / 0.13 |
| Right | 3.38 / 2.38 | 2.14 / 2.38 |
| Far front | 9.34 / 10.48 | 3.73 / 4.10 |
| Far left | 14.31 / 14.26 | 1.21 / 1.08 |
| Far right | 11.60 / 16.21 | 2.38 / 1.19 |
| Front return | 11.46 / 12.70 | 2.48 / 0.59 |

Displacement: distance of filtered segment median from each replay's front raw reference. Spread: 90% radius about the segment's own median. Statistics omit the first second of each stationary label, require initialized output, and are conditional on available measurements. No ground-truth marker positions are available.

Conclusion: a proven coordinate/weighting bug has been removed. Real-data viewpoint consistency is not uniformly improved; some metrics worsen. An incorrect transformation can partially cancel other errors, so a smaller displacement metric alone does not validate the old geometry. The remaining camera/marker biases and filter adaptation need separate investigation. This fix does not establish that the original three-week tracking problem is solved or caused by the newer missing-marker change.

No APK was installed as part of this controlled code-and-replay step.
