extends "res://tests/suite.gd"

class FakeProvider extends Node:
	signal markers_updated(ids: Array)
	var poses := {}
	func get_marker_world_pose(id: int) -> Transform3D:
		return poses.get(id, Transform3D.IDENTITY)
	func marker_age_ms(_id: int) -> float:
		return 10.0

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var tracker := NaretArucoTracker.new()
	tracker.marker_layout_file = "res://data/user_marker_layout.cfg"
	tracker.calibration_file = "user://flip_rejection_missing.cfg"
	tracker.apply_temporal_filter = false
	tree.root.add_child(tracker)
	var provider := FakeProvider.new()
	tree.root.add_child(provider)
	tracker.bind_provider(provider)
	var layout: NaretMarkerLayout = tracker._layout
	var target := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.2, 0.3, -1.0))
	for id in [0, 1]:
		provider.poses[id] = target * layout.offsets[id].affine_inverse()
	provider.markers_updated.emit([0, 1])
	check(tracker.latest_pose.origin.is_equal_approx(target.origin), "two good markers fuse to the target")
	check(tracker.rejected_flips == 0, "a good marker is not rejected")
	var tilted := target * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(14.9)), Vector3.ZERO)
	var raw_tilt: Transform3D = tilted * layout.offsets[0].affine_inverse()
	check(not layout.is_flipped(0, raw_tilt), "tilt just below 15 degrees passes the rejection rule")
	check(layout.fuse({0: raw_tilt}).pose.basis.y.is_equal_approx(Vector3.UP), "accepted tilt is still flattened to horizontal")
	var over_limit := target * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15.1)), Vector3.ZERO)
	check(layout.is_flipped(0, over_limit * layout.offsets[0].affine_inverse()), "tilt just above 15 degrees is rejected")
	var yaw_only := Transform3D(Basis(Vector3.UP, deg_to_rad(120.0)), target.origin)
	check(not layout.is_flipped(0, yaw_only * layout.offsets[0].affine_inverse()), "120 degree yaw alone is not rejected")
	layout.floor_orientation = false
	check(not layout.is_flipped(0, over_limit * layout.offsets[0].affine_inverse()), "tilt rule remains disabled outside horizontal-floor mode")
	layout.floor_orientation = true
	var mirrored := Transform3D(target.basis * Basis(Vector3.RIGHT, PI / 2.0), target.origin + Vector3(0.14, 0.0, 0.0))
	provider.poses[1] = mirrored * layout.offsets[1].affine_inverse()
	provider.markers_updated.emit([0, 1])
	check(tracker.rejected_flips == 1 and tracker.held_flips == 1, "a mirrored marker is rejected and held")
	check(tracker.latest_pose.origin.is_equal_approx(target.origin), "the mirrored reading does not pull the fused point: " + str(tracker.latest_pose.origin))
	tracker._last_good.clear()
	provider.markers_updated.emit([0, 1])
	check(tracker.latest_pose.origin.is_equal_approx(target.origin), "without a good pose the mirrored marker is left out")
	tracker.free()
	provider.free()
	return failures
