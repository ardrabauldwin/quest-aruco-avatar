# Common and patient anchor axes

New marker-layout profiles declare `common_frame="patient_y_up"`. Their
marker-to-common transforms produce +Y up and Z along the body. Horizontal
heading uses common Z projected onto the horizontal plane. Raw detector axes,
marker size and the common-point position are unchanged.

## Why the model rotation also changes

Godot ConfigFile serializes the nine basis entries by rows. The old line
`Transform3D(1,0,0, 0,0,-1, 0,1,0, 0,0,0)` represents +90 degrees about X.
After the old horizontal construction, that produced an anchor with +Y down.
The main scene compensated with a 180-degree model rotation about X.

The new common frame uses +Y up directly. The bundled marker transforms each
absorb a -90-degree X rotation C by right multiplication: O_new = O_old*C.
Because C has zero translation, every marker still predicts the same common
point. The new standard profile no longer needs the post-fusion axis bridge.
The main scene removes its separate 180-degree model flip.

## Preserve existing placement and saved alignment

Let R be the exact 180-degree X rotation. The equivalent new anchor is
A_new = A_old*R. For an old saved model alignment M_old, loading converts it to
M_new = R*M_old. Thus A_new*M_new = A_old*M_old: the displayed world pose stays
unchanged, including existing translations and scale. The default alignment
also preserves the previous world-space 2 mm marker-thickness displacement.

A new `alignment_frame` key records the convention when calibration is saved.
Old files without this key are converted in memory; loading does not rewrite
them. Newly saved patient-axis files are not converted twice. An older APK that
does not understand the new key must not reuse a newly saved calibration without
restoring its backup. Floor/chest corrections and nudges are not recalibrated.

Standalone legacy scenes keep their historical anchor API unless they opt into
`patient_anchor_axes`. The updated main scene enables it.

## Profiles and physical chest calibration

Old profiles without `common_frame` still load. Their offsets convert to O*C,
and their bridge B converts to inverse(C)*B*R. This preserves equivalent output
in the new anchor convention without rewriting the file. Old profiles missing
their explicit bridge remain ambiguous and are rejected.

New profiles may still supply `common_to_sternum` for a measured physical
common-to-chest transform. Omission means identity; it does not establish that
marker 0 lies on the physical compression point.

## Verification

A fixture records 42 outputs from the unmodified fusion code: all seven nonempty
subsets of markers 0/1/2, three tilted/rotated setups with marker disagreement,
and horizontal orientation enabled/disabled. Both new and imported old profiles
are compared to their equivalent outputs. Tests additionally verify world-space
placement with an old scaled/nudged alignment, no double migration after save,
and unchanged default body/sternum placement. This establishes coordinate
compatibility, not anatomical accuracy or headset performance.
