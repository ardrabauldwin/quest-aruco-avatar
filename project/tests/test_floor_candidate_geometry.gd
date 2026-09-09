extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var candidate = preload("res://tests/replay_floor_candidate.gd").CandidateProvider.new()
	candidate.constrain_first = true
	var baseline = preload("res://tests/replay_floor_candidate.gd").CandidateProvider.new()
	var marker := Node3D.new()
	root.add_child(marker)
	# A tilted marker mounted 15 cm away from the common origin.
	var marker_in_common := Transform3D(Basis.from_euler(Vector3(0.2, -0.1, 0.15)), Vector3(0.03, 0.15, -0.02))
	var common := Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(0.4, 0.2, -1))
	candidate._offsets[marker] = marker_in_common.affine_inverse()
	baseline._offsets[marker] = marker_in_common.affine_inverse()
	marker.global_transform = common * marker_in_common
	assert(candidate.get_pose([marker], 1).origin.distance_to(common.origin) < 0.00001)
	# Inject pitch error in orientation only; keep the measured marker centre correct.
	var rotation_error := Basis(common.basis.x, deg_to_rad(15))
	marker.global_basis = rotation_error * common.basis * marker_in_common.basis
	var constrained_error: float = candidate.get_pose([marker], 2).origin.distance_to(common.origin)
	var original_error: float = baseline.get_pose([marker], 2).origin.distance_to(common.origin)
	assert(constrained_error < 0.00001)
	assert(original_error > 0.03)
	print("Floor candidate geometry PASS; pure-pitch induced position error, baseline/candidate cm: ", original_error*100, " / ", constrained_error*100)
	marker.free()
	quit()
