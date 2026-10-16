extends SceneTree
## Explicit live integration check. Requires server.py on localhost:8766.
var scenario: NaretScenario
var bridge: Node
var decisions := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func report(text: String) -> void:
	var before := decisions
	bridge.observe_speech(text)
	var deadline := Time.get_ticks_msec() + 12000
	while decisions == before and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	if decisions == before:
		printerr("FAIL live CCBM: report did not advance: ", text)
		failed = true

func _run() -> void:
	scenario = NaretScenario.new()
	scenario.cpr_witness_only = true
	root.add_child(scenario)
	bridge = load("res://scripts/scenario/ccbm_bridge.gd").new()
	bridge.configure(scenario)
	root.add_child(bridge)
	bridge.endpoint = "http://127.0.0.1:8766/infer"
	bridge.decision.connect(func(action: String, details: Dictionary):
		if scenario.submit_action(action, details): decisions += 1)
	bridge.status_changed.connect(func(status: String): print("CCBM_STATUS ", status))
	scenario.event_recorded.connect(bridge.observe_accepted)
	await report("Start exercise")
	await report("The scene is safe")
	await report("He is not responding")
	await report("Anna, please call 112")
	await report("He is not breathing normally")
	if scenario.state != NaretScenario.State.CPR: failed = true
	for i in range(30): scenario.submit_action("compression", {"source": "test"})
	await report("I have given the first breath")
	await report("I have given the second breath")
	if scenario.cycles != 1: failed = true
	for i in range(30): scenario.submit_action("compression", {"source": "test"})
	var before_pair := decisions
	if not bridge.observe_breath_pair(): failed = true
	var pair_deadline := Time.get_ticks_msec() + 12000
	while decisions < before_pair + 2 and Time.get_ticks_msec() < pair_deadline:
		await create_timer(0.02).timeout
	if decisions != before_pair + 2 or scenario.cycles != 2:
		failed = true
		printerr("FAIL live CCBM: completed breath pair must produce exactly two accepted decisions")
	if bridge.observe_breath_pair():
		failed = true
		printerr("FAIL live CCBM: duplicate pair outside the breath step must be rejected")
	await report("Hand over the patient")
	if scenario.state != NaretScenario.State.RECOVERY: failed = true
	print("LIVE_CCBM_FAIL" if failed else "LIVE_CCBM_PASS: Godot -> HTTP -> native CCBM -> scenario, no progression buttons")
	quit(1 if failed else 0)
