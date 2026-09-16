extends SceneTree
## Replay a viewpoint recording through the real placement chain (provider -> stabilizer -> rig)
## at 72 Hz and write what the AVATAR did, row by row, next to the raw fused pose.
##   godot --headless --path project -s res://tests/replay_recording.gd -- <csv path> [out csv]
## Analyse with tools/replay_summary.py.

class ReplayRig extends "res://avatar_rig_navel.gd":
	var has_display_pose := false
	func _apply_filtered_pose(pose: Transform3D) -> void:
		super._apply_filtered_pose(pose)
		has_display_pose = true
	var calibration_path := DEFAULT_CALIBRATION_PATH
	func _load_calibration() -> void:
		assert(_common_provider.load_from(calibration_path, _markers), "cannot load " + calibration_path)
	func _on_orientation_settled() -> void:
		_filter.anchor_at(_common_provider.rest_pose())

func _init() -> void:
	call_deferred("run")

func read_pose(row: PackedStringArray, start: int) -> Transform3D:
	return Transform3D(Basis(Quaternion(float(row[start+3]), float(row[start+4]), float(row[start+5]), float(row[start+6])).normalized()), Vector3(float(row[start]), float(row[start+1]), float(row[start+2])))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 1, "usage: -- <recording.csv> [out.csv]")
	var out_path: String = args[1] if args.size() > 1 else args[0].get_basename() + "_replay.csv"
	var source := FileAccess.open(args[0], FileAccess.READ)
	assert(source != null, "cannot open " + args[0])
	source.get_csv_line()
	var rows: Array[PackedStringArray] = []
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() >= 33:
			rows.append(row)
	var rig := ReplayRig.new()
	if args.size() > 4:
		rig.calibration_path = args[4]
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
	if args.size() > 2:
		rig._common_provider.marker_weights[markers[0]] = float(args[2])
	if args.size() > 3:
		rig._common_provider.flip_hold_ms = int(args[3])
	var output := FileAccess.open(out_path, FileAccess.WRITE)
	assert(output != null)
	output.store_line("time_s,phase,ready,n_markers,raw_x,raw_y,raw_z,raw_yaw,avatar_x,avatar_y,avatar_z,avatar_yaw,rejected_flips")
	var hz := 72.0
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
				var marker_cam := read_pose(row, col)
				marker_cam.origin = CommonPoseProvider.range_correct(marker_cam.origin)
				markers[i].global_transform = camera * marker_cam
				seen.append(markers[i])
		if not seen.is_empty():
			selected = seen
			latest_ms = now
		var raw: Transform3D = rig._common_provider._common_pose
		var avatar := rig.global_transform
		var values := PackedStringArray([str((now - start) / 1000.0), row[4], str(int(rig.has_display_pose)), str(seen.size())])
		for p in [raw, avatar]:
			for v in [p.origin.x, p.origin.y, p.origin.z]:
				values.append(str(v))
			values.append(str(rad_to_deg(atan2(p.basis.y.x, p.basis.y.z))))
		values.append(str(rig._common_provider.rejected_flips))
		output.store_line(",".join(values))
	output.close()
	print("Replay written: ", out_path, "  rows=", rows.size(), "  rejected flips=", rig._common_provider.rejected_flips)
	rig.free()
	for marker in markers:
		marker.free()
	quit()
