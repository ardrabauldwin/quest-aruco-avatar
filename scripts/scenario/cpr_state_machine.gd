class_name NaretCprStateMachine
extends RefCounted
## Standalone finite state machine of the single-witness CPR exercise. Nothing in the app
## uses it yet: it states the flow of scenario_controller.gd as one explicit table, without
## the AED stages (switched off in this exercise). tests/test_cpr_state_machine.gd keeps the
## two in step by feeding both the same random inputs.
##
## Usage: var fsm := NaretCprStateMachine.new()
##        var result := fsm.handle("start")  # {accepted, state, error}
## Inputs are event names. Voice, hand tracking or buttons translate their signals into these.

signal state_changed(previous: int, current: int, input: String)

enum State { IDLE, INTRO, CHECK_PATIENT, CALL_HELP, CHECK_BREATHING, COMPRESSIONS, BREATHS, COMPRESSION_ONLY, RECOVERY }
const STATE_NAMES := ["IDLE", "INTRO", "CHECK_PATIENT", "CALL_HELP", "CHECK_BREATHING", "COMPRESSIONS", "BREATHS", "COMPRESSION_ONLY", "RECOVERY"]

const COMPRESSIONS_PER_CYCLE := 30
const BREATHS_PER_CYCLE := 2

## Every allowed transition: [from, input, to, guard]. An empty guard always passes.
const TRANSITIONS := [
	[State.INTRO, "begin_check", State.CHECK_PATIENT, ""],
	[State.CHECK_PATIENT, "check_responsiveness", State.CALL_HELP, "unresponsive"],
	[State.CALL_HELP, "call_emergency", State.CHECK_BREATHING, ""],
	[State.CHECK_BREATHING, "check_breathing", State.COMPRESSIONS, "not_breathing_normally"],
	[State.COMPRESSIONS, "compression", State.COMPRESSIONS, "cycle_incomplete"],
	[State.COMPRESSIONS, "compression", State.BREATHS, "last_compression"],
	[State.BREATHS, "ventilation", State.BREATHS, "breaths_incomplete"],
	[State.BREATHS, "ventilation", State.COMPRESSIONS, "last_breath"],
	[State.COMPRESSIONS, "compression_only", State.COMPRESSION_ONLY, ""],
	[State.BREATHS, "compression_only", State.COMPRESSION_ONLY, ""],
	[State.COMPRESSION_ONLY, "compression", State.COMPRESSION_ONLY, ""],
	[State.COMPRESSIONS, "handover", State.RECOVERY, ""],
	[State.BREATHS, "handover", State.RECOVERY, ""],
	[State.COMPRESSION_ONLY, "handover", State.RECOVERY, ""],
]

## Why a known input is refused in a state. Anything else is error.invalid_action.
const REJECTIONS := {
	State.CHECK_PATIENT: {"check_breathing": "error.check_responsiveness_first"},
	State.CALL_HELP: {"check_breathing": "error.call_first"},
	State.COMPRESSIONS: {"ventilation": "error.compress_first"},
	State.BREATHS: {"compression": "error.ventilate_first"},
	State.COMPRESSION_ONLY: {"ventilation": "error.compress_first"},
}

var state: int = State.IDLE
var cycle_compressions := 0
var cycle_breaths := 0
var total_compressions := 0
var total_breaths := 0
var cycles := 0
var history: Array[Dictionary] = []

func handle(input: String, details: Dictionary = {}) -> Dictionary:
	## Applies one input. A refused input never changes the state.
	if input == "start":
		_clear()
		return _move(State.INTRO, input)
	if input == "reset":
		_clear()
		return _move(State.IDLE, input)
	if state == State.IDLE or state == State.RECOVERY:
		return _refuse(input, "error.invalid_action")
	if input == "reassure":
		return _move(state, input) # Talking to the witness never changes the step.
	var error := "error.invalid_action"
	for row: Array in TRANSITIONS:
		if row[0] != state or row[1] != input:
			continue
		if _guard_passes(row[3], details):
			_apply_effect(input)
			return _move(row[2], input)
		if row[3] in ["unresponsive", "not_breathing_normally"]:
			error = "error.check_result"
	return _refuse(input, REJECTIONS.get(state, {}).get(input, error))

func available_inputs() -> Array[String]:
	## Inputs with a transition out of the current state.
	var inputs: Array[String] = []
	for row: Array in TRANSITIONS:
		if row[0] == state and row[1] not in inputs:
			inputs.append(row[1])
	return inputs

func state_name() -> String:
	return STATE_NAMES[state]

static func to_dot() -> String:
	## Graphviz text of the machine, for a report diagram.
	var lines := PackedStringArray(["digraph cpr {", "  rankdir=LR;", "  IDLE -> INTRO [label=\"start\"];"])
	for row: Array in TRANSITIONS:
		var label: String = row[1] if str(row[3]).is_empty() else "%s [%s]" % [row[1], row[3]]
		lines.append("  %s -> %s [label=\"%s\"];" % [STATE_NAMES[row[0]], STATE_NAMES[row[2]], label])
	lines.append("}")
	return "\n".join(lines)

func _guard_passes(guard: String, details: Dictionary) -> bool:
	match guard:
		"unresponsive": return not bool(details.get("responsive", false))
		"not_breathing_normally": return not bool(details.get("normal_breathing", false))
		"cycle_incomplete": return cycle_compressions + 1 < COMPRESSIONS_PER_CYCLE
		"last_compression": return cycle_compressions + 1 == COMPRESSIONS_PER_CYCLE
		"breaths_incomplete": return cycle_breaths + 1 < BREATHS_PER_CYCLE
		"last_breath": return cycle_breaths + 1 == BREATHS_PER_CYCLE
	return true

func _apply_effect(input: String) -> void:
	match input:
		"compression":
			total_compressions += 1
			cycle_compressions += 1
			if state == State.COMPRESSION_ONLY and cycle_compressions == COMPRESSIONS_PER_CYCLE:
				cycles += 1
				cycle_compressions = 0
		"ventilation":
			total_breaths += 1
			cycle_breaths += 1
			if cycle_breaths == BREATHS_PER_CYCLE:
				cycles += 1
				cycle_compressions = 0
				cycle_breaths = 0
		"compression_only":
			cycle_compressions = 0
			cycle_breaths = 0

func _move(next: int, input: String) -> Dictionary:
	var previous := state
	state = next
	history.append({"input": input, "accepted": true, "from": STATE_NAMES[previous], "to": STATE_NAMES[next]})
	if next != previous:
		state_changed.emit(previous, next, input)
	return {"accepted": true, "state": state, "error": ""}

func _refuse(input: String, error: String) -> Dictionary:
	history.append({"input": input, "accepted": false, "from": STATE_NAMES[state], "to": STATE_NAMES[state], "error": error})
	return {"accepted": false, "state": state, "error": error}

func _clear() -> void:
	cycle_compressions = 0
	cycle_breaths = 0
	total_compressions = 0
	total_breaths = 0
	cycles = 0
	history.clear()
