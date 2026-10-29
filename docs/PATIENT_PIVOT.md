# Patient pivot at the compression point

The `Mannequin` node's origin is its `Sternum` compression point. The scene
moves the patient node to the existing scene landmark and subtracts that shift
from each spatial child. Geometry and interactions therefore keep their world
positions. The GLB, anatomical landmark and physical calibration are unchanged.

`BodyFrame` is an explicit datum for coordinates authored before this refactor:
patient footprints, the whole-body contact envelope and AED pad poses. They use
`get_body_transform()` rather than assuming the patient pivot is on the floor.
It is a body-coordinate datum, not a measured floor or a second chest landmark.

Bystanders use the existing body-relative X/Z footprint, and their standing
height comes from the accepted floor reference. The patient's manual height
nudge no longer raises or lowers standing bystanders in fallback placement.
Room geometry and clearance selection are unchanged. The AED prop's home is
still stored relative to its own existing parent; this refactor changes its
electrode target calculation to use BodyFrame, not its carrier/home behaviour.

Chest-thickness fitting can move the sternum. After fitting, the patient node
is rebased to the new sternum while all child world transforms and cached local
face targets are compensated. The heart's thickness calculation uses BodyFrame
as its baseline. This prevents flatten/shift changes from shifting the heart or
leaving the patient pivot away from the compression point.

Saved marker-to-patient calibration belongs to SpatialAnchor, whose coordinate
frame does not move in this refactor. No additional calibration migration or
rewrite is required. The preceding patient-axis migration remains separate.

The pre-change regression fixture records default floor contact, measured-chest
shift and flatten modes. Tests compare model, heart, scan, sternum, face zones,
AED pad targets, exclusion footprints and whole-body contact decisions against
those prior world-space values. They also assert that bystander height uses the
floor and that the pivot remains at the sternum during thickness changes.
These tests establish coordinate preservation; headset validation is still
needed. Moving the pivot does not improve anatomical accuracy by itself.
