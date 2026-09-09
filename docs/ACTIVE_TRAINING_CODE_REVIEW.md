# Active training code review - 2026-09-08

Scope: the active Godot training path, its avatar/ArUco filter connection, and regression/edge simulations. This is not headset validation or an exhaustive audit of third-party/native dependencies. No runtime changes were made during this review.

## Current runtime rules

- `project.godot` selects `main_3d.tscn`. The scene uses `avatar_rig_navel.gd`, `simple_pose_stabilizer.gd`, `navel_provider.gd`, and `cpr_hand_zone.gd`.
- `main_3d.gd` submits camera images to a detection worker and places marker nodes using the camera transform associated with the image. The native processor detects ArUco markers and estimates poses. Calibrated marker poses feed the avatar filter.
- Avatar filtering uses a five-detection medoid window, 20 mm position / 0.3 degree rotation dead zones, 1.2 s smoothing and a 2 s rest prior. These are avatar settings, not hand-motion smoothing. The avatar holds through marker loss and collects fresh rest data after application resume.
- Motion requires an actively tracked palm position, not palm orientation or wrist tracking. Controller-inferred hands and stale/invalid positions are rejected. A palm must lie within 8 cm laterally/longitudinally of the chest target and between -12 and +15 cm along its normal.
- On acquisition, choose the higher palm along the chest normal if both are usable; otherwise use the single usable palm. Keep the current hand while usable. Automatically switch when it becomes unusable and another palm is usable. Switches preserve counts and cycle progress, but discard the unfinished stroke and establish a fresh baseline.
- The measured point is the OpenXR palm joint centre, not the skin surface. Height is its projection relative to the chest target along the chest normal, corrected for XR scale. Travel is starting height minus deepest sampled height.
- A stroke begins after more than 4 mm downward movement. It counts on return to within 10 mm of the top, with at least 6 mm rise from the bottom, only if excursion was at least 50 mm. Excursions above 120 mm are discarded. Thus counting and depth qualification are still coupled.
- Slow feedback is a 0.70 s threshold on stroke duration or time since the last count. It says Press faster and never clears the count. There is no measured BPM calculation, interval average, or too-fast feedback.
- Invalid tracking, hand changes, a frame longer than 250 ms, application pause, and chest-pose jumps discard incomplete motion. Chest-pose jumps are over 30 mm translation or 5 degrees rotation per frame; smaller reference movement can still affect estimated travel.
- Beeps run at a 110 BPM target independently of motion while the visible practice zone is available. They continue through hand occlusion, stop during app pause and the breathing phase, and do not determine whether a stroke counts. Tone is 880 Hz, 90 ms, -3 dB on Master.
- First accepted stroke auto-starts the exercise. Explicit start/reset uses the configured right-controller button or desktop C. After 30 counted strokes the app shows a five-second breathing practice timer, then sets the next set to zero; lifetime total is retained. No breaths are detected.
- Placement grading separately uses wrist/palm orientation, an estimated heel/contact box and stack checks. It colours the existing symbol but does not gate motion counting. The symbol hides after start.

## Findings

1. **Counting threshold misses borderline movements.** Eight synthetic 50 mm cycles produce zero counts at 72/90 Hz; 55 mm cycles produce eight. Discrete samples fall below the strict threshold. Four-centimetre presses are not counted, despite the proposed separation of repetition count from quality feedback.
2. **Tracking spike creates a false press.** A single-frame 55 mm downward jump followed by a return produces one count. There is no hand-position spike rejection/minimum duration check.
3. **Pace feedback is incomplete.** Synthetic 90 BPM and 150 BPM runs both finish with Follow the beep. The agreed immediate per-press feedback and four-interval average are not implemented.
4. **Depth display can show an old result.** A 55 mm press followed by a 40 mm press leaves the stored result at approximately 55 mm, because only counted strokes update it. The HUD also takes the maximum of current travel and the previous result. This can hide a shallower subsequent press.
5. **Observed tracking is required.** A missing frame or hand change can lose the incomplete repetition. Count preservation is implemented; perfect uninterrupted counting through missing observations is not.
6. **Requested UI is pending.** Green Place hands here text, a needle/BPM speedometer, and red/green depth bands are recorded requirements, not current UI behavior. The current bar is cyan and the original placement symbol remains.
7. **Physical depth/contact is unvalidated.** Palm travel and the experimental placement check do not verify chest compression depth or real contact. Avatar-reference motion may influence the estimate.

## Evidence and limits

- Latest automatic-hand-switching integration tests passed before the latest APK export: both hand orders, two hand spacings, two XR scales, switch directions, count retention, fresh-reference travel and resumed counting.
- Counter regression tests passed in the preceding implementation work; the edge audit deliberately exposes the remaining weaknesses above.
- `tests/audit_cpr_motion_edges.gd` rerun during this review reproduced threshold misses, spike counts, incomplete recoil/gap rejection, pace-feedback gaps and stale depth.
- `tests/test_filter_rest_flow.gd` rerun during this review passed.
- Desktop Godot reports the existing missing Windows OpenCV extension. Synthetic tests do not validate live camera detection. No on-device hand tracking, audio audibility or depth-accuracy verification has been performed for these new APKs.
