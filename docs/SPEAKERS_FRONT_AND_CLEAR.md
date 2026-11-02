# Both speakers in front and clear of scanned walls

Headset placement now requires a room scan, accepted patient placement and a
calibrated floor. A play-area boundary is not a furniture/wall scan. There is no
unverified patient-relative fallback. Desktop preview retains its authored poses.

The complete ring/grid candidate set is searched for a pair. Each character has
its own containing horizontal circle computed from actual model geometry, scale,
current bone poses and props. The assumed 25 cm shoulder radius is not used.
Per-bone boxes are cached from influenced skin vertices; their animated world
corners provide conservative bounds without reskinning every vertex every frame.
Morph displacement is reserved up to the existing rig maximum weight 2.2.
Nonnegative normalised skin weights are required; unknown geometry fails closed.

Every candidate must put its entire circle inside the scanned floor, outside all
scanned obstacle rectangles, outside the patient and trainee exclusion zones, and
strictly ahead of the headset's horizontal viewing plane. The two circles cannot
overlap. The front test applies to BOTH people, not only Anna or either person.
No automatic scaling or floor-height nudges are introduced.

A process-priority-200 guard runs after animation (100) and floor grounding (110).
If head direction, a gesture, a turn or new room geometry invalidates either
person's placement, both are hidden before rendering. The existing one-second
placement pass tries a new pair. On failure, a localized hand-menu notice asks
for a scan/floor setup or a clearer area in front. Training audio continues.
The stricter circles can conservatively reject spaces where a less conservative
oriented body envelope would fit; finding no sampled pair does not prove no pair
exists anywhere in the room.

"In front" means the entire horizontal envelope is ahead of the head plane. It
does not guarantee both are simultaneously inside the optical field of view or
unoccluded by every physical object. Wall/obstacle avoidance is relative to the
supplied scan: missing, stale or inaccurate scans cannot guarantee real clearance.
Room scan walls are currently represented by conservative XZ rectangles. Animated
skeletal/morph bounds assume the shipped rig, not arbitrary shader displacement.

Tests cover front-only pair selection, full-body wall clearance, overlapping
bodies, front-only obstruction, missing scans, impossible pairs and envelope
containment of both actual models in idle, talk and reach poses. A live Quest
room/turning/gesture check remains necessary. This is a local source change,
not included in the previously published 29 October standard APK.
