# Viewer-motion gate restored — 3 October 2026

This update supersedes earlier notes saying Dennis's automatic re-placement rule
remains active in XR. Models, counting and scenario logic stay as already merged.

After initial placement, the XR camera drives the port of `_gate_measurement`
from the older local `project/avatar_rig_navel.gd`:

- Speed above 0.15 m/s OR yaw rate above 20 degrees/s over 0.3 s resets stillness.
- Hold until 0.5 s of stillness, then collect five fresh marker results.
- Coordinate medians of horizontal displacement and relative yaw define bias.
  Within 10 cm AND 10 degrees, subtract that initial bias from later readings.
  Later residual changes can still move the patient through the stabilizer.
- A larger settled difference requires full configured-marker evidence and no
  detected hand over the chest. Partial windows hold and retry.
- More than 30 cm OR 25 degrees over three full-evidence detections retains the
  original large-move override, including while the viewer moves.
- Beyond 1.8 m, hold ordinary updates; the large-move override is checked first.

Heading uses the new patient's -Z axis, not the old common rig's +Y axis.
The tracker supplies unsmoothed XR measurements; smoothing runs after the gate.
The anchor holds its placed vertical coordinate. No old GLB, nudge or range
scaling is restored. XR startup now uses the user's robust estimator: collect
distinct observations, estimate coordinate-median position and rotation medoid
at readings 30, 33, 36, etc. Four consecutive estimate changes within 1.5 mm AND
1 degree allow placement (reading 42 earliest). Reading 100 is the inherited
fallback even without convergence; it is not evidence of accurate placement.
The patient stays hidden until acceptance. Desktop preview retains Dennis's
original behavior. Explicit anchor unlock clears startup, gate and filter state.

Full evidence means all markers in the chosen profile, or the single configured
marker in default mode. It is not independent confirmation that the mannequin
moved. The restored heuristic may absorb a real small move, follow a persistent
bad large reading, or permit later drift. It measures yaw, not full head rotation.
These inherited limits are not claimed fixed by this migration.

Validation: Godot 4.7.1 offline import, 12 suites and DE/PL smoke test. Tests include
five distinct readings, initial bias cancellation, later residual motion, moving
head, large-move evidence, heading convention, partial windows and anchor wiring.
No Quest validation, APK installation or remote push has occurred. Three-marker
operation still requires the explicit common-to-sternum calibration profile.
