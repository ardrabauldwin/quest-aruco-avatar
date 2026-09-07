# CPR hand placement feedback

`AvatarRig/mannequin/CPRHandZone` follows the mannequin's held or tracked pose.
The default is **guide-only mode** (`guide_only = true`): a constant green ring with
an open centre and a small centre dot. The hand illustration is removed; the label
**Place hand heel here / Other hand on top** sits just above the ring on the chest plane.
Green indicates the intended heel target, not measured correctness.
The ring and label hide after two completed practice strokes and return on reset. The target
centre is unchanged. The visual ring is enlarged from about 4.7 to 7.4 cm across at mannequin
scale for visibility; this does not enlarge the experimental contact box or counting bounds.
Place the lower hand's heel at the centre; the entire hand does not need to fit inside the ring.

Hand motion is read separately when `enable_motion_practice` is enabled (the default).
Motion counting now needs only an actively tracked palm position; it does not require
wrist tracking, palm orientation, or the stricter experimental heel-placement check.
Controller-inferred hands and stale palm positions are still rejected. A missing wrist
therefore no longer blocks the motion counter. Tracking a palm's movement does not imply
using the palm centre as the intended chest contact point: the ring remains a heel guide.

The HUD distinguishes missing trackers, controller-based input, unavailable hands,
and tracked hands outside the target region. Changes are logged with the `CPR hands:`
prefix for on-device diagnosis. The app uses the real-world camera passthrough to show
hands; no virtual hand mesh is included. Not seeing a rendered hand model does not itself
mean that joint tracking is unavailable.

- Right-controller **B** starts CPR and hides the guide; **B** again resets it.
- Desktop **C** performs the same toggle.
- A future exercise controller can call `start_cpr()` directly.

## Hand-tracking practice feedback (no mannequin sensors)

The app estimates motion of one tracked hand near the chest, along the chest normal and
relative to the avatar's current chest surface. It keeps the same hand while it remains
usable and can fall back to the other hand when it disappears. Changing hands, tracking
loss, app pauses, large avatar pose jumps, and long frame stalls discard unfinished strokes.
Counts cannot bridge those gaps. Existing counts remain; the HUD reports unavailable tracking.

The detector uses peak-to-trough travel and return toward the starting height, not a per-frame
5 mm velocity threshold. Two repeated complete strokes start the practice session and count
as its first two strokes. Prototype minimum travel is 15 mm, minimum stroke time 0.20 seconds,
and minimum spacing 0.25 seconds. These thresholds filter noise; they are not CPR quality criteria.
Movement over 12 cm or lasting more than 1.5 seconds invalidates an unfinished stroke.

The camera-attached HUD shows `12 / 30`, a cyan **Estimated hand travel** bar (0–8 cm display
range), and the configured pacing BPM. This is NOT measured chest depth: optical tracking cannot
prove contact, pressure, recoil, or compression of the mannequin. Repetitive hovering near the
target may still look like strokes. Do not interpret a counted stroke as a correct compression.

After 30 estimated strokes, the HUD prompts two breaths and runs the requested configurable
five-second **practice pause timer**, then resets the counter for the next cycle. This timer
does not detect or verify breaths. It continues if hands leave view, but freezes when the app
is paused or the avatar's world placement is unavailable.

The metronome generates a 55 ms, 880 Hz PCM tone through `AudioStreamPlayer`, paced independently
at 110 BPM by default (configurable 100–120). It runs during the active compression phase even
if hands briefly disappear, stops during breathing/app pause, and never creates counts.
Missed beats after a long frame are skipped rather than played in a burst.

`cpr_motion_session.gd` owns stroke/cycle timing, `cpr_feedback_hud.gd` owns the headset display,
and `cpr_metronome.gd` generates the tone. `test_cpr_motion_session.gd` tests 30/72/90 Hz synthetic
strokes, auto-start, jitter, gaps, 30-stroke cycles, breathing timers, and independent BPM timing.
`test_cpr_hand_zone.gd` also tests the XR joint-to-motion integration, continued counting after
start, PCM creation, and HUD values. This has not yet been validated on the Quest/mannequin.

## Experimental detector (off by default)

For development tests only, set `guide_only = false` before the node enters the scene tree.
This retains the experimental heel estimator for later validation; the main scene uses
the constant green guide. The remainder of the detector description applies only to this
opt-in mode.

The invisible `CollisionShape3D` box defines a thin heel-contact slab at the chest surface.
The script checks an estimated lower-hand heel in that box's local coordinates directly;
physics layers and overlap signals are intentionally unused.

- Orange: heel contact or the estimated two-hand stack fails, or required joints are untracked.
- Green: either hand's estimated heel is on the target, the other estimated heel is above it,
  their sideways separation is small, and both palms face the chest.
- Right-controller **B** starts CPR and hides the highlight; **B** again resets placement.
- Desktop **C** performs the same toggle.
- `start_cpr()` can also be called explicitly; entering the zone alone does not start CPR.

The source is the OpenXR left/right hand tracker, not the existing controller grip nodes.
Controller-inferred joints are rejected. Unknown tracking sources are accepted only with
valid, actively tracked wrist/palm positions and palm orientation. Tracking loss clears
placement immediately. Overlapping hands can occlude the lower hand; this needs headset testing.

## Heel estimate and stack check

OpenXR has wrist and palm joints but no heel-of-hand contact joint. For each hand,
the prototype estimates a point 30% of the way from wrist centre to palm centre,
then offsets it 8 mm toward the palm skin using the tracked palm orientation.
Godot's OpenXR Humanoid conversion defines +Z toward that palm-facing side.
The joint transforms are adjusted for XR reference frame and world scale, then
transformed through `XROrigin3D` into scene coordinates.

The 30% fraction and 8 mm skin offset are tunable estimates; they have not been fitted
to measured hand anatomy. They are exposed under `Heel estimate` on the zone instance.
The wrist-to-palm length must be 10–150 mm; missing/invalid data fails the check.

Either hand can be lower. Its estimated heel must be in the thin contact slab.
The upper estimated heel must be 8–80 mm above it along the chest normal, with at most
35 mm sideways displacement. Both palm-facing normals must point toward the chest
within 50 degrees. These are editable prototype tolerances, not clinical thresholds.
This evaluates approximate heel-over-heel geometry; it does not verify physical contact,
finger interlocking, pressure, or compression quality.

`correct_placement` now represents this full check. `lower_hand` reports `left`, `right`,
or an empty string when incorrect. `left_hand_inside`/`right_hand_inside` now indicate
individual heel contact with the chest slab; both do not need to be true.

## Target location

The refined zone centre is `(0, 0.127, 0.12)` in mannequin-local coordinates. Inspection
of the actual textured GLB shows this on the chest midline, above the visible V-shaped
lower rib junction (approximately Z=0.18). The footprint spans X=-0.04 to +0.04 and
Z=0.085 to 0.155. These visible surface landmarks are estimates, not segmented bones;
they do not establish the exact sternum or xiphoid boundaries.

The sampled central chest surface at Z=0.12 is Y=0.05883. The highlight sits at
Y=0.062, approximately 2.4 mm above that surface after the mannequin's scale is applied.
Its patch is flat, so separation varies slightly across the curved chest.
This is model-based placement, not a validated anatomical calibration.
Check it against the real mannequin's target.
Adjust the instance position in `main_3d.tscn`, and the box/quad sizes in
`cpr_hand_zone.tscn`. The mannequin's 0.77 scale makes the refined zone about
6.2 cm wide, 5.4 cm along the chest, and 2 cm deep (about ±1 cm around the surface).
The upper hand is evaluated relative to the lower hand, not inside this slab.
These are prototype tolerances, not dimensions prescribed by CPR guidance.
The old footprint was about 10 by 10 cm; its centre along the chest was retained.
Green indicates the estimated heel/stack geometry passes; it is not clinically verified
hand placement. The chest landmark and hand-contact estimates both need on-device validation.

Run `python tools/inspect_cpr_target.py` from the repository root to reproduce the
textured front-view review in `builds/cpr_target_model_front.png`. The script renders
mesh triangles and embedded texture and samples surface height; it does not identify
anatomical landmarks automatically.

The highlight is excluded from avatar tinting and floor-contact geometry.
The existing CSV recording A/X/Y controls are unchanged. No compression depth, rate,
or CPR quality is inferred by this feature.

Run `res://tests/test_cpr_hand_zone.gd` with Godot headless and XR disabled to check
transformed contact, either lower hand, heel-versus-palm placement, stacking separation,
palm facing direction, missing wrist/orientation data, tracking loss, XR origin/world scale,
pause/resume, and start/reset. These are synthetic geometry tests, not headset validation.

API references: [XRHandTracker](https://docs.godotengine.org/en/stable/classes/class_xrhandtracker.html),
[XRPose](https://docs.godotengine.org/en/stable/classes/class_xrpose.html), and the
[Godot OpenXR hand conversion](https://github.com/godotengine/godot/blob/master/modules/openxr/extensions/openxr_hand_tracking_extension.cpp).
