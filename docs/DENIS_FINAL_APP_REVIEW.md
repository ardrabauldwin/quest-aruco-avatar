# Denis's upstream app versus the final merged app

Reviewed 8 October 2026. Baseline: upstream `origin/main`, commit `9d880a1`
(28 September 2026), from NaReT-Nachbarsprache-wird-reanimiert/naret-xr-app.
Compared against the current working tree and the code used for installed
version 42, `0.3.40-original-stabilizer`. This includes uncommitted and untracked
files; it is not a comparison of two published releases. No changes were pushed.

## Executive assessment

Denis supplied the application architecture, patient/witness presentation,
scenario engine, audio/cloud framework, interface, and feedback infrastructure.
His dependency setup already imported the user's compression/hand-zone code
and `simple_pose_stabilizer.gd`. Those were not invented during this merge.
He also already integrated an external ArUco addon.

The merge changes the headset placement pipeline, connects the original CPR
display, narrows the exercise to one witness without AED, adds English, and
routes reported exercise actions through a new CCBM bridge. Paul's imported
addon supplies the newer detector. The latest fix activates the user's tuned
stabilizer settings and rest-pose policy, which had been missing in the adapter.

Source inspection establishes implementation, not correct behavior on hardware.
All 24 application test suites passed in the latest run, with the Windows-native
detector excluded. The imported Windows DLL is blocked by Application Control.
Android detection was observed previously with all three colored markers.
The latest restored stabilizer still needs the user's stationary/head-motion
check; this review does not claim the entire exercise is finished.

## 1. Composition and ownership — scripts/main.gd

**Before:** constructed Denis's scenario, QCPR manager, EKG, AED, two-witness
director, cloud/audio modules, tracker, interaction, room layout and UI.

**Now:** sets `cpr_witness_only` and `observation_driven`; constructs the CCBM
bridge and observation interpreter; instantiates a single-witness director with
Anna and null second rescuer/AED references. EKG and patient systems remain.
The current startup does not instantiate QCPR manager or the AED object.

The tracker receives the marker-layout profile. On the headset, the spatial
anchor receives the viewer head and the tracker-level temporal filter is
disabled so the anchor owns stabilization. This avoids two filter stages.

Audio recording and playback mute the CPR metronome. English confirmations,
recognized-text display, service status messages, controller nudging, save
actions, witness positioning and accessible training controls are connected here.
Virtual room/floor and colored hand meshes are not installed in the XR flow.

**Review:** this remains the largest integration file. AED/QCPR declarations and
legacy branches remain even though those systems are not instantiated. They are
inactive leftovers, not evidence that real QCPR measurements are connected.
Start requires placement and saved calibration. Exact headset use should be
tested in one complete run rather than inferred from individual functions.

## 2. Scenario — scripts/scenario/scenario_controller.gd

**Before:** deterministic assessment/call/CPR/AED/recovery states, counts and
allowed-action guards. Buttons could submit training actions.

**Now:** adds two policy switches. Witness-only mode rejects AED actions and
bystander-generated treatment events. Observation-driven mode hides routine
clinical progression buttons through `get_interface_actions()` while retaining
setup/reset controls. The original scenario guard still validates actions after
CCBM acceptance. Logging accepts CCBM probability and spoken-report metadata.
The summary identifies the focused exercise as `cpr_single_witness_practice`.

**Review:** AED enums and implementation remain for the broader scenario; they
are excluded in the selected mode. This is a focused CPR exercise, not Denis's
full original AED simulation. Speech confirms reported findings, not physical
technique. Physical compressions remain detector events.

## 3. Witnesses and conversation

### scripts/scenario/bystander_director.gd — unchanged upstream implementation

Denis's original two-witness director remains in the repository. The current
app instantiates a subclass instead, so presence of this file does not mean
Marek or automated bystander compressions are active.

### scripts/scenario/single_witness_director.gd — new

Overrides state/event handling: Anna arrives, urges action after waiting and
responds to accepted responsiveness assessment. Stroke and intent callbacks
do nothing. It never supplies compressions or fetches an AED. It deliberately
reuses the original director's timing/audio infrastructure.

### scripts/ai/llm_orchestrator.gd — modified

Adds English fallback replies, English model prompting/response validation and
a `single_witness` policy. In that mode, AED-fetch replies are suppressed and
the prompt forbids another helper or witness-performed CPR. Its queue and
dialogue-only separation are retained. Generated replies do not advance the
scenario. Calm/thank replies update Anna's emotion, not proof of a learner action.

**Review:** a cloud reply and a prerecorded fallback are different paths.
Arbitrary conversation requires the configured LLM; local ASR alone does not
provide open-ended dialogue. Legacy AED response dictionaries remain but are
filtered in the active mode.

## 4. Microphone, recognition and action interpretation

### scripts/ai/audio_manager.gd — modified

English is accepted throughout recording/playback. An empty capture buffer now
returns zero level instead of retaining a stale loud value; this prevents a
silence timer from being continually reset by old samples. Recording does not
restart an already-playing microphone stream. An unscripted missing clip does
not substitute an unrelated Anna calming line. Original microphone capture,
voice activation, playback queue and prepared-clip support remain.

### scripts/api/uni_api_client.gd — modified

Adds optional local ASR at `http://127.0.0.1:8767/inference`, a separate request
with a 30-second timeout, no cloud credentials, no redirects and English
transcription support. Denis's cloud completion/TTS/authentication framework
remains. The local route is a USB-forwarded development deployment, not an
independent speech recognizer running inside the Quest.

### scripts/scenario/spoken_observation.gd — new

Normalizes speech and maps bounded statements/requests to structural action
codes. Supports selected multi-sentence forms around a finding; does not mean
every wording or pace is accepted. Speech cannot create a compression stroke.

### scripts/scenario/speech_confirmation.gd — new

English-only pending proposals last 30 seconds and are bound to the current
scenario context. Yes/no applies only to an explicit pending proposal. A small
list handles observed transcription mistakes and tentative statements. It is
not a general fuzzy-match acceptance engine.

### scripts/ai/observation_interpreter.gd — new

For speech not handled by bounded matching, asks the configured LLM for an
action, kind, result and verbatim supporting evidence. Validates the schema,
evidence substring and expected result. Questions, intentions, ambiguous or
contradictory statements cannot silently become completed treatment actions.
Conversation is sent onward to Anna's dialogue system.

**Review findings:** the interpreter has one in-flight request; speech arriving
while busy gets clarification, not a queued interpretation. Without a configured
LLM, unfamiliar wording receives clarification. English confirmation behavior
is not mirrored completely in German/Polish. Recognition at different speaking
rates and interruption during playback still needs recorded headset validation.

## 5. CCBM — new, not part of Denis's baseline

### scripts/scenario/ccbm_bridge.gd

Sends structural observation history to an external worker. Requires a response
identifying engine `ccbm`, the requested action and a finite probability at
least 0.90. Then checks the action is still allowed by Denis's scenario. One
request is allowed at a time; history is limited to 256 observations. Reset
invalidates old responses. It records compression onset from accepted tracked
strokes rather than sending every stroke over HTTP. Reported ventilation is
still a spoken claim. Start does not require CCBM inference.

### integrations/ccbm/d.pddl, p.pddl, d-observations.cpp, server.py

Added behavior model/problem/observation code and HTTP wrapper around the
compiled CCBM worker on the PC/Linux runtime. The bridge is not itself the
inference engine. Repeated breathing observations represent first/second breath
in the model. Local speech/CCBM forwarding is configured by development tools.

**Review:** 0.90 is explicitly a prototype policy, not a threshold selected by
data-driven validation. Endpoint/model availability and accepted exercise
transitions must be checked during a full run. CCBM cannot prove a physical
breath, correct hand position or correct airway maneuver from a spoken report.

## 6. Tracking, marker combination and placement

### scripts/tracking/aruco_tracker.gd — modified Denis adapter

Adds profile loading and marker combination, used-marker evidence reporting
and a switch for temporal filtering. Preserves marker size/ID configuration,
tracking status and desktop preview. Chooses the migrated camera provider in
the XR path. Combining markers uses the exact newest detection result, not
unrelated stale poses. Unrecognized IDs are ignored by the layout.

### scripts/tracking/user_camera_provider.gd — new adapter from original approach

Retains CameraServer capture, background detection and capture-time head-pose
world conversion. Uses the imported detector's `detect_markers()` when present,
explicitly selects 4x4/50, passes configured physical marker sizes and retains
the existing intrinsics. Identity head pose is passed to detection; the saved
head transform is applied once. Old API fallback remains.

The explicit lens compatibility correction logged as identity on the headset:
the suspected inverse difference was ruled out. Diagnostic PNG saving is off.
Detection timing is periodically logged. Camera latency remains a fixed 50 ms
estimate; the addon's accurate CameraX timestamp path is not integrated here.

### scripts/tracking/colored_camera.gdshader — new

Combines luminance/chroma camera textures and classifies blue to white and
orange to black before detection. Full-resolution processing remains enabled
for colored markers. Lighting, printing and color thresholds can still affect
detection; this is not proof that all resolutions were optimized.

### scripts/tracking/colored_marker_image.gd — new

CPU fallback for non-GPU images, with RGB hue classification and luminance
fallback handling. Unit tests cover mapping and image handling; these are not
a hardware lighting benchmark.

### scripts/tracking/marker_layout.gd — added during migration

Loads calibrated marker-to-common transforms and a common-to-sternum bridge.
Each visible marker reconstructs the same anchor; translations are averaged
and sign-aligned quaternions combined. Reports position spread. Optional floor
orientation removes pitch/roll; it does not place the mesh bottom on the floor.

### scripts/tracking/startup_placement.gd — added during migration

Robust coordinate-median position and measured rotation medoid. Starts checking
after 30 independent readings, at three-reading checkpoints, with 1.5 mm /
1-degree estimate stability; four stable comparisons permit earliest acceptance
at 42 readings. A 100-reading fallback exists. Faster detection changes the
wall-clock duration of observation-count rules.

### scripts/tracking/viewer_motion_gate.gd — migrated original gate

Holds during head movement using a 0.3 s head window, 0.15 m/s and 20 degrees/s,
then 0.5 s settling. Five readings learn viewpoint bias within 10 cm AND
10 degrees. Small updates are held beyond 1.8 m; a 30 cm OR 25-degree change
with three full-evidence detections has an override. These heuristic constants
were retained, not newly proved optimal by this review. The experimental blanket
partial-marker hold was removed at the user's request.

### scripts/tracking/spatial_anchor.gd — modified Denis placement

Denis's original one-marker 1.5 s settling/mean path remains for desktop.
The headset uses the robust startup and viewer gate. Model offset and save/load
compatibility remain. Adds floor reference/geometry handling, model orientation,
opacity persistence, height preservation and explicit reposition resets.

Version 42 finally configures the original filter: window 5, position dead zone
20 mm, rotation dead zone 0.3 degrees, smoothing 1.2 s, prior 2 s; stable endpoint
checks 1.5 mm / 1 degree over 3 observations and relocation floors 80 mm /
8 degrees. A separate remembered rest pose is used and stable components can
re-anchor independently. Earlier statements that the script's presence meant
the full original policy was active were incomplete.

### scripts/tracking/marker_pose_gizmo.gd — new diagnostic

White marker-center dot, labeled ID and 5 cm RGB axes on raw world marker poses,
before patient/layout offsets. Hides after 500 ms without detection. Depth-test
bypass keeps it readable through the patient. Raw gizmo jitter is intentional.

### scripts/tracking/openxr_setup.gd / room_layout.gd — modified

Adds floor-height helpers respecting active tracking spaces, reference transforms
and live tracked room-anchor positions. Original XR/scene integration remains.
`room_anchor.gd` itself is unchanged.

**Review:** three issues should not be conflated: marker pose alignment, mesh
alignment offset, and stationary smoothing. A floor orientation constraint is
also different from physical mesh-floor contact. Current gate heuristics and
50 ms camera timing can still cause viewpoint-dependent shifts. Real movement,
occlusion and rest reacquisition need hardware checks without inventing offsets.

## 7. CPR and hand/controller interaction

### scripts/tracking/xr_interaction.gd — modified

Denis already instantiated the upstream hand-zone/stroke detector. Changes now
attach the original CPR HUD to the XR camera; use its BPM interval source rather
than a separate adapter calculation; retain the original zone dimensions; enable
metronome except while audio is busy; reset the 0–30 practice count for a new
cycle. The standalone automatic breathing-pause scheduler stays disabled because
the scenario owns the breathing events.

The practice display/zone appears after patient placement, but only CPR-stage
strokes receive exercise credit. Adds controller trigger menu clicks while
retaining hand pinch/poke input. Controllers do not generate physical CPR counts.

### addons/naret_upstream/avatar/*

`cpr_hand_zone.gd/.tscn`, `cpr_motion_session.gd`, `cpr_metronome.gd` and the
target guide originated in the user's project and were already dependencies of
Denis's application. `cpr_feedback_hud.gd` was brought into this runtime for the
original 0–30 count, pace needle, depth bar and coaching. The stabilizer script
matches the original project; the important latest change is its configuration
and rest-pose use in the spatial anchor.

**Review:** depth is hand excursion, not measured mannequin compression depth.
Speech cannot add compression counts. The existing sensor modules would need
real hardware/plugin connection for verified depth/recoil/ventilation data.

## 8. Patient model, transparency and animation

### scripts/mannequin/mannequin_controller.gd — modified

Adds optional anatomical fitting, resized mouth/forehead targets and neutral
gesture landmarks. Fit dimensions default to zero; scene model scale is 0.9.
Therefore the presence of fitting code does not establish a measured mannequin
match. Preserve the actual physical torso dimensions when assessing fit.

Adds body overlay materials using `assets/patient_overlay.gdshader`; head region
stays solid to avoid seeing teeth/eyeballs through facial skin. Body opacity
uses a 4x4 screen-space coverage mask instead of layered alpha blending. Pallor
updates preserve material alpha. A pattern can remain visible, especially in XR.

**Important exact difference:** current head-tilt limits are 10 degrees neck and
10 degrees head. Denis's baseline uses 28 and 20. These values are not the same,
even though earlier conversation discussed retaining Denis's angles.

### scripts/tracking/head_tilt_gesture.gd — new

Two separate tracked hands: forehead palm within 6 cm, other index tip within
4.5 cm of chin; 0.35 s positioning; coordinated movement within 2 s, sustained
0.12 s; 0.25 s lost-tracking grace. Limits are provisional. It triggers animation
only and does not score or confirm actual airway opening. Replaces Denis's
one-palm-within-10-cm trigger.

### Other mannequin scripts — unchanged

AED device, breathing system, bystander controller, heart system, pupil system,
ragdoll and rig animator retain upstream implementations. Whether each is active
depends on composition. AED code remains inactive in the focused exercise;
retained physiological displays are simulations, not sensed patient physiology.

## 9. Languages and interface

### scripts/ai/language_manager.gd — modified

Adds English scenario/action lines and UI translation mapping, three-language
selection and some English communication intents. Denis's DE/PL content remains.
Missing UI translation keys fall back to German, so full English coverage is not
guaranteed merely by selecting EN.

### scripts/ui/hand_menu.gd — modified

Larger direct training, language, microphone and voice-test controls alongside
the wrist-menu infrastructure. Uses observation-driven action lists. Language
and active-state feedback turn green; momentary actions flash rather than
remaining selected. Some visible strings remain English regardless of language.

### scripts/ui/calibration_panel.gd — modified

Retains XYZ and Euler rotation preview through the model offset, preserves scale,
and gates saving on startup placement. Removed marker geometry, scan visibility
and model-scale controls. Later requests added language/start/audio/microphone
controls outside scrolling, plus body transparency and floor adjustment fields.
It is therefore broader than the earlier requested minimal six-field panel.
Close keeps preview; Save writes it. Y controls can be disabled when floor locked.
Hard-coded English messages need localization review.

### scripts/ui/info_panel.gd — modified

Adds next-step/example phrases and hand-compression display. Helps the learner
understand expected observations instead of requiring hidden action buttons.
Remaining literal English strings require DE/PL checks.

### scripts/ui/dashboard.gd — modified

Adds EN selection and localized labels, hides QCPR simulator button, uses
observation-driven available UI actions and labels hand depth as an estimate.
Desktop/simulation utilities remain; their presence is not headset sensor support.

### scripts/ui/briefing_panel.gd — modified

Skips missing-AED feedback in witness-only mode, adapts the final advice for that
scenario and routes localization through the language helper. This file changes
what is displayed; it does not replace the scoring or session-log engine.

## 10. Feedback, EKG, QCPR and utilities retained from Denis

`score_tracker.gd` and `session_logger.gd` are unchanged upstream. The input events
and scenario metadata are extended, so their output can differ even without
editing the files. Full results should be checked for a no-AED, speech-report
session. Numeric verified-quality scores must not imply measured chest depth.

`ekg_system.gd` and `ekg_renderer.gd` are unchanged. `performance_monitor.gd` is
unchanged. The QCPR backend, real BLE adapter, constants, packet parser, manager,
simulated backend and QCPR debug panel are unchanged source; current main does
not start their runtime. Native BLE availability is a separate integration task.

## 11. Remaining work, in practical order

### Scene, addon and build changes outside scripts/

- `scenes/main.tscn`: selects `data/user_marker_layout.cfg`, supplies the default
  180-degree X model orientation, and removes the AED and Marek scene instances.
  This is an actual scene change, not just hiding their buttons.
- `scenes/mannequin.tscn`: sets the human model scale to 0.9. Saved model offsets
  can add their own transform, so the scene scale alone is not a torso measurement.
- `assets/patient_overlay.gdshader`: new opaque-depth coverage shader with a solid
  head region; discussed in section 8.
- `addons/opencv_aruco`: imported from Paul's `addon-port` branch, commit
  `729f8c0`, with new packaged native libraries/API and export guard. It is a
  selective addon port, not replacement of Denis's whole project. Its standalone
  timestamped CameraX tracker is not the active camera provider.
- `project.godot`: the OpenCV editor-plugin section was moved; comparison with
  this baseline does not show a new XR-reference-space policy in this file.
- `export_presets.cfg`: installed build identifies as code 42,
  `0.3.40-original-stabilizer`; application package remains the same so replace
  installation preserves user data.
- English script/audio and service setup tools are additions. Service settings
  are runtime/device configuration, not evidence that all required servers are
  bundled in the APK. No credential values are included in this review.

### Validation still required

1. Confirm the latest patient stabilization on a stationary mannequin, head
   movement, partial marker loss and restart. Compare patient versus raw gizmos.
2. Confirm saved model fit/nudge and floor-height behavior after restarting and
   XR recentering; do not compensate a camera-pose defect with a model offset.
3. Decide whether to retain the current 10+10-degree visual animation or restore
   Denis's 28+20-degree animation; test its direction on the actual rig.
4. Run one full English exercise with natural speech, interruptions, two breaths,
   compression cycle, handover and debrief. Log ASR, CCBM and scenario decisions.
5. Repeat in German/Polish; review translated UI, audio availability and fallback
   behavior. Current English confirmation support is more extensive.
6. Decide the deployment model: USB-connected PC ASR/CCBM is development mode.
   Independent headset deployment needs reachable services or another runtime.
7. Validate any desired real mannequin measurements via sensors/BLE. Do not label
   hand excursion or spoken breaths as verified physical measurements.
8. Clean up inactive AED/QCPR branches only after reviewing the intended future
   scope, then produce a reviewable commit/PR. Local changes are not automatically
   incorporated into Denis's GitHub repository.

## File inventory

The following inventory compares each runtime script with the baseline Git blob,
normalizing Windows/Unix line endings. Changed files may include comments/formatting, not
only behavioral differences. Unchanged files retain source but can be called
with different settings or inputs. Godot `.uid` sidecars are omitted.

<!-- generated runtime inventory -->

51 runtime script/shader files: 17 changed, 13 added, 21 unchanged after normalizing line endings.

| Runtime file | Compared with Denis's baseline | Lines |
|---|---|---:|
| [scripts/ai/audio_manager.gd](../scripts/ai/audio_manager.gd) | Changed | 386 |
| [scripts/ai/language_manager.gd](../scripts/ai/language_manager.gd) | Changed | 260 |
| [scripts/ai/llm_orchestrator.gd](../scripts/ai/llm_orchestrator.gd) | Changed | 142 |
| [scripts/ai/observation_interpreter.gd](../scripts/ai/observation_interpreter.gd) | Added | 76 |
| [scripts/api/uni_api_client.gd](../scripts/api/uni_api_client.gd) | Changed | 219 |
| [scripts/ekg/ekg_system.gd](../scripts/ekg/ekg_system.gd) | Unchanged | 71 |
| [scripts/feedback/score_tracker.gd](../scripts/feedback/score_tracker.gd) | Unchanged | 59 |
| [scripts/feedback/session_logger.gd](../scripts/feedback/session_logger.gd) | Unchanged | 64 |
| [scripts/main.gd](../scripts/main.gd) | Changed | 856 |
| [scripts/mannequin/aed_device.gd](../scripts/mannequin/aed_device.gd) | Unchanged | 547 |
| [scripts/mannequin/breathing_system.gd](../scripts/mannequin/breathing_system.gd) | Unchanged | 44 |
| [scripts/mannequin/bystander_controller.gd](../scripts/mannequin/bystander_controller.gd) | Unchanged | 218 |
| [scripts/mannequin/heart_system.gd](../scripts/mannequin/heart_system.gd) | Unchanged | 68 |
| [scripts/mannequin/mannequin_controller.gd](../scripts/mannequin/mannequin_controller.gd) | Changed | 312 |
| [scripts/mannequin/pupil_system.gd](../scripts/mannequin/pupil_system.gd) | Unchanged | 23 |
| [scripts/mannequin/ragdoll.gd](../scripts/mannequin/ragdoll.gd) | Unchanged | 383 |
| [scripts/mannequin/rig_animator.gd](../scripts/mannequin/rig_animator.gd) | Unchanged | 379 |
| [scripts/qcpr/qcpr_backend.gd](../scripts/qcpr/qcpr_backend.gd) | Unchanged | 69 |
| [scripts/qcpr/qcpr_ble_real_backend.gd](../scripts/qcpr/qcpr_ble_real_backend.gd) | Unchanged | 168 |
| [scripts/qcpr/qcpr_constants.gd](../scripts/qcpr/qcpr_constants.gd) | Unchanged | 179 |
| [scripts/qcpr/qcpr_manager.gd](../scripts/qcpr/qcpr_manager.gd) | Unchanged | 195 |
| [scripts/qcpr/qcpr_packet.gd](../scripts/qcpr/qcpr_packet.gd) | Unchanged | 259 |
| [scripts/qcpr/simulated_manikin_backend.gd](../scripts/qcpr/simulated_manikin_backend.gd) | Unchanged | 478 |
| [scripts/scenario/bystander_director.gd](../scripts/scenario/bystander_director.gd) | Unchanged | 498 |
| [scripts/scenario/ccbm_bridge.gd](../scripts/scenario/ccbm_bridge.gd) | Added | 120 |
| [scripts/scenario/scenario_controller.gd](../scripts/scenario/scenario_controller.gd) | Changed | 371 |
| [scripts/scenario/single_witness_director.gd](../scripts/scenario/single_witness_director.gd) | Added | 25 |
| [scripts/scenario/speech_confirmation.gd](../scripts/scenario/speech_confirmation.gd) | Added | 48 |
| [scripts/scenario/spoken_observation.gd](../scripts/scenario/spoken_observation.gd) | Added | 70 |
| [scripts/tracking/aruco_tracker.gd](../scripts/tracking/aruco_tracker.gd) | Changed | 207 |
| [scripts/tracking/colored_camera.gdshader](../scripts/tracking/colored_camera.gdshader) | Added | 28 |
| [scripts/tracking/colored_marker_image.gd](../scripts/tracking/colored_marker_image.gd) | Added | 27 |
| [scripts/tracking/head_tilt_gesture.gd](../scripts/tracking/head_tilt_gesture.gd) | Added | 90 |
| [scripts/tracking/marker_layout.gd](../scripts/tracking/marker_layout.gd) | Added | 104 |
| [scripts/tracking/marker_pose_gizmo.gd](../scripts/tracking/marker_pose_gizmo.gd) | Added | 42 |
| [scripts/tracking/openxr_setup.gd](../scripts/tracking/openxr_setup.gd) | Changed | 70 |
| [scripts/tracking/room_anchor.gd](../scripts/tracking/room_anchor.gd) | Unchanged | 7 |
| [scripts/tracking/room_layout.gd](../scripts/tracking/room_layout.gd) | Changed | 178 |
| [scripts/tracking/spatial_anchor.gd](../scripts/tracking/spatial_anchor.gd) | Changed | 357 |
| [scripts/tracking/startup_placement.gd](../scripts/tracking/startup_placement.gd) | Added | 99 |
| [scripts/tracking/user_camera_provider.gd](../scripts/tracking/user_camera_provider.gd) | Added | 434 |
| [scripts/tracking/viewer_motion_gate.gd](../scripts/tracking/viewer_motion_gate.gd) | Added | 156 |
| [scripts/tracking/xr_interaction.gd](../scripts/tracking/xr_interaction.gd) | Changed | 466 |
| [scripts/ui/briefing_panel.gd](../scripts/ui/briefing_panel.gd) | Changed | 149 |
| [scripts/ui/calibration_panel.gd](../scripts/ui/calibration_panel.gd) | Changed | 219 |
| [scripts/ui/dashboard.gd](../scripts/ui/dashboard.gd) | Changed | 364 |
| [scripts/ui/ekg_renderer.gd](../scripts/ui/ekg_renderer.gd) | Unchanged | 31 |
| [scripts/ui/hand_menu.gd](../scripts/ui/hand_menu.gd) | Changed | 773 |
| [scripts/ui/info_panel.gd](../scripts/ui/info_panel.gd) | Changed | 111 |
| [scripts/ui/qcpr_debug_panel.gd](../scripts/ui/qcpr_debug_panel.gd) | Unchanged | 217 |
| [scripts/utils/performance_monitor.gd](../scripts/utils/performance_monitor.gd) | Unchanged | 34 |
