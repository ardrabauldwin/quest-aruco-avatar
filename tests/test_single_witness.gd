extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var scenario := NaretScenario.new()
	scenario.cpr_witness_only = true
	scenario.start()
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
		check(scenario.submit_action(action), "single-witness progression: " + action)
	for action in ["request_aed", "attach_aed", "shock", "reassess"]:
		check(not scenario.get_available_actions().has(action), "no AED menu action: " + action)
		check(not scenario.submit_action(action), "reject injected AED action: " + action)
	check(not scenario.submit_action("compression", {"source": "bystander"}), "witness cannot generate presses")
	check(scenario.compressions == 0, "no phantom compressions")
	for i in range(30):
		check(scenario.submit_action("compression", {"source": "hand_tracking", "measurement_verified": false}), "real trainee press accepted")
	check(scenario.submit_action("ventilation"), "first simulated breath")
	check(scenario.submit_action("ventilation"), "second simulated breath")
	check(scenario.submit_action("handover"), "can finish without AED")
	check(scenario.outcome == "simulated_handover", "finishing does not invent recovery")
	scenario.free()
	var layout := NaretMarkerLayout.new()
	check(layout.load_profile("res://data/user_marker_layout.cfg") == OK, "actual three-marker profile loads")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	check(scene.get_node("Bystanders").get_child_count() == 1, "exactly one witness in scene")
	check(not scene.has_node("SpatialAnchor/AED"), "no AED model in scene")
	check(scene.get_node("Instructor") is NaretBystander, "male character restored as separate instructor")
	var person := NaretBystander.new()
	var model := Node3D.new()
	model.name = "Model"
	person.add_child(model)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.position.y = 1.6
	model.add_child(mesh)
	(Engine.get_main_loop() as SceneTree).root.add_child(person)
	person.place_on_floor(Transform3D(Basis.IDENTITY, Vector3(2, 0.3, 1)))
	check(is_equal_approx(mesh.global_position.y - 0.5, 0.3), "character feet placed at scanned floor, independent of model origin")
	person.free()
	scene.free()
	return failures

