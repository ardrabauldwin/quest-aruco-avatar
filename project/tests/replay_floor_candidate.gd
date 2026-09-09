extends SceneTree


class CandidateProvider extends CommonPoseProvider:
	var constrain_first := false
	func get_pose(markers: Array, detection_ms: int = -1) -> Transform3D:
		var estimates: Array[Transform3D] = []
		for marker in markers:
			if marker == null or not _offsets.has(marker):
				continue
			var offset: Transform3D = _offsets[marker]
			var common: Transform3D = marker.global_transform * offset
			if constrain_first:
				var flat := _floor_lock(common)
				var marker_in_common := offset.affine_inverse().origin
				common = Transform3D(flat.basis, marker.global_position - flat.basis * marker_in_common)
			estimates.append(common)
		if estimates.is_empty():
			return _common_pose
		_common_pose = _floor_lock(_fuse(estimates))
		_has_common_pose = true
		_update_rest(_common_pose, detection_ms)
		return _common_pose

class ReplayRig extends "res://avatar_rig_navel.gd":
	var freeze_rest := false
	var has_display_pose := false
	func _apply_filtered_pose(pose: Transform3D) -> void:
		super._apply_filtered_pose(pose)
		has_display_pose = true
	func _load_calibration() -> void:
		assert(_common_provider.load_from(DEFAULT_CALIBRATION_PATH, _markers))
	func _on_orientation_settled() -> void:
		_filter.anchor_at(_common_provider.rest_pose())
	func _update_tracking(markers: Array, detection_ms: int, delta: float) -> void:
		if not freeze_rest:
			super._update_tracking(markers, detection_ms, delta)
			return
		_tracking_was_available = true
		var raw := _common_provider.get_pose(markers, detection_ms)
		var filtered := _filter.update(raw, delta, detection_ms, _common_provider.rest_pose(), _common_provider.has_rest_pose())
		if _filter.is_ready() and _common_provider.has_rest_pose():
			_apply_filtered_pose(filtered)

func _init() -> void:
	call_deferred("run")

func read_pose(row: PackedStringArray, start: int) -> Transform3D:
	return Transform3D(Basis(Quaternion(float(row[start+3]), float(row[start+4]), float(row[start+5]), float(row[start+6])).normalized()), Vector3(float(row[start]), float(row[start+1]), float(row[start+2])))

func run() -> void:
	var source := FileAccess.open("res://../recordings/aruco_viewpoint_1788955119.csv", FileAccess.READ)
	assert(source != null)
	source.get_csv_line()
	var rows: Array[PackedStringArray] = []
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() >= 33:
			rows.append(row)
	for mode in ["floor_baseline72", "floor_candidate72"]:
		replay(rows, mode)
	print("Research replay complete")
	quit()

func replay(rows: Array[PackedStringArray], mode: String) -> void:
	var rig := ReplayRig.new()
	var provider := CandidateProvider.new()
	provider.constrain_first = mode == "floor_candidate72"
	rig._common_provider = provider
	var markers: Array = []
	for i in range(3):
		var marker := Node3D.new()
		marker.name = "aruco_patch%d" % i
		root.add_child(marker)
		markers.append(marker)
	rig.common_marker = markers[0]
	rig.chest_marker = markers[1]
	rig.torso_marker = markers[2]
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(rig)
	rig.freeze_rest = mode == "fixed_rest72"
	if mode == "no_prior72":
		rig._filter.prior_time_s = 0.0
	var output := FileAccess.open("res://../builds/replay_%s.csv" % mode, FileAccess.WRITE)
	assert(output != null)
	output.store_line("time_s,phase,ready,raw_x,raw_y,raw_z,filtered_x,filtered_y,filtered_z,rest_x,rest_y,rest_z,raw_yaw,filtered_yaw,rest_yaw")
	var hz := 90.0 if mode == "current90" else 72.0
	var tick := float(rows[0][1])
	var start := tick
	var selected: Array = []
	var latest_ms := -1000000
	for row in rows:
		var now := int(row[1])
		while tick < now:
			if tick - latest_ms <= 300 and not selected.is_empty():
				rig._update_tracking(selected, latest_ms, 1.0 / hz)
			else:
				rig._hold_after_tracking_loss()
			tick += 1000.0 / hz
		var seen: Array = []
		var camera := read_pose(row, 5)
		for i in range(3):
			var col := 12 + i * 7
			if row[col] != "":
				markers[i].global_transform = camera * read_pose(row, col)
				seen.append(markers[i])
		if not seen.is_empty():
			selected = seen
			latest_ms = now
			# Incorporate this result at the next simulated render tick.
			var raw := rig._common_provider.get_pose(selected, latest_ms)
			var filtered := rig.global_transform
			var rest := rig._common_provider.rest_pose()
			var values := PackedStringArray([str((now-start)/1000.0), row[4], str(int(rig.has_display_pose))])
			for p in [raw.origin, filtered.origin, rest.origin]:
				for v in [p.x,p.y,p.z]:
					values.append(str(v))
			for p in [raw,filtered,rest]:
				values.append(str(atan2(p.basis.y.x,p.basis.y.z)))
			output.store_line(",".join(values))
	output.close()
	rig.free()
	for marker in markers:
		marker.free()
