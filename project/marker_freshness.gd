class_name MarkerFreshness
extends RefCounted
## The app's view of "which ArUco markers are usable right now, and where", on top of the addon.
##
## Three questions, and both the avatar rig and the gizmo ask all of them:
##
##   result_ids()   -- the ids that came out of the SINGLE newest detection. The common pose is only
##                     ever fused from one result: two results were baked with two different head
##                     poses, so mixing them mixes two capture-time corrections.
##   age_ms(id)     -- how stale one marker is on its own, regardless of which result it came from.
##   world_pose(id) -- where that marker was in its newest detection, range-corrected, WORLD space.
##
## BEFORE THE ADDON this was inference. main_3d.gd wrote a marker node's global_transform only when
## OpenCV had returned that id, and same-result grouping was done by comparing the nodes'
## last_detected_ms stamps for exact equality. ArucoMarkerTracking answers the first two directly:
## detection_applied carries exactly the markers of one detection, and marker_age_ms is a real
## per-marker age. So this class no longer infers anything -- what is left is the app's POLICY.
##
## Part of that policy is the 300 ms window below, deliberately SHORTER than the addon's
## marker_lost_timeout_ms (500 ms, after which an XR tracker is paused). A marker that is still good
## enough for a tracker to hold its last pose is not automatically good enough to feed a fresh
## fusion, and the rig and the gizmo must agree on where that line is -- hence one place for it
## rather than a constant in each.
##
## The other part is CommonPoseProvider.range_correct, the residual range error fitted on the
## 2026-09-15 viewpoint recordings. It is a correction of the marker's position ALONG THE CAMERA RAY,
## so it has to be applied in head-relative space, with the head pose the detection was baked with
## -- which only detection_applied hands over. Applying it here, once per detection, is what gives
## the rig and the gizmo the same corrected pose, the way both used to read the same patch node.

## How long a detection result stays usable. Shorter than the addon's tracker grace period on
## purpose; see the class comment.
var tracking_loss_timeout_ms := 300

var _tracking: ArucoMarkerTracking = null
## The ids this consumer cares about. A detection that found only OTHER markers must not count as
## a fresh result here, the same way it would not have moved this consumer's marker nodes before.
var _watched_ids: Array = []
var _result_ids: Array = []
var _result_ms := -1
## marker id -> range-corrected WORLD pose from the newest detection that contained it.
var _world_poses := {}


## Subscribe to the tracking node. Call from the consumer's _ready, once its exports are applied.
func attach(tracking: ArucoMarkerTracking, watched_ids: Array) -> void:
	_tracking = tracking
	_watched_ids = watched_ids.duplicate()
	if _tracking == null:
		push_error("[cpr] [freshness::attach] no ArucoMarkerTracking assigned; markers stay unseen")
		return
	if not _tracking.detection_applied.is_connected(_on_detection_applied):
		_tracking.detection_applied.connect(_on_detection_applied)


## Ids from the single newest detection, or [] once that result has aged out. Empty is the caller's
## cue that tracking is lost -- not that the markers moved.
func result_ids() -> Array:
	if _result_ms < 0 or Time.get_ticks_msec() - _result_ms > tracking_loss_timeout_ms:
		return []
	return _result_ids


## Timestamp of the newest result, in Time.get_ticks_msec(). One value per detection, which is what
## the provider and the stabilizer use to take exactly one sample per OpenCV result rather than one
## per rendered frame.
func result_ms() -> int:
	return _result_ms


## Milliseconds since this marker was last detected; INF if it never was. INF compares correctly
## against any window, so a never-seen id is simply never fresh.
func age_ms(id: int) -> float:
	if _tracking == null:
		return INF
	return _tracking.marker_age_ms(id)


## True while this marker's own pose is inside the freshness window, independent of result grouping.
func is_fresh(id: int) -> bool:
	return age_ms(id) <= float(tracking_loss_timeout_ms)


## The marker's pose from the newest detection that contained it: range-corrected, WORLD space.
## IDENTITY if it was never seen -- pair with has_pose() where that would pass for a real pose.
func world_pose(id: int) -> Transform3D:
	return _world_poses.get(id, Transform3D.IDENTITY)


func has_pose(id: int) -> bool:
	return _world_poses.has(id)


# Emitted by the addon right after it applied the same result to its trackers and its id-keyed
# record, so get_marker_world_pose(id) below IS poses[id] run through the addon's play->world
# conversion -- no second copy of that conversion lives here.
func _on_detection_applied(
		_image: Image, _corners: Dictionary, poses: Dictionary, head_pose: Transform3D) -> void:
	var mine: Array = []
	var to_head := head_pose.affine_inverse()
	for id in poses:
		if not _watched_ids.has(id):
			continue
		# Both play space, so this is the marker relative to the head at capture time, which is
		# where the correction is defined (the old pipeline's camera-space pose).
		var play: Transform3D = poses[id]
		var in_head := to_head * play
		in_head.origin = CommonPoseProvider.range_correct(in_head.origin)
		# The correction as a marker-local offset, carried onto the addon's world pose. Exact while
		# XRServer.world_scale is 1: the offset is in metres and would otherwise need the scale too.
		var correction := play.affine_inverse() * (head_pose * in_head)
		_world_poses[id] = _tracking.get_marker_world_pose(id) * correction
		mine.append(id)
	# A detection that found none of our markers is not a result for us. Letting it through would
	# refresh _result_ms without refreshing any pose, so a marker that left view would look fresh
	# for as long as any OTHER marker stayed visible.
	if mine.is_empty():
		return
	_result_ids = mine
	_result_ms = Time.get_ticks_msec()
