class_name CommonPoseProviderOld
extends RefCounted
## Reconstructs one 6DOF pose for ID0 common.
##
## Marker names:
##   aruco_patch0 = common (the final target)
##   aruco_patch1 = chest
##   aruco_patch2 = torso
##
## Each marker has a saved marker-to-common offset. A visible marker rebuilds
## ID0 common with:
##
##     marker.global_transform * marker_to_common
##
## Several visible markers are fused. With no visible marker, the last good
## pose is held.

var _offsets := {}
var _common_pose := Transform3D.IDENTITY
var _has_common_pose := false


## Save the marker-to-common offset for every supplied marker.
func calibrate(markers: Array, common_pose: Transform3D) -> void:
	for marker in markers:
		if marker != null:
			_offsets[marker] = (
				marker.global_transform.affine_inverse()
				* common_pose
			)


## Rebuild and fuse ID0 common from the visible calibrated markers.
func get_pose(visible_now: Array) -> Transform3D:
	var views: Array[Transform3D] = []

	for marker in visible_now:
		if marker != null and _offsets.has(marker):
			var marker_to_common: Transform3D = _offsets[marker]
			var estimated_common_pose: Transform3D = (
				marker.global_transform * marker_to_common
			)
			views.append(estimated_common_pose)

	if not views.is_empty():
		_common_pose = _fuse(views)
		_has_common_pose = true

	return _common_pose


## True after the first valid common pose has been calculated.
func is_ready() -> bool:
	return _has_common_pose


## Write the calibration offsets to disk.
func save_to(path: String) -> void:
	var cfg := ConfigFile.new()
	for marker in _offsets:
		cfg.set_value("common", marker.name, _offsets[marker])
	cfg.save(path)


## Reload calibration offsets and match them to marker nodes by name.
func load_from(path: String, markers: Array) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false

	_offsets.clear()
	for marker in markers:
		if marker != null and cfg.has_section_key("common", marker.name):
			_offsets[marker] = cfg.get_value("common", marker.name)
	return not _offsets.is_empty()


## Average several estimates of ID0 common.
func _fuse(poses: Array) -> Transform3D:
	var position := Vector3.ZERO
	var rotation := Quaternion(0, 0, 0, 0)
	var first: Quaternion = poses[0].basis.get_rotation_quaternion()

	for pose in poses:
		position += pose.origin
		var q: Quaternion = pose.basis.get_rotation_quaternion()
		if first.dot(q) < 0.0:
			q = -q
		rotation += q

	return Transform3D(
		Basis(rotation.normalized()),
		position / poses.size()
	)
