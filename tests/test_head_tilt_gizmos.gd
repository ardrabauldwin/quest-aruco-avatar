extends "res://tests/suite.gd"

class FakeMannequin extends Node3D:
	## The slice of NaretMannequin's API the gizmos read.
	func gesture_forehead() -> Vector3:
		return Vector3(0.1, 0.3, -0.4)
	func gesture_chin() -> Vector3:
		return Vector3(0.1, 0.25, -0.25)

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var mannequin := FakeMannequin.new()
	tree.root.add_child(mannequin)
	var gesture := NaretHeadTiltGesture.new()
	var gizmos: Node3D = load("res://scripts/tracking/head_tilt_gizmos.gd").new()
	tree.root.add_child(gizmos)
	gizmos.bind(mannequin, gesture)
	var forehead := gizmos.get_node_or_null("ForeheadArea") as MeshInstance3D
	var chin := gizmos.get_node_or_null("ChinArea") as MeshInstance3D
	check(forehead != null and forehead.global_position.is_equal_approx(mannequin.gesture_forehead()), "the forehead area sits on the gesture's forehead point")
	check(chin != null and chin.global_position.is_equal_approx(mannequin.gesture_chin()), "the chin area sits on the gesture's chin point")
	check(forehead != null and is_equal_approx((forehead.mesh as SphereMesh).radius, NaretHeadTiltGesture.FOREHEAD_RADIUS_M), "the forehead area shows the gesture's radius")
	check(chin != null and is_equal_approx((chin.mesh as SphereMesh).radius, NaretHeadTiltGesture.CHIN_RADIUS_M), "the chin area shows the gesture's radius")
	var alpha := func(area: MeshInstance3D) -> float:
		return (area.material_override as StandardMaterial3D).albedo_color.a
	var away := Vector3(9, 9, 9)
	var observe := func(hands: Array) -> void:
		gesture.observe(hands, mannequin.gesture_forehead(), mannequin.gesture_chin(), Vector3.UP, Vector3.FORWARD, 0.016)
		gizmos._process(0.0)
	observe.call([{"palm": away, "finger": away}, {"palm": away, "finger": away}])
	check(alpha.call(forehead) < 0.5 and alpha.call(chin) < 0.5, "no hand in a zone leaves both dim")
	observe.call([{"palm": mannequin.gesture_forehead(), "finger": away}, {}])
	check(alpha.call(forehead) > 0.5 and alpha.call(chin) < 0.5, "a palm on the forehead lights only the forehead zone")
	observe.call([{"palm": away, "finger": mannequin.gesture_chin()}, {}])
	check(alpha.call(forehead) < 0.5 and alpha.call(chin) > 0.5, "a fingertip on the chin lights only the chin zone")
	observe.call([{"palm": mannequin.gesture_forehead(), "finger": mannequin.gesture_chin()}, {}])
	check(alpha.call(forehead) > 0.5 and alpha.call(chin) < 0.5, "one hand cannot light both zones")
	observe.call([{"palm": mannequin.gesture_forehead(), "finger": away}, {"palm": away, "finger": mannequin.gesture_chin()}])
	check(alpha.call(forehead) > 0.5 and alpha.call(chin) > 0.5, "two hands in their roles light both zones")
	gesture.active = true
	gizmos._process(0.0)
	check(forehead.scale.is_equal_approx(Vector3.ONE) and chin.scale.is_equal_approx(Vector3.ONE), "an active gesture does not resize the zones")
	gizmos.free()
	mannequin.free()
	return failures
