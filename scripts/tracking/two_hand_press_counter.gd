class_name NaretTwoHandPressCounter
extends RefCounted
## Runs one NaretPlacedPressCounter per palm, each with its own resting height, and reports the
## presses of the steadier palm, judged once while both rest. The headset sees the upper hand;
## the hidden lower one jitters about twice as much (four recordings, 2026-11-03). A palm change
## carries on from the count reported so far: taking over the other palm's own count added
## presses nobody made when that palm was partly tracked (2026-11-04: three extra, one "10.6 cm").
## Replayed against the QCPR manikin: 60/60 and 31/31 presses, none false.
## Same signals and fields as NaretPlacedPressCounter, so cpr_hand_zone.gd can use either.

signal placed(hand: String, rest_m: float)
signal lifted
signal pressed(depth_m: float)

const JITTER_WINDOW_S := 1.5
const SWITCH_RATIO := 0.8      # the other palm must be clearly steadier to take over

## "count" (default): report a press whenever either palm's count since placement passes the
## count reported so far, and show the leading palm. Headset run 2026-11-05: the hidden lower
## palm froze, looked steadiest at rest and was followed: 8 of 23 presses counted while the
## upper palm pressed cleanly. "steady": the palm judged steadier at rest (until 2026-11-05).
var follow := "count"
## In "count", a palm's presses closer than this are one press shaken into several by tracking
## jitter (200 a minute; CPR is 100-120), so a jittery palm cannot out-count the pressing one.
const MIN_PRESS_INTERVAL_S := 0.3
var _valid := {"left": 0, "right": 0}         # presses per palm in this placement, "count" only
var _last_press_s := {"left": -INF, "right": -INF}

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
		_valid = {"left": 0, "right": 0}
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
	if follow == "count":
		pass  # the palm that presses leads; see _on_press
	elif hand not in placed_sides:
		change = placed_sides[0]
	elif not _decided and placed_sides.size() == 2 and not _counters.left.pressing and not _counters.right.pressing:
		_decided = true
		var best := _steadier(placed_sides)
		if best != hand and _jitter(best) < _jitter(hand) * SWITCH_RATIO:
			change = best
	if change != "":
		hand = change
		_base[hand] = _counts[hand] - _reported
	if hand not in placed_sides:
		hand = placed_sides[0]
	var current: NaretPlacedPressCounter = _counters[hand]
	rest_m = current.rest_m
	drop_m = current.drop_m
	pressing = current.pressing


func _on_press(depth_m: float, side: String) -> void:
	_counts[side] += 1
	_depths[side].append(depth_m)
	if state != "placed":
		return
	if follow == "count":
		if _time_s - float(_last_press_s[side]) < MIN_PRESS_INTERVAL_S:
			return
		_last_press_s[side] = _time_s
		_valid[side] += 1
		if _valid[side] > _reported:
			hand = side
			_reported += 1
			pressed.emit(depth_m)
	elif side == hand:
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
