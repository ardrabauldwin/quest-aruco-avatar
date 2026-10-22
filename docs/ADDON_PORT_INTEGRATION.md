# addon-port integration

Source: `ardrabauldwin/quest-aruco-avatar`, branch `addon-port`, commit `729f8c0`.
Working branch: `integration/addon-port-colour-20261008`.

The `project/addons/opencv_aruco` subtree was imported, including its Android
libraries and export guard. This is a selective port, not a wholesale merge of
the older demo project. The import manifest is `build/addon-port-import.json`.
The previous addon is backed up in `build/opencv_before_addon_port`, excluded
from Godot imports with `.gdignore`.

## Active camera path

Superseded: detection now runs upstream's `ArucoMarkerTracking` node from
`godot-opencv-aruco` `main` unchanged, created by `NaretArucoTracker`. Stage it
with `python -c "import sys; sys.path.insert(0,'tools'); import setup_dependencies as s; s.stage_aruco(True)"`,
which copies `addons/opencv_aruco` and `addons/GodotAndroidCamera` from the
submodule.

- Camera: CameraX (GodotAndroidCamera), left passthrough camera "50", 640x480
  luma plane with sensor timestamps. No GPU readback.
- Detector: ArucoNano at full resolution with upstream's calibration.
- The only override is the dictionary, 4x4/50 (value 1), plus the marker sizes
  from the tracking configuration.
- The orange/blue colour path (`user_camera_provider.gd`, colour shader) was
  removed: luma frames carry no colour. Print the marker black on white.

Placement, marker fusion, startup, motion gating, smoothing, model alignment,
compression counting, HUD and speech are not replaced by the demo's versions.

## Scope and verification limits

The addon's standalone `ArucoMarkerTracking` node and CameraX timestamp path
are not used by this adapter yet. The current 50 ms capture-latency estimate
remains an estimate. A grayscale-only CameraX path would lose the marker colour.

The packaged binaries expose a newer API than the branch's root legacy C++
source. Rebuilding that root source is not a verified reproduction of the
imported binaries.

Windows blocked the imported Windows DLL with Application Control error 4551.
The desktop native probe therefore could not validate the detector. No policy
was changed. Android detection was subsequently checked on the connected Quest.
At 12:02 on 2026-10-08, logs showed IDs 0, 1 and 2 together, approximately
117–121 ms per detection, and startup placement at 72 readings without fallback.
The previous detector measured approximately 320–335 ms. These are sequential
session measurements, not a controlled same-frame benchmark. Visual pose
direction and physical alignment still require the wearer to confirm them.

The installed APK is `build/naret-addon-nano-colour.apk`, version code 37,
version `0.3.35-addon-nano-colour`. Its packaged Android detector was compared
byte-for-byte with the imported library. Calibration was backed up and compared
unchanged after installation. USB speech/CCBM forwarding was restored.

All 24 application suites passed with the native addon excluded from that
desktop test run. Native Windows validation remains blocked; the Android logs
are the evidence for marker detection. Logs are `build/addon-headset.log` and
`build/addon-unit-tests.log`.

## Headset check

### Original stabilizer restoration (version 42)

The merged spatial anchor had instantiated the original filter script without
calling its configuration function, leaving generic defaults and disabling the
rest prior. Version `0.3.40-original-stabilizer` restores the configuration
from `project/avatar_rig_navel.gd`: window 5, position dead zone 20 mm, rotation
dead zone 0.3 degrees, smoothing 1.2 s, prior 2 s, endpoint stability 1.5 mm /
1 degree over 3 detections, and relocation floors 80 mm / 8 degrees. The anchor
keeps a separate rest pose and adopts stable endpoint components as the original
`navel_provider.gd` does. This was checked against the original source, not
confirmed by decompiling yesterday's APK. All 24 app suites pass, including a
stationary 15 mm jitter regression. Marker gizmos intentionally remain raw.

### Wobble follow-up

The explicit lens compatibility transform logged as identity on the Quest:
the suspected old/new lens inversion difference was ruled out. The adapter now
computes compatibility explicitly rather than assuming it.

Logs showed marker subsets alternating between one and three markers, alongside
5–6 cm bias estimates. The viewer gate now holds on incomplete marker evidence,
clears its candidate window, and requires five fresh full-evidence readings
before resuming. This applies to the required marker layout; single-marker
profiles still require just their configured marker. Smoothing thresholds and
the saved calibration are unchanged. This addresses partial-evidence updates;
it does not prove all remaining jitter or physical alignment errors are solved.

That experimental hold and its specific tests were subsequently removed at the
user's request to retain their original gate. The current version code 40 is
`0.3.38-nano-original-gate`; its viewer gate and gate tests are restored to the
pre-experiment behavior. Paul’s native detection remains behind the existing
camera/world-pose adapter. All 24 application suites pass. The paragraph above
describes the superseded version-39 experiment, not the current behavior.

1. Check for native or script errors in logcat after launch.
2. Show the black-and-white markers; enable `debug_prints_enabled` on the
   `ArucoMarkerTracking` node to log `detect_ms` and marker counts.
3. Confirm startup placement, correct head/feet orientation and saved nudge.
4. Move your head around the stationary mannequin and check holding behavior.
5. Check the original compression counter, pace needle and depth display.

Keep the previous full-resolution APK available for rollback. Installing with
`adb install -r` preserves app data; back up and compare calibration around it.
