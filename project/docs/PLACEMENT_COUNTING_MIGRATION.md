# Placement and counting migration — 3 October 2026

Reviewed target: `NaReT-Nachbarsprache-wird-reanimiert/naret-xr-app`, main
`9d880a1` (Dennis, 28 September 2026). This is Godot/OpenXR, not Unity.
Prepared locally on `integration/placement-counting`. The available account
has read access, not push access. No headset installation or upstream merge occurred.

## What Dennis already integrated

- `tools/setup_dependencies.py` stages the upstream hand zone, compression
  session, metronome and stabilizer from the pinned avatar submodule.
- `NaretXRInteraction` attaches that zone to his patient's sternum and publishes
  compression events into `scripts/main.gd` and the existing scenario controller.
- His tracker consumes world poses from the ArUco addon. His spatial anchor
  follows then settles a single sternum marker, and applies persisted calibration.
- German/Polish dialogue, scenario progression, feedback, QCPR and logging are
  already separate modules. None need to be replaced by the older demo scene.

## Implemented changes

1. Advance the avatar dependency from `1560fee6bf766f4dae98f5025155b14476b75877`
   to published `728f35d11ab344d37707401c03e5ea6ce579c76d`. This includes the newer
   recoil, short-spike rejection, off-beat counting and hand-handover work.
   This is a committed source baseline, NOT a claim of reproducing Thursday's APK.
2. Update staging policy patches: NaReT still owns breathing pauses and metronome
   presentation. The newer detector no longer requires the old beat-gate patch.
   Staging verifies each replacement instead of silently modifying unknown source.
3. Preserve NaReT's sternum-relative contact envelope when importing the newer
   upstream surface-slab scene. Hand excursion remains unverified chest depth.
4. Add optional `NaretMarkerLayout`: each current-frame marker world pose times
   its calibrated marker-to-common transform gives a common estimate. Equal
   position mean and sign-aligned quaternion mean reconstruct the shared pose.
   A separately measured common-to-sternum transform adapts it to Dennis's anchor.
   Known markers work individually during occlusion. Unknown, stale, non-finite
   and non-rigid poses do not become new measurements.
5. Add `marker_layout_file` on the main scene root and tracker. Empty retains
   the original single-marker behavior. A malformed selected profile fails closed.
   Layout profiles own marker size; single-marker size controls are hidden in
   that mode. The native detector receives the profile's measured marker size.

## Calibration before enabling the older three-marker layout

Do not copy the old torso's nudge or floor offset onto Dennis's different human
model. Do not treat common marker 0 as if it were at the sternum.

Start with the existing measured `[common]` entries (`aruco_patch0/1/2`) and add
a `[layout]` section with `marker_size_m=0.10` and an explicitly measured rigid
`common_to_sternum=Transform3D(...)`. This is a Godot ConfigFile.

To derive that bridge at a verified aligned pose:

```
common_to_sternum = common_world.affine_inverse()
                   * desired_patient_anchor_world
                   * anchor.marker_to_mannequin.affine_inverse()
```

The bridge includes the axis convention difference as well as translation.
Clear or recalibrate any single-marker saved patient offset before measuring;
keep the resulting profile and patient calibration together. Set the main scene
root's `marker_layout_file` to that profile. An old `[common]` file alone is
intentionally rejected. No real bridge has been measured for the new model yet.

The adapter reports `layout_position_spread_m` for diagnostics. It does not
claim that averaging removes a shared bias. It does not apply the 0.937 factor,
the old distance-dependent correction, floor snapping, or old 10 cm/10 degree
viewer-bias cancellation inside the adapter. The anchor now separately applies
the user's startup estimator and viewer gate in XR; see
`VIEWER_GATE_MIGRATION.md`. This migration does not prove side drift fixed.

## Clean merge strategy

- Base the feature branch on the app's current main; merge only the adapters,
  dependency pin, staging changes and tests. Do not merge the old project history,
  `main_3d.tscn`, camera loop, export settings, saved user data or APK overlays.
- Keep one detector, one spatial anchor, one hand counter and the existing
  scenario controller. Preserve BLE/simulator and hand-source arbitration.
- Review/apply the patch in this private app repository. Do not publish its code
  into the older public avatar repository.
- Stage pinned dependencies, import, run tests and the offline smoke test.
- Then validate on Quest: each marker individually, all three, occlusion,
  front/side/back, tracking recovery, known counted presses, hand switching,
  and no duplicate counts with QCPR. Test the default single-marker mode too.
- Keep deployment separate from source review. No APK has been built or installed.

## Validation

Local Godot 4.7.1, headless, XR disabled, dummy audio and `NARET_OFFLINE=1`:
import clean; 12 suites / 0 failures; DE/PL scenario smoke passed. The target
native editor plugin was temporarily disabled for these desktop tests because
native dependencies were not staged; its original setting has been restored.
The calibration UI also passed a separate script check after its change. The target
documents Godot 4.7.2 for CI; that version and on-device tracking remain untested.
Tests cover rotated coordinate composition, marker-zero occlusion, explicit
calibration, native marker size, stale input, 32 strokes across the scenario
cycle boundary, tracking dropout and resting jitter. They do not establish
physical placement accuracy or actual chest compression depth.
