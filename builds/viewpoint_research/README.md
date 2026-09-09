# Viewpoint experiment: measured inputs and filter replay

Source: `recordings/aruco_viewpoint_1788955119.csv`, 2020 logged results, September 9, 2026. The user reports a stationary manikin and a measured 100 cm front-to-far-front move. No physical ground-truth marker positions were logged.

## Figures

- `summary.png` / `.pdf`: displacement and within-label spread, separately.
- `each_view_before_after.png` / `.pdf`: position and heading time series for all seven stationary labels.
- `filter_comparison.png` / `.pdf`: full experiment including walking, current filter, rest pull disabled, and rest re-anchoring disabled.
- `metrics.json`: numerical results.

## What was actually compared

The raw curves are the **fused common pose**, after camera-to-world conversion, marker-to-common calibration and the existing orientation floor constraint. They are not individual marker centres. The filtered curves are **offline replays**, not measurements of the avatar displayed during the recording.

The replay uses the actual `CommonPoseProvider`, `SimplePoseStabilizer` and rig tracking functions in the current source. Current parameters: five-detection medoid, 20 mm position dead zone, 0.3 degree rotation dead zone, 1.2 s smoothing time, 2 s rest-pull time, automatic rest updates after the configured endpoint test. Device calibration was read and matches the bundled calibration used here.

Assumptions: cold start at CSV beginning; simulated 72 Hz render loop; CSV logger timestamps approximate detection application timestamps; hold latest successful result for 300 ms before tracking-loss handling. A 90 Hz sensitivity replay was also run. Original filter history before recording, actual render intervals, application pause/relevel events and exact detection/capture timestamps are unavailable. A logged result is not necessarily every camera frame. Filtered outputs are sampled just before the newly logged measurement is processed by the next simulated render tick.

The graph is for the rig/common pose BEFORE geometry-dependent floor lift and the final child/nudge transform. Consequently it does not measure actual head, ear, chest-surface or displayed-avatar alignment. Those need additional output logs or independent visual/physical ground truth. No app code or APK was changed for this analysis.

Stationary statistics exclude the first second of the label and require initialized replay output. Missing-marker rows have no raw fused measurement and are omitted from the paired comparison; thus this is conditional on available measurements. Walking segments are retained in the continuous replay, not reset between views. The reference is the median initialized raw fused position in the initial front label. Displacement is relative to that reference, not absolute accuracy. Spread is the 90th percentile of Euclidean distance from each series' own within-label median; it includes drift/transients and is not a pure sensor-noise variance. Zero front spread means this simulated output was held constant, not perfect measurement or physical alignment.

## Results (cm)

| View | Raw spread | Replayed spread | Raw reference displacement | Replayed reference displacement |
|---|---:|---:|---:|---:|
| Front | 6.82 | 0.00 | 0.00 | 0.11 |
| Left | 3.99 | 0.13 | 5.79 | 4.42 |
| Right | 7.06 | 2.14 | 2.41 | 3.38 |
| Far Front | 6.71 | 3.73 | 8.92 | 9.34 |
| Far Left | 5.56 | 1.21 | 13.71 | 14.31 |
| Far Right | 5.36 | 2.38 | 11.46 | 11.60 |
| Front Return | 7.61 | 2.48 | 12.55 | 11.46 |

These differ from the earlier individual-marker table because common-point reconstruction includes each marker's orientation and calibration offset, and fuses a changing set of visible markers.

Disabling automatic rest updates (while retaining rest pull) reduced far-front/left/right reference displacement from 9.34/14.31/11.60 cm to 5.80/8.55/7.22 cm. This is evidence that rest adaptation contributes under the replay assumptions. It does not prove those latter positions are physically correct. Disabling only the rest pull left substantial displacement (9.28/14.14/11.58 cm). Median displacement metrics at 72 versus 90 Hz differed by under 0.04 cm here; that small sensitivity does not validate unknown initial state or camera timing. A repeat run produced an identical SHA256 for the current72 replay CSV.

## Interpretation for a research discussion

1. Temporal stabilization helps within-view spread, but does not establish viewpoint-invariant placement.
2. Marker detection availability and quality are different: a detected marker can still supply an unstable pose. At far right, ID0/ID2 appear in about 9%/7% of logged stationary samples.
3. Orientation matters. A common point reconstructed as t + R o inherits both translation error and rotation error. The far-right raw fused heading contains large excursions, so a depth-only explanation is inadequate.
4. Equal-weight fusion of the available markers can change when their visibility changes. Marker-specific biases and orientation errors can then become changes in the common-point estimate.
5. Rest adaptation is a mechanism for persistent movement: a stable medoid target is not independent evidence that the manikin moved. Three successive overlapping medoid targets may repeat even when individual inputs are unstable.
6. The 100 cm floor-mark move is not identical to headset optical-range change. Recorded median horizontal headset displacement is about 88 cm; posture, placement/label timing and coordinate drift remain possible contributors. Front-return is still about 89 cm from the initial front in recorded coordinates, so it cannot validate return repeatability without clarification.
7. Neither a Kalman filter nor an ML model can distinguish arbitrary true movement from arbitrary measurement bias using these observations alone. Additional constraints, calibration or ground truth are necessary. A stationary-placement lock is a task-specific constraint, not a proof of general moving-object tracking accuracy.

## Proposed next work, in order

- Instrument actual displayed rig/child pose, pre-floor filtered pose, rest pose and rest-update events; record detector timestamps, marker corners, reprojection residuals and marker availability. Compare online output with replay before claiming an exact filter benefit.
- For stationary training, compare fixed placement after verified initial alignment against the current adaptive pipeline. Explicitly label this stationary-use baseline; it cannot follow a moved manikin.
- Validate camera intrinsics, distortion, camera-to-headset transform and timing; then evaluate quality-aware fusion and measurement rejection. Do not fit a camera calibration correction solely to this one trajectory.
- If continuous tracking is required, validate on held-out viewpoints and a separate physical-manikin movement trial. Measure static spread, viewpoint displacement, rotational error, latency, detection coverage and movement retention separately.

Reproduction: run `project/tests/replay_viewpoint_research.gd` with Godot headless, then `tools/plot_viewpoint_research.py` with NumPy and Matplotlib. Figures and metrics are derived from the same replay files in `builds/replay_*.csv`.
