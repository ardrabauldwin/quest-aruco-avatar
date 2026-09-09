extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var provider := CommonPoseProvider.new()
	var markers: Array = []
	var common := Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(1, 0.2, -2))
	for i in range(3):
		var marker := Node3D.new()
		root.add_child(marker)
		markers.append(marker)
		var relative := Transform3D(Basis.from_euler(Vector3(.05*i, .1*i, -.1*i)), Vector3(.08*i, .06*i, .01*i))
		provider._offsets[marker] = relative.affine_inverse()
		marker.global_transform = common * relative
	if provider.has_method("_build_inverse_offsets"):
		provider.call("_build_inverse_offsets")
	var failures := 0
	for mask in range(1, 8):
		var seen: Array = []
		for i in range(3):
			if mask & (1 << i):
				seen.append(markers[i])
		var result := provider.get_pose(seen, mask)
		if result.origin.distance_to(common.origin) > 0.00001 or not result.basis.is_equal_approx(common.basis):
			print("FAIL visible subset ", mask, "; common position error cm: ", result.origin.distance_to(common.origin)*100)
			failures += 1
	# Two independent inputs carry equal weight; an unseen third adds no information.
	markers[0].global_position.x += 0.06
	var pair := provider.get_pose([markers[0],markers[1]], 10)
	if pair.origin.distance_to(common.origin + Vector3(.03,0,0)) > .00001:
		print("FAIL independent measurement weights")
		failures += 1
	var held := provider.get_pose([], 11)
	if not held.is_equal_approx(pair):
		failures += 1
	for marker in markers:
		marker.free()
	print("Missing-marker common-point tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
