# Integration test review — 3 October 2026

Reviewed local integration base `bc18287`, with additional startup anchor tests.

Godot 4.7.1 headless, XR off, Dummy audio, NARET_OFFLINE=1:

- Editor import: passed without script/parse errors.
- All 12 test suites: passed, zero failures.
- DE/PL scenario smoke test: passed (scene wiring, ECG, export and language modes).
- Startup anchor integration: hidden before acceptance, shown at reading 42 for
  stable input, calibrated model offset applied once, unlock clears collection.
- Startup fallback: accepts at 100 even for moving input, as inherited. This is
  explicitly tested behavior, not evidence of reliable alignment.
- Viewer gate: initial bias cancellation, later residual motion, head-motion
  hold, partial evidence and large-move override passed synthetic tests.
- Counting: 32 simulated strokes count as 32; resting jitter and interrupted
  strokes do not count; counting recovers after a tracking dropout.

Logs: `build/review_import.log`, `build/review_tests.log`, `build/review_smoke.log`.

Limits: ADB returned no connected devices. No headset test or installation was
performed. The native ArUco addon is not staged in this checkout; its editor
plugin declaration was temporarily disabled during desktop tests and restored.
Tests do not establish camera detection, physical alignment, actual hand tracking,
compression depth accuracy, or the suitability of the inherited gate thresholds.
The optional three-marker layout still needs a measured common-to-sternum profile.
