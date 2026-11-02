extends "res://tests/suite.gd"
const Native = preload("res://scripts/scenario/ccbm_native.gd")
const Bridge = preload("res://scripts/scenario/ccbm_bridge.gd")

class HeldNative extends RefCounted:
	signal finish_old
	signal finish_new
	var calls := 0
	func infer(_observations: Array) -> Dictionary:
		calls += 1
		if calls == 1: await finish_old
		else: await finish_new
		return {"engine": "ccbm", "action": "begin_check", "probability": 0.99}

func run() -> Array[String]:
	failures.clear()
	var output := 'Time "(begin_check)" "(check_responsiveness)" "BLOCKED"\n1 0.95 0.03 0.02\n'
	var parsed := Native.parse_posterior(output, 1)
	check(parsed.get("engine") == "ccbm" and parsed.get("action") == "begin_check", "native posterior parsed")
	check(is_equal_approx(float(parsed.get("probability", 0)), 0.95), "unknown mass remains in denominator")
	check(Native.parse_posterior(output, 2).is_empty(), "incomplete observation consumption rejected")
	check(Native.parse_posterior('Time "begin_check" "BLOCKED"\n1 0.1 0.9', 1).get("action") == "BLOCKED", "blocked mass can win; no forced expected action")
	for invalid in ['Time "begin_check"\n1 -1', 'Time "begin_check"\n1 0.2', 'Time "begin_check"\n1 nan', 'Time "begin_check"\n1 inf', 'no posterior', 'Time "begin_check"\n0 1']:
		check(Native.parse_posterior(invalid, 1).is_empty(), "invalid posterior refused: " + invalid)
	var combined := Native.parse_posterior('Time "(ventilation_first)" "(ventilation_second)" "BLOCKED"\n2 0.4 0.55 0.05', 2)
	check(combined.get("action") == "ventilation" and is_equal_approx(float(combined.get("probability", 0)), 0.95), "legacy breath actions grouped without losing blocked mass")
	# Scheduling regression only. Real native-engine verification is performed
	# separately on Quest; this deliberately held transport is not inference.
	var scenario := NaretScenario.new()
	scenario.start()
	var bridge := Bridge.new()
	bridge.configure(scenario)
	var held := HeldNative.new()
	bridge._native = held
	var decisions := []
	bridge.decision.connect(func(action: String, _details: Dictionary): decisions.append(action))
	bridge.observe_action("begin_check")
	bridge.reset()
	bridge.observe_action("begin_check")
	held.finish_old.emit()
	check(bridge._pending and decisions.is_empty(), "old native result cannot release or advance a new pending exercise")
	held.finish_new.emit()
	check(not bridge._pending and decisions == ["begin_check"], "only the new exercise's native result advances")
	bridge.free()
	scenario.free()
	return failures
