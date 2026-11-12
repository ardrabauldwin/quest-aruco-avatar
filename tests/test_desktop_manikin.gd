extends "res://tests/suite.gd"
## Desktop has no hand tracking: keys C and V drive the simulated manikin, which must
## reach the scenario as strokes and breaths, and must never press by itself.

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var scenario := NaretScenario.new()
	scenario.cpr_witness_only = true
	tree.root.add_child(scenario)
	var qcpr := NaretQcprManager.new()
	qcpr.scenario = scenario
	tree.root.add_child(qcpr)
	qcpr.set_simulator_auto_mode(false)
	qcpr.sim_backend.connect_device()
	qcpr.trigger_manual_compression(55.0)
	check(scenario.compressions == 0, "C before CPR counts nothing")
	for action in ["start", "begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
		scenario.submit_action(action, {"source": "test"})
	check(scenario.state == NaretScenario.State.CPR, "scenario reached CPR")
	for i in range(10): await tree.process_frame
	check(scenario.compressions == 0, "manual mode never presses by itself")
	for i in range(30): qcpr.trigger_manual_compression(55.0)
	check(scenario.cycle_compressions == 30, "30 x C give 30 strokes (got %d)" % scenario.cycle_compressions)
	for i in range(2): qcpr.trigger_manual_ventilation(500.0)
	check(scenario.cycles == 1 and scenario.cycle_compressions == 0, "2 x V finish the 30:2 cycle")
	qcpr.free()
	scenario.free()
	return failures
