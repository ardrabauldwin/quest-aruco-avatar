extends "res://tests/suite.gd"

const INPUTS := ["start", "reset", "begin_check", "check_responsiveness", "call_emergency", "check_breathing",
	"compression", "ventilation", "compression_only", "handover", "reassure"]
## The scenario state for each machine state: the machine splits two of them.
const SCENARIO_STATE := {
	NaretCprStateMachine.State.IDLE: NaretScenario.State.IDLE,
	NaretCprStateMachine.State.INTRO: NaretScenario.State.INTRO,
	NaretCprStateMachine.State.CHECK_PATIENT: NaretScenario.State.CHECK_PATIENT,
	NaretCprStateMachine.State.CALL_HELP: NaretScenario.State.CALL_HELP,
	NaretCprStateMachine.State.CHECK_BREATHING: NaretScenario.State.CALL_HELP,
	NaretCprStateMachine.State.COMPRESSIONS: NaretScenario.State.CPR,
	NaretCprStateMachine.State.BREATHS: NaretScenario.State.CPR,
	NaretCprStateMachine.State.COMPRESSION_ONLY: NaretScenario.State.CPR,
	NaretCprStateMachine.State.RECOVERY: NaretScenario.State.RECOVERY,
}

func run() -> Array[String]:
	failures.clear()
	_full_exercise()
	_wrong_order()
	_matches_scenario()
	_shadows_in_app()
	return failures

func _full_exercise() -> void:
	var fsm := NaretCprStateMachine.new()
	for input in ["start", "begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
		check(fsm.handle(input).accepted, "the normal flow accepts " + input)
	check(fsm.state == NaretCprStateMachine.State.COMPRESSIONS, "the flow reaches compressions")
	for _i in range(30): fsm.handle("compression")
	check(fsm.state == NaretCprStateMachine.State.BREATHS, "30 compressions lead to breaths")
	check(fsm.handle("compression").error == "error.ventilate_first", "a 31st compression is refused")
	fsm.handle("ventilation")
	check(fsm.state == NaretCprStateMachine.State.BREATHS, "one breath stays in breaths")
	fsm.handle("ventilation")
	check(fsm.state == NaretCprStateMachine.State.COMPRESSIONS and fsm.cycles == 1, "two breaths finish a cycle")
	check(fsm.handle("handover").accepted and fsm.state == NaretCprStateMachine.State.RECOVERY, "handover ends the exercise")
	check("digraph" in NaretCprStateMachine.to_dot(), "the machine exports a diagram")

func _shadows_in_app() -> void:
	var app: Node = load("res://scripts/main.gd").new()
	app._shadow_state_machine({"action": "start", "accepted": true})
	app._shadow_state_machine({"action": "begin_check", "accepted": false})
	check(app._fsm.state == NaretCprStateMachine.State.INTRO, "the app machine follows accepted events only")
	app._shadow_state_machine({"action": "begin_check", "accepted": true})
	check(app._fsm.state == NaretCprStateMachine.State.CHECK_PATIENT, "the app machine advances with the scenario")
	app.free()

func _wrong_order() -> void:
	var fsm := NaretCprStateMachine.new()
	check(not fsm.handle("check_breathing").accepted, "nothing but start works in idle")
	fsm.handle("start")
	fsm.handle("begin_check")
	check(fsm.handle("check_breathing").error == "error.check_responsiveness_first", "breathing before responsiveness is refused")
	check(fsm.handle("check_responsiveness", {"responsive": true}).error == "error.check_result", "a responsive report is refused")
	fsm.handle("check_responsiveness")
	check(fsm.handle("check_breathing").error == "error.call_first", "breathing before the call is refused")
	check(fsm.state == NaretCprStateMachine.State.CALL_HELP, "a refused input keeps the state")

func _matches_scenario() -> void:
	## Same random inputs into both machines: same acceptance and state at every step.
	var random := RandomNumberGenerator.new()
	random.seed = 20261031
	var compared := 0
	for run_index in range(300):
		var fsm := NaretCprStateMachine.new()
		var scenario := NaretScenario.new()
		scenario.cpr_witness_only = true
		var failed := false
		for step in range(400):
			# Favour the expected next input, so runs get deep instead of dying early.
			var options := fsm.available_inputs()
			var use_expected := not options.is_empty() and random.randf() < 0.9
			var input: String = options[random.randi() % options.size()] if use_expected else INPUTS[random.randi() % INPUTS.size()]
			if run_index % 3 == 0 and input == "handover" and step < 300: input = "compression"
			var ours: bool = fsm.handle(input).accepted
			var theirs := scenario.submit_action(input)
			compared += 1
			if ours != theirs or SCENARIO_STATE[fsm.state] != scenario.state:
				check(false, "run %d step %d input %s: machine %s/%s, scenario %s/%s" % [run_index, step, input, fsm.state_name(), ours, scenario.get_state_name(), theirs])
				failed = true
				break
		scenario.free()
		if failed: break
	print("NARET_FSM compared ", compared, " inputs")
