# Reset old patient nudges after the pivot cleanup

The main scene now selects patient alignment revision 2. Loading a calibration
from an earlier revision removes its manual translation/rotation from the
active alignment. Existing scale is retained, and the geometry offset is
recalculated so the sternum pivot follows the supplied anchor. The existing
marker-thickness correction and separate floor/chest height rules still apply.
This does not claim that marker 0 is physically on the compression point.

Marker-layout calibration, floor fingertip correction, chest height/fit and
manual floor correction are not reset. This operation concerns the saved
`marker_to_mannequin` alignment, not those separate measurements.

Loading does not rewrite the device file. Before a later save replaces the
old pose, its original pose/frame/calibrated flag/revision (where present) are
retained in the `previous_patient_alignment` section. The new alignment is
marked uncalibrated: use the existing Save alignment control to confirm it
after startup placement, before starting training. A new deliberate nudge
saved at revision 2 is restored normally and is not cleared on each launch.

Standalone scenes default to revision 1 for compatibility. The pivot cleanup
and this reset have not been installed on the headset by editing the source.
