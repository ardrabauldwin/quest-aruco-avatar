extends SceneTree


func _init() -> void:
	_test_prior_still_works_inside_rest_dead_zone()
	_test_small_stable_movement_can_reanchor()
	_test_slow_movement_is_not_a_stable_endpoint()
	_test_stable_target_reanchors_once()
	print("filter/rest flow tests: PASS")
	quit()


func _test_prior_still_works_inside_rest_dead_zone() -> void:
	var filter := SimplePoseStabilizer.new()
	filter.configure(7, 0.006, 0.5, 0.8, 0.1)
	var rest := Transform3D.IDENTITY
	var near_rest := Transform3D(Basis.IDENTITY, Vector3(0.004, 0.0, 0.0))
	filter.anchor_at(near_rest)
	var output := near_rest
	for frame in 30:
		output = filter.update(near_rest, 1.0 / 72.0, 1, rest, true)
	assert(output.origin.x < near_rest.origin.x)


func _test_small_stable_movement_can_reanchor() -> void:
	var filter := SimplePoseStabilizer.new()
	filter.configure(7, 0.006, 0.5, 0.8, 8.0, 0.002, 0.5, 7)
	var rest := Transform3D.IDENTITY
	var moved := Transform3D(Basis.IDENTITY, Vector3(0.020, 0.0, 0.0))
	filter.anchor_at(rest)
	for detection in 30:
		filter.update(moved, 1.0 / 72.0, detection, rest, true)
	assert(filter.position_reanchor_ready())
	assert(not filter.rotation_reanchor_ready())


func _test_slow_movement_is_not_a_stable_endpoint() -> void:
	var filter := SimplePoseStabilizer.new()
	filter.configure(7, 0.006, 0.5, 0.8, 8.0, 0.002, 0.5, 7)
	var rest := Transform3D.IDENTITY
	filter.anchor_at(rest)
	for detection in 30:
		var moving := Transform3D(
			Basis.IDENTITY,
			Vector3(float(detection + 1) * 0.001, 0.0, 0.0)
		)
		filter.update(moving, 1.0 / 72.0, detection, rest, true)
	assert(not filter.position_reanchor_ready())


func _test_stable_target_reanchors_once() -> void:
	var filter := SimplePoseStabilizer.new()
	filter.configure(7, 0.006, 0.5, 0.8, 8.0, 0.002, 0.5, 7)
	var old_rest := Transform3D.IDENTITY
	var moved := Transform3D(Basis.IDENTITY, Vector3(0.020, 0.0, 0.0))
	filter.anchor_at(old_rest)
	for detection in 30:
		filter.update(moved, 1.0 / 72.0, detection, old_rest, true)
	assert(filter.position_reanchor_ready())

	var provider := CommonPoseProvider.new()
	provider._has_rest_pose = true
	provider._rest_collecting = false
	provider._rest_pose = old_rest
	assert(provider.reanchor_rest_from_stable_target(moved, 42, true, false))
	filter.complete_rest_reanchor(true, false)
	assert(is_equal_approx(provider.rest_pose().origin.x, 0.020))
	assert(not filter.position_reanchor_ready())

	# The same OpenCV result cannot re-anchor twice.
	var duplicate := Transform3D(Basis.IDENTITY, Vector3(0.200, 0.0, 0.0))
	assert(not provider.reanchor_rest_from_stable_target(duplicate, 42, true, false))
	assert(is_equal_approx(provider.rest_pose().origin.x, 0.020))
