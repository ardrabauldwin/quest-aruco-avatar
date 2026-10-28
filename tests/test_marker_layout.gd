extends "res://tests/suite.gd"

class Provider extends Node:
	signal markers_updated(ids: Array)
	var poses := {}
	var age := 0.0
	var enabled := true
	var default_marker_size := 0.05
	var marker_sizes: Array[float] = []
	func get_marker_world_pose(id: int) -> Transform3D:
		return poses[id]
	func marker_age_ms(_id: int) -> float:
		return age

func run() -> Array[String]:
	failures.clear()
	var layout := NaretMarkerLayout.new()
	layout.offsets = {0: Transform3D.IDENTITY, 1: Transform3D(Basis.IDENTITY, Vector3(-0.14, 0, 0)), 2: Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.16))}
	layout.common_to_sternum = Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.03, 0))
	var common := Transform3D(Basis(Vector3.UP, 0.7), Vector3(1, 0.2, -2))
	var measured := {}
	for id in layout.offsets:
		measured[id] = common * (layout.offsets[id] as Transform3D).affine_inverse()
	var expected := common * layout.common_to_sternum
	check(layout.fuse(measured).pose.is_equal_approx(expected), "three markers reconstruct one world sternum without double transform")
	check(layout.fuse({1: measured[1]}).pose.is_equal_approx(expected), "occluded marker zero: calibrated marker one still places sternum")
	check(layout.fuse({2: measured[2]}).pose.is_equal_approx(expected), "marker two alone uses its full calibrated offset")
	check(layout.fuse({49: common}).is_empty(), "unknown marker never becomes placement")
	check(layout.fuse({0: Transform3D(Basis.IDENTITY.scaled(Vector3(2, 1, 1)), Vector3.ZERO)}).is_empty(), "scaled detector poses rejected")
	var cfg := ConfigFile.new()
	var path := "user://migration_test_layout.cfg"
	cfg.set_value("common", "aruco_patch0", Transform3D.IDENTITY)
	cfg.save(path)
	check(layout.load_profile(path) == ERR_INVALID_DATA, "legacy profile cannot silently assume common point is sternum")
	cfg.set_value("layout", "common_to_sternum", layout.common_to_sternum)
	cfg.set_value("layout", "common_frame", "patient_y_up")
	cfg.set_value("layout", "marker_size_m", 0.10)
	cfg.save(path)
	check(layout.load_profile(path) == OK and is_equal_approx(layout.marker_size_m, 0.10), "explicit measured layout loads")
	cfg.set_value("common", "aruco_patch1", Transform3D(Basis.IDENTITY, Vector3(-0.14, 0, 0)))
	cfg.save(path)
	var tree := Engine.get_main_loop() as SceneTree
	var world := Node3D.new()
	tree.root.add_child(world)
	var provider := Provider.new()
	provider.name = "Provider"
	provider.poses = measured
	world.add_child(provider)
	var tracker := NaretArucoTracker.new()
	tracker.desktop_preview = false
	tracker.marker_layout_file = path
	tracker.provider_path = NodePath("../Provider")
	world.add_child(tracker)
	tracker._filter = null # verify adapter only, not temporal smoothing
	var published: Array[Transform3D] = []
	tracker.pose_updated.connect(func(pose: Transform3D): published.append(pose))
	provider.markers_updated.emit([1])
	check(published.size() == 1 and published[0].is_equal_approx(expected), "tracker publishes from current frame's marker one without marker zero")
	check(is_equal_approx(provider.default_marker_size, 0.10), "provider receives real 10 cm geometry")
	provider.age = 900
	provider.markers_updated.emit([1])
	tracker._process(0.01)
	check(published.size() == 1 and not tracker.tracked, "stale results neither place patient nor stay tracked")
	check(tracker.configure_marker(0.05, 0) == ERR_UNAVAILABLE, "single marker controls cannot silently corrupt layout geometry")
	world.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return failures
