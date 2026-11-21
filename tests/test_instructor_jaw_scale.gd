extends "res://tests/suite.gd"
func run() -> Array[String]:
	failures.clear()
	var main = load("res://scenes/main.tscn").instantiate()
	var instructor: NaretBystander = main.get_node("Instructor")
	check(is_equal_approx(instructor.speech_jaw_scale,0.3), "instructor has the reduced per-character mouth setting")
	main.remove_child(instructor)
	(Engine.get_main_loop() as SceneTree).root.add_child(instructor)
	instructor._rig._apply_mouth(1.0)
	for target in instructor._rig._morphs.get("jaw_open",[]):
		check(is_equal_approx(target.mesh.get_blend_shape_value(target.index),0.3), "full speech energy opens the instructor jaw only to the requested smaller range")
	for target in instructor._rig._morphs.get("mouth_open",[]):
		check(is_zero_approx(target.mesh.get_blend_shape_value(target.index)), "legacy face-tearing mouth remains off")
	instructor._rig._apply_mouth(0.0)
	for target in instructor._rig._morphs.get("jaw_open",[]):
		check(is_zero_approx(target.mesh.get_blend_shape_value(target.index)), "instructor mouth closes fully after speech")
	instructor.free()
	main.free()
	return failures
