extends SceneTree
## A marker returned in its mirror (planar-ambiguity) pose must not be fused; when every visible
## marker is flipped the previous common pose is held.

func _init() -> void:
	call_deferred("run")

func shifted(pose: Transform3D, offset: Vector3) -> Transform3D:
	return Transform3D(pose.basis, pose.origin + offset)

func run() -> void:
	var provider := CommonPoseProvider.new()
	# marker id -> world pose, as MarkerFreshness hands them to the rig.
	var poses := {}
	var common := Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(1, 0.2, -2))
	for i in range(3):
		var relative := Transform3D(Basis.from_euler(Vector3(.05*i, .1*i, -.1*i)), Vector3(.08*i, .06*i, .01*i))
		provider._offsets[i] = relative.affine_inverse()
		poses[i] = common * relative
	var failures := 0
	var good := provider.get_pose(poses, 1)
	if good.origin.distance_to(common.origin) > 0.00001 or provider.rejected_flips != 0:
		print("FAIL baseline: nothing should be rejected")
		failures += 1
	# Marker 0 comes back as the mirror solution: normal turned ~90 deg, position 13 cm off.
	var true_xform: Transform3D = poses[0]
	var flipped := true_xform
	flipped.basis = flipped.basis * Basis(Vector3.RIGHT, deg_to_rad(90.0))
	flipped.origin += Vector3(0.10, 0.0, 0.08)
	poses[0] = flipped
	var result := provider.get_pose(poses, 2)
	if result.origin.distance_to(common.origin) > 0.00001 or not result.basis.is_equal_approx(common.basis):
		print("FAIL flipped marker changed the common pose by cm: ", result.origin.distance_to(common.origin) * 100)
		failures += 1
	if provider.rejected_flips != 1:
		print("FAIL expected one rejected flip, got ", provider.rejected_flips)
		failures += 1
	# Within flip_hold_ms the flipped marker's last good pose stands in for it (weight kept),
	# so a marker 6 cm off plus the held marker average to 3 cm, not 6.
	poses[0] = flipped
	poses[1] = shifted(poses[1], Vector3(0.06, 0, 0))
	var held_pair := provider.get_pose({0: poses[0], 1: poses[1]}, 500)
	if held_pair.origin.distance_to(common.origin + Vector3(0.03, 0, 0)) > 0.00001:
		print("FAIL held pose should share the average, offset cm: ", (held_pair.origin - common.origin).x * 100)
		failures += 1
	if provider.held_flips != 2:
		print("FAIL expected two held flips (first flipped frame + this one), got ", provider.held_flips)
		failures += 1
	# Past the hold window the flipped marker is dropped, so the 6 cm marker stands alone.
	var expired := provider.get_pose({0: poses[0], 1: poses[1]}, 2000)
	if expired.origin.distance_to(common.origin + Vector3(0.06, 0, 0)) > 0.00001:
		print("FAIL expired hold should drop the flipped marker")
		failures += 1
	poses[1] = shifted(poses[1], Vector3(-0.06, 0, 0))
	# A tilt of 25 deg (steep but real, like the chest marker) is still accepted.
	var tilted := true_xform
	tilted.basis = tilted.basis * Basis(Vector3.RIGHT, deg_to_rad(25.0))
	poses[0] = tilted
	var rejected_before := provider.rejected_flips
	provider.get_pose(poses, 3)
	if provider.rejected_flips != rejected_before:
		print("FAIL a 25 deg tilt must not be rejected")
		failures += 1
	# Every visible marker flipped: hold the previous pose.
	for id in poses.keys():
		var f: Transform3D = poses[id]
		f.basis = f.basis * Basis(Vector3.RIGHT, deg_to_rad(90.0))
		f.origin += Vector3(0.12, 0, 0)
		poses[id] = f
	var before := provider.get_pose({}, 9000)
	var held := provider.get_pose(poses, 9001)
	if not held.is_equal_approx(before):
		print("FAIL all-flipped frame moved the pose")
		failures += 1
	print("Flip rejection tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
