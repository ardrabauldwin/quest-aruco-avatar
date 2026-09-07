# CPR hand placement feedback

`AvatarRig/mannequin/CPRHandZone` follows the mannequin's held or tracked pose.
The default is **guide-only mode** (`guide_only = true`): a constant green target ring
with an open centre, a small centre dot, and a stacked-hands illustration beside it.
The instruction reads **Hand heel here / Other hand on top**.
Green indicates where to place the lower hand's heel, not measured
correctness. No hand tracking is read and no placement approval is emitted in this mode.
The ring, illustration, and instruction hide together on Start and return together on reset.
The circular ring is about 4.7 cm across at the mannequin's scale; the experimental
detector retains its rectangular footprint. The illustration faces the viewer and sits
beside the ring, not over the contact point.

- Right-controller **B** starts CPR and hides the guide; **B** again resets it.
- Desktop **C** performs the same toggle.
- A future exercise controller can call `start_cpr()` directly.

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
- A future compression detector can call `start_cpr()`; entering the zone does not start CPR.

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
The wrist-to-palm length must be 15–120 mm; missing/invalid data fails the check.

Either hand can be lower. Its estimated heel must be in the thin contact slab.
The upper estimated heel must be 12–60 mm above it along the chest normal, with at most
25 mm sideways displacement. Both palm-facing normals must point toward the chest
within 40 degrees. These are editable prototype tolerances, not clinical thresholds.
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
