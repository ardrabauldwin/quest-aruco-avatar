extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var provider := CommonPoseProvider.new()
	# marker id -> world pose, as MarkerFreshness hands them to the rig.
	var poses := {}
	var common := Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(1, 0.2, -2))
	for i in range(3):
		var relative := Transform3D(Basis.from_euler(Vector3(.05*i, .1*i, -.1*i)), Vector3(.08*i, .06*i, .01*i))
		provider._offsets[i] = relative.affine_inverse()
		poses[i] = common * relative
	if provider.has_method("_build_inverse_offsets"):
		provider.call("_build_inverse_offsets")
	var failures := 0
	for mask in range(1, 8):
		var seen := {}
		for i in range(3):
			if mask & (1 << i):
				seen[i] = poses[i]
		var result := provider.get_pose(seen, mask)
		if result.origin.distance_to(common.origin) > 0.00001 or not result.basis.is_equal_approx(common.basis):
			print("FAIL visible subset ", mask, "; common position error cm: ", result.origin.distance_to(common.origin)*100)
			failures += 1
	# Two independent inputs carry equal weight; an unseen third adds no information.
	var moved: Transform3D = poses[0]
	moved.origin.x += 0.06
	var pair := provider.get_pose({0: moved, 1: poses[1]}, 10)
	if pair.origin.distance_to(common.origin + Vector3(.03,0,0)) > .00001:
		print("FAIL independent measurement weights")
		failures += 1
	var held := provider.get_pose({}, 11)
	if not held.is_equal_approx(pair):
		failures += 1
	print("Missing-marker common-point tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
