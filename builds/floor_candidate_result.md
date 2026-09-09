# Floor-constrained reconstruction experiment

Decision: do not promote the candidate into the app on this evidence.

Input: recordings/aruco_viewpoint_1788955119.csv. Replay: project/tests/replay_floor_candidate.gd. Metrics: builds/floor_candidate_metrics.json. Figure: builds/floor_candidate_comparison.pdf.

The comparison isolates original measured-marker-only common reconstruction against per-marker floor-constrained reconstruction. Both use the same bundled calibration (verified against the device), initialization and temporal filter, with a simulated 72 Hz loop. Each method uses its own initial-front raw median as a relative reference. This tests viewpoint consistency, not absolute position accuracy. Replay limitations from viewpoint_research/README.md apply: unknown initial online state and render timing, no final avatar/floor geometry output, statistics conditional on marker measurements.

Candidate formula: for marker world pose M and stored marker-to-common transform A, first construct the common orientation from M*A, constrain that orientation to the floor, then estimate the common origin as M.origin - constrained_basis * A.affine_inverse().origin. Fuse the resulting common poses using the existing mean. No candidate parameters were fitted to this recording.

A synthetic geometry test passed: an isolated 15-degree pitch error with correct marker translation induced 3.95 cm baseline common-position error and approximately zero candidate error. Thus the intended geometric error pathway is removed in that controlled case.

Real-data filtered displacement/spread in cm:

| View | Original displacement | Candidate displacement | Original spread | Candidate spread |
|---|---:|---:|---:|---:|
| Front | 0.11 | 0.12 | 0.00 | 0.00 |
| Left | 4.42 | 5.44 | 0.13 | 1.59 |
| Right | 2.38 | 6.03 | 2.38 | 2.61 |
| Far front | 10.48 | 9.94 | 4.10 | 4.96 |
| Far left | 14.26 | 14.35 | 1.08 | 3.42 |
| Far right | 16.21 | 17.63 | 1.19 | 2.01 |
| Front return | 12.70 | 13.09 | 0.59 | 4.10 |

Raw front spread improves from 6.82 to 1.60 cm, but that benefit does not generalize to other viewpoints or the final temporal output. The remaining error is not explained by isolated pitch/roll noise. Translation/rotation coupling, yaw instability, calibration/model assumptions and differing marker availability remain possible contributors; this experiment does not uniquely identify them.

Provenance warning: workspace commit 772977b added missing-marker reconstruction during the wider investigation. Its generated missing-marker poses are appended directly to common-point estimates without converting them back to the common point. That is a separate frame-consistency concern. It is excluded from both arms of this controlled comparison and was not overwritten or silently fixed here. Earlier unpinned replay reports must not be treated as a single immutable baseline across that source change.

Only research/test artifacts were added in this experiment. No APK was built or installed and the active provider was not edited.
