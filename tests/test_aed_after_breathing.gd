extends "res://tests/suite.gd"
## 21 Nov 2026 (user): "Introduce the AED step only after the breathing check, even if the
## person bringing the AED arrives earlier." Marek is sent during the call; however long the
## call and the breathing check take, he comes back with the AED only once the breathing
## has been checked, and only then is the AED there to use.
const Helper = preload("res://scripts/scenario/aed_helper_director.gd")

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var scenario := NaretScenario.new()
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var anna: NaretBystander = load("res://scenes/bystander.tscn").instantiate()
	var marek: NaretBystander = load("res://scenes/bystander_male.tscn").instantiate()
	var model: Node3D = load("res://assets/models/aed.glb").instantiate()
	var device := NaretAED.new()
	var director := Helper.new()
	var world := Node3D.new()
	tree.root.add_child(world)
	world.add_child(model)
	for node in [scenario, patient, anna, marek, device, director]: tree.root.add_child(node)
	device.configure(model, patient)
	director.configure(scenario, anna, marek, patient, device)
	director.return_after_compressions = 0
	director.delivery_ready = func(): return true
	var delivered := [false]
	director.device_delivered.connect(func(): delivered[0] = true)

	for order: String in ["aed_first", "call_first"]:
		scenario.reset()
		scenario.start()
		delivered[0] = false
		for action in ["begin_check", "check_responsiveness"]: scenario.submit_action(action)
		var first := ["request_aed", "call_emergency"] if order == "aed_first" else ["call_emergency", "request_aed"]
		for action in first: check(scenario.submit_action(action), order + ": " + action)
		check(scenario.state == NaretScenario.State.CALL_HELP and not scenario.breathing_checked, order + ": the breathing check is still to come")
		# The errand takes far longer than his usual fetch time.
		for i in 120: director.advance(0.5)
		check(director.away and not director.presenting and not marek.visible, order + ": 60 s later, breathing not yet checked: he has NOT come back")
		check(not scenario.aed_available and not delivered[0], order + ": no AED to use before the breathing check")
		check(scenario.submit_action("check_breathing"), order + ": the breathing check")
		check(scenario.state == NaretScenario.State.CPR, order + ": CPR begins")
		director.advance(0.1)
		check(director.presenting and marek.visible, order + ": now he comes back with the AED (phase %s)" % director.phase)
		for i in 40:
			director.advance(0.5)
			if delivered[0]: break
		check(delivered[0] and scenario.aed_available, order + ": the AED step comes after the breathing check")
		director._end_errand(true)
		director.delivered = false

	for node in [world, scenario, patient, anna, marek, device, director]: node.free()
	return failures
