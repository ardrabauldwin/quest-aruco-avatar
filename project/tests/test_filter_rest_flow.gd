extends SceneTree


func _init() -> void:
	_test_relocated_measurement_is_not_pulled_to_old_rest()
	_test_prior_still_works_inside_rest_dead_zone()
	_test_dead_zone_crossing_does_not_disable_prior()
	_test_confirmed_relocation_reanchors_once()
	print("filter/rest flow tests: PASS")
	quit()


func _test_relocated_measurement_is_not_pulled_to_old_rest() -> void:
	var filter := SimplePoseStabilizer.new()
	filter.configure(7, 0.006, 0.5, 0.8, 8.0)
	var rest := Transform3D.IDENTITY
	var moved := Transform3D(Basis.IDENTITY, Vector3(0.1, 0.0, 0.0))
	filter.anchor_at(rest)
	for detection in 1000:
		filter.update(moved, 1.0 / 72.0, detection, rest, true)
	assert(filter.position_relocation_ready())
	# Smoothing may stop inside the 6 mm dead zone, but the old prior must not hold a 100 mm
	# relocation at its former ~91 mm equilibrium.
	assert(filter.update(moved, 1.0 / 72.0, 1001, rest, true).origin.x > 0.093)


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


func _test_dead_zone_crossing_does_not_disable_prior() -> void:
	var filter := SimplePoseStabilizer.new()
	filter.configure(7, 0.006, 0.5, 0.8, 0.1, 0.100, 5.0, 7, 0.002, 0.5, 7)
	var rest := Transform3D.IDENTITY
	var outside_dead_zone := Transform3D(Basis.IDENTITY, Vector3(0.020, 0.0, 0.0))
	filter.anchor_at(rest)
	for detection in 30:
		filter.update(outside_dead_zone, 1.0 / 72.0, detection, rest, true)
	assert(not filter._position_relocating)
	assert(not filter.position_relocation_ready())


func _test_confirmed_relocation_reanchors_once() -> void:
	var filter := SimplePoseStabilizer.new()
	filter.configure(7, 0.006, 0.5, 0.8, 8.0, 0.100, 5.0, 7, 0.002, 0.5, 7)
	var old_rest := Transform3D.IDENTITY
	var moved := Transform3D(Basis.IDENTITY, Vector3(0.120, 0.0, 0.0))
	filter.anchor_at(old_rest)
	for detection in 30:
		filter.update(moved, 1.0 / 72.0, detection, old_rest, true)
	assert(filter.position_relocation_ready())
	assert(not filter.rotation_relocation_ready())

	var provider := CommonPoseProvider.new()
	provider._has_rest_pose = true
	provider._rest_collecting = false
	provider._rest_pose = old_rest
	assert(provider.reanchor_rest_after_relocation(moved, 42, true, false))
	filter.complete_relocation(true, false)
	assert(is_equal_approx(provider.rest_pose().origin.x, 0.120))
	assert(not filter._position_relocating)

	# The same OpenCV result cannot re-anchor twice.
	var duplicate := Transform3D(Basis.IDENTITY, Vector3(0.200, 0.0, 0.0))
	assert(not provider.reanchor_rest_after_relocation(duplicate, 42, true, false))
	assert(is_equal_approx(provider.rest_pose().origin.x, 0.120))
