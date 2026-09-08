class_name MarkerFreshness
extends RefCounted

## Determines whether an ArUco marker was detected recently.
##
## main_3d.gd records a timestamp whenever OpenCV returns that marker ID.

# Complete tracking is treated as lost when the newest successful marker result is older than
# this. Same-result fusion is handled separately by exact timestamp equality.
var tracking_loss_timeout_ms := 300

# A very large age used for null markers and markers not detected yet.
# It is always greater than tracking_loss_timeout_ms, so never-detected markers cannot keep
# tracking alive.
const NOT_DETECTED_AGE_MS := 1 << 30


## Returns the number of milliseconds since this marker last received a detected pose.
## The primary rig compares the newest successful marker age with tracking_loss_timeout_ms.
func age_ms(marker: Node3D) -> int:
	if marker == null or not marker.has_meta("last_detected_ms"):
		return NOT_DETECTED_AGE_MS

	return Time.get_ticks_msec() - int(marker.get_meta("last_detected_ms"))
