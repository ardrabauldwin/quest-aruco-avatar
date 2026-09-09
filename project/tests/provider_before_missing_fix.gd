extends CommonPoseProvider

var _inverse_offsets := {}

func get_pose(markers: Array, detection_ms: int = -1) -> Transform3D:
	var estimates: Array[Transform3D] = []
	var detected_markers: Dictionary = {}

	# Convert all detected markers to common pose
	for marker in markers:
		if marker != null and _offsets.has(marker):
			var marker_to_common: Transform3D = _offsets[marker]
			estimates.append(marker.global_transform * marker_to_common)
			detected_markers[marker] = true

	# Rigid-body reconstruction: for any missing marker, estimate it from detected ones
	for missing_marker in _offsets.keys():
		if detected_markers.has(missing_marker):
			continue  # Already detected, no need to reconstruct

		if not _inverse_offsets.has(missing_marker):
			continue  # No reconstruction rules available

		# Find any detected marker that can be used to reconstruct this missing one
		for source_marker in _inverse_offsets[missing_marker].keys():
			if detected_markers.has(source_marker):
				var source_to_missing: Transform3D = _inverse_offsets[missing_marker][source_marker]
				estimates.append(source_marker.global_transform * source_to_missing)
				break  # Use first available source marker

	if estimates.is_empty():
		return _common_pose

	_common_pose = _floor_lock(_fuse(estimates))
	_has_common_pose = true
	_update_rest(_common_pose, detection_ms)
	return _common_pose


func _build_inverse_offsets() -> void:
	_inverse_offsets.clear()
	var markers_list = _offsets.keys()

	# For each marker, build inverse relationships from all others
	for target_marker in markers_list:
		_inverse_offsets[target_marker] = {}

		# Common→ID1: offset stored as common→marker[ID1]. Inverse is ID1→common.
		for source_marker in markers_list:
			if source_marker == target_marker:
				continue

			# We have: common = marker[source] * _offsets[source]
			# We need: target = marker[source] * inverse_offset
			# Solution: target = common * _offsets[target]^-1
			#           target = marker[source] * _offsets[source] * _offsets[target]^-1
			# So: inverse = _offsets[source] * _offsets[target]^-1

			var source_offset: Transform3D = _offsets[source_marker]
			var target_offset: Transform3D = _offsets[target_marker]
			var target_inverse: Transform3D = target_offset.inverse()
			var reconstruction_offset: Transform3D = source_offset * target_inverse

			_inverse_offsets[target_marker][source_marker] = reconstruction_offset



func load_from(path: String, markers: Array) -> bool:
	if not super.load_from(path, markers):
		return false
	_build_inverse_offsets()
	return true
