class_name NaretEKG
extends Node
## Illustrative electrical traces, not diagnostic ECGs or a physiological model.
## PEA and the scenario's pulseless VT have electrical activity but no mechanical beat.

signal beat

enum Rhythm { SINUS, VT, VF, ASYSTOLE, PEA }
const LABELS := ["Sinus", "VT (pulseless)", "VF", "Asystole", "PEA"]
const DEFAULT_RATES := [75.0, 180.0, 0.0, 0.0, 65.0]
var rhythm: int = Rhythm.SINUS
var bpm := 75.0
var time := 0.0
var alarm := ""
var _last_beat_index := -1

func set_rhythm(new_rhythm: int, rate: float = -1.0) -> void:
	if new_rhythm < Rhythm.SINUS or new_rhythm > Rhythm.PEA:
		return
	rhythm = new_rhythm
	bpm = DEFAULT_RATES[rhythm] if rate < 0.0 or not is_finite(rate) else clampf(rate, 0.0, 300.0)
	if rhythm == Rhythm.VF or rhythm == Rhythm.ASYSTOLE:
		bpm = 0.0
	time = 0.0
	_last_beat_index = -1
	var new_alarm := ""
	if rhythm != Rhythm.SINUS:
		new_alarm = "SIMULATION: " + LABELS[rhythm]
	elif bpm < 50.0 or bpm > 120.0:
		new_alarm = "SIMULATION: rate outside 50–120/min"
	alarm = new_alarm

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if delta < 0.0 or not is_finite(delta):
		return
	time += delta
	if rhythm != Rhythm.SINUS or bpm <= 0.0:
		return
	# R peak is phase 0.25 in sample(); notify at exactly the same cycle position.
	var beat_index := int(floor(time * bpm / 60.0 - 0.25))
	if beat_index > _last_beat_index:
		_last_beat_index = beat_index
		beat.emit()

func sample(t: float) -> float:
	if not is_finite(t):
		return 0.0
	if rhythm == Rhythm.ASYSTOLE:
		return 0.0
	if rhythm == Rhythm.VF:
		return 0.36 * sin(TAU * t * 6.7) + 0.19 * sin(TAU * t * 9.3 + 0.7) + 0.1 * sin(TAU * t * 13.1 + 1.9)
	if bpm <= 0.0:
		return 0.0
	var phase := fposmod(t * bpm / 60.0, 1.0)
	if rhythm == Rhythm.VT:
		return 0.75 * sin(TAU * phase) + 0.2 * sin(2.0 * TAU * phase + 0.5)
	# P-QRS-T sum; PEA deliberately shares its organized electrical appearance.
	return 0.12 * _gaussian(phase, 0.10, 0.026) - 0.16 * _gaussian(phase, 0.215, 0.012) + 1.0 * _gaussian(phase, 0.25, 0.012) - 0.25 * _gaussian(phase, 0.285, 0.014) + 0.25 * _gaussian(phase, 0.47, 0.065)

func get_label() -> String:
	return LABELS[rhythm]

func has_mechanical_pulse() -> bool:
	return rhythm == Rhythm.SINUS and bpm > 0.0

static func _gaussian(value: float, center: float, width: float) -> float:
	var normalized := (value - center) / width
	return exp(-0.5 * normalized * normalized)
