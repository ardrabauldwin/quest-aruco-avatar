extends "res://tests/suite.gd"
const Floor = preload("res://scripts/tracking/stable_floor_reference.gd")

class FakeXR extends NaretOpenXRSetup:
	var sample := NAN
	func floor_height_world(_origin: XROrigin3D) -> float:
		return sample

class FakeRoom extends NaretRoomLayout:
	var reads := 0
	func floor_height_world() -> float:
		reads += 1
		return 1.0

func run() -> Array[String]:
	failures.clear()
	var floor_ref := Floor.new()
	check(not is_finite(floor_ref.height_world(NAN, Transform3D.IDENTITY)), "missing floor does not invent height zero")
	check(not floor_ref.ready, "wait until local floor is valid")
	var expected := -0.12
	check(is_equal_approx(floor_ref.height_world(expected, Transform3D.IDENTITY), expected), "valid reference is used without artificial collection delay")
	for sample in [-0.119, -0.11, 0.03, NAN]:
		check(is_equal_approx(floor_ref.height_world(sample, Transform3D.IDENTITY), expected), "jitter, jumps and temporary loss preserve accepted height")
	var recentered := Transform3D(Basis(Vector3.UP, 0.7), Vector3(2.0, 0.3, -1.0))
	check(is_equal_approx(floor_ref.height_world(0.5, recentered), expected + 0.3), "recenter moves stored plane into new world coordinates")
	check(is_equal_approx(floor_ref.height_world(NAN, recentered), expected + 0.3), "floor remains stable after recenter")
	var moved_origin := recentered
	moved_origin.origin.y -= 0.1
	check(is_equal_approx(floor_ref.height_world(0.5, moved_origin), expected + 0.2), "explicit scene-origin movement transforms floor too")
	_test_app_source()
	return failures

func _test_app_source() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var app = load("res://scripts/main.gd").new()
	var origin := XROrigin3D.new()
	tree.root.add_child(origin)
	var anchor := NaretSpatialAnchor.new()
	var xr := FakeXR.new()
	var room := FakeRoom.new()
	room.available = true
	app.origin = origin
	app.anchor = anchor
	app.xr = xr
	app.room = room
	app._refresh_floor_reference()
	check(not anchor.floor_locked and room.reads == 0, "room scan cannot supply height when local floor is missing")
	xr.sample = -0.05
	anchor.floor_touch_source = "local_floor"
	anchor.floor_touch_offset_m = 0.03
	app._refresh_floor_reference()
	check(anchor.floor_locked and is_equal_approx(anchor.floor_y, -0.02), "optional local-floor touch correction remains applied")
	xr.sample = 0.05
	app._refresh_floor_reference()
	check(is_equal_approx(anchor.floor_y, -0.02), "app holds floor despite later different sample")
	anchor.floor_touch_offset_m = 0.04
	app._refresh_floor_reference()
	check(is_equal_approx(anchor.floor_y, -0.01), "deliberate fingertip recalibration updates correction on retained reference")
	anchor.floor_touch_offset_m = 0.03
	app._refresh_floor_reference()
	xr.sample = NAN
	app._refresh_floor_reference()
	check(is_equal_approx(anchor.floor_y, -0.02) and room.reads == 0, "temporary loss does not switch to room scan")
	origin.position.y = 0.2
	app._refresh_floor_reference()
	check(is_equal_approx(anchor.floor_y, 0.18), "app transforms stored floor when scene origin changes")
	anchor.floor_touch_source = "room_scan"
	app._refresh_floor_reference()
	check(is_equal_approx(anchor.floor_y, 0.15), "old room-scan correction is not misapplied to local floor")
	app.free()
	anchor.free()
	xr.free()
	room.free()
	origin.free()
