class_name NaretTwoHandPressCounter
extends RefCounted
## Runs one NaretPlacedPressCounter per palm, each with its own resting height, and reports the
## presses of the steadier palm, judged once while both rest. The headset sees the upper hand;
## the hidden lower one jitters about twice as much (four recordings, 2026-11-03). Because both palms are counted all along,
## changing to the other palm takes over its count instead of losing the press in progress:
## a single counter that changed palms during the first presses missed three in a row (16:03).
## Replayed against the QCPR manikin: 60/60 and 31/31 presses, none false.
## Same signals and fields as NaretPlacedPressCounter, so cpr_hand_zone.gd can use either.

signal placed(hand: String, rest_m: float)
signal lifted
signal pressed(depth_m: float)

const JITTER_WINDOW_S := 1.5
const SWITCH_RATIO := 0.8      # the other palm must be clearly steadier to take over

var state := "waiting"
var hand := ""
var rest_m := 0.0
var drop_m := 0.0
var pressing := false
var _counters := {}
var _counts := {"left": 0, "right": 0}
var _depths := {"left": [], "right": []}
var _reported := 0             # presses reported in this placement
var _base := {"left": 0, "right": 0}   # each palm's count when this placement began
var _steps := {"left": [], "right": []}
var _last := {"left": NAN, "right": NAN}
var _time_s := 0.0
var _decided := false          # the steadier palm is judged once, while both rest, then kept


func _init() -> void:
	for side in ["left", "right"]:
		var counter := NaretPlacedPressCounter.new()
		counter.hand_rule = side
		counter.pressed.connect(_on_press.bind(side))
		_counters[side] = counter


func update(delta: float, left: Dictionary, right: Dictionary) -> void:
	_time_s += delta
	var hands := {"left": left, "right": right}
	for side: String in hands:
		var height := float(hands[side].get("height", NAN))
		if is_finite(height) and is_finite(float(_last[side])) and hands[side].get("in_zone", false):
			_steps[side].append([_time_s, absf(height - float(_last[side]))])
		_last[side] = height
		while not _steps[side].is_empty() and float(_steps[side][0][0]) < _time_s - JITTER_WINDOW_S:
			_steps[side].pop_front()
		# A palm only counts on its own: the other palm is reported as absent to it.
		var alone := {"in_zone": false, "height": NAN}
		_counters[side].update(delta, hands[side] if side == "left" else alone, alone if side == "left" else hands[side])
	var placed_sides := []
	for side in ["left", "right"]:
		if _counters[side].state == "placed":
			placed_sides.append(side)
	if state == "waiting":
		if placed_sides.is_empty():
			return
		state = "placed"
		_base = _counts.duplicate()
		_reported = 0
		_decided = false
		hand = _steadier(placed_sides)
		placed.emit(hand, float(_counters[hand].rest_m))
	elif placed_sides.is_empty():
		state = "waiting"
		hand = ""
		pressing = false
		drop_m = 0.0
		lifted.emit()
		return
	# Steadiness tells the palms apart only at rest: while pressing, the upper hand moves most.
	# So judge once, when both palms have just been placed, and keep that palm until it is lost.
	var change := ""
	if hand not in placed_sides:
		change = placed_sides[0]
	elif not _decided and placed_sides.size() == 2 and not _counters.left.pressing and not _counters.right.pressing:
		_decided = true
		var best := _steadier(placed_sides)
		if best != hand and _jitter(best) < _jitter(hand) * SWITCH_RATIO:
			change = best
	if change != "":
		hand = change
		_catch_up()
	var current: NaretPlacedPressCounter = _counters[hand]
	rest_m = current.rest_m
	drop_m = current.drop_m
	pressing = current.pressing


func _on_press(depth_m: float, side: String) -> void:
	_counts[side] += 1
	_depths[side].append(depth_m)
	if state == "placed" and side == hand:
		_catch_up()


## Report every press the followed palm has counted in this placement and not yet reported.
func _catch_up() -> void:
	var counted: int = _counts[hand] - _base[hand]
	while _reported < counted:
		var index: int = _depths[hand].size() - (counted - _reported)
		pressed.emit(float(_depths[hand][index]))
		_reported += 1


func _steadier(sides: Array) -> String:
	if sides.size() == 1:
		return sides[0]
	return "left" if _jitter("left") <= _jitter("right") else "right"


## Median height change between frames over JITTER_WINDOW_S: the hidden hand's tracking noise.
func _jitter(side: String) -> float:
	var samples: Array = _steps[side]
	if samples.size() < 10:
		return INF
	var steps: Array[float] = []
	for entry in samples:
		steps.append(float(entry[1]))
	steps.sort()
	return steps[steps.size() / 2]
