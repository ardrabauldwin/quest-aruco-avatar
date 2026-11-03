class_name NaretPlacedPressCounter
extends RefCounted
## Counts compressions from where the hands rest on the chest, not from where they came from.
##
## 1. waiting: a hand lies in the chest zone (the 14 x 14 cm green area, 8 cm deep) and holds
##    still for PLACE_STILL_S -> "placed". Its resting height becomes zero, so an avatar that is
##    a little too big or too high does not change the measured depth. The higher palm is the
##    upper hand, the one the headset sees; it is used until the hands are lifted.
## 2. placed: a press starts PRESS_START_M below zero and counts when the hand comes back to
##    within RETURN_M of zero, or recoils RECOIL_M and starts the next press. Depth is the
##    deepest point below zero.
## 3. no hand in the zone for LIFT_S -> waiting again; the next placement sets a new zero.
## Heights are metres along the chest normal, positive above the chest surface.

signal placed(hand: String, rest_m: float)
signal lifted
signal pressed(depth_m: float)

const PLACE_STILL_S := 0.5
const STILL_RANGE_M := 0.010   # palm jitter at rest stays within this
const PRESS_START_M := 0.020   # resting jitter on the Quest reached 1.5-2.8 cm of "travel"
const RETURN_M := 0.010
const RECOIL_M := 0.015        # hands that do not come fully back up between presses
const MAX_DEPTH_M := 0.10      # deeper is a tracking jump, not a press
const LIFT_S := 0.5
const LOST_SWITCH_S := 0.3     # upper hand unseen this long: carry on with the other one
const JITTER_WINDOW_S := 1.5   # half a second while placing was too short to tell the hands apart
const CONFIRM_PRESSES := 3     # "smooth" keeps checking the hand choice until this many presses

## Which palm to follow once placed: "smooth" (default: the steadier palm while still; the
## headset sees the upper hand, the hidden lower one jitters about twice as much: four headset
## recordings on 2026-11-03, 0.2-0.4 vs 0.4-0.7 mm per frame), "higher", "seen" (more tracked
## joints; the headset reported 26 for both hands, so it does not tell them apart), or a fixed
## "left"/"right" for replays.
var hand_rule := "smooth"
var state := "waiting"
var hand := ""
var rest_m := 0.0
var drop_m := 0.0
var pressing := false
var max_drop_m := 0.0
var _low_m := 0.0
var _history := {"left": [], "right": []}   # [time_s, height_m] while in the zone
var _seen := {"left": 0, "right": 0}
var _steps := {"left": [], "right": []}   # [time_s, |height change|] over JITTER_WINDOW_S
var _last_height := {"left": NAN, "right": NAN}
var _presses_since_placed := 0
var _time_s := 0.0
var _away_s := 0.0
var _lost_s := 0.0


## left/right: {"in_zone": bool, "height": float (NAN when untracked), optional "seen": int}.
func update(delta: float, left: Dictionary, right: Dictionary) -> void:
	_time_s += delta
	var hands := {"left": left, "right": right}
	for side: String in hands:
		_seen[side] = int(hands[side].get("seen", 0))
		var h: Dictionary = hands[side]
		if h.get("in_zone", false) and is_finite(float(h.get("height", NAN))):
			_history[side].append([_time_s, float(h.height)])
		else:
			_history[side].clear()
		while not _history[side].is_empty() and float(_history[side][0][0]) < _time_s - PLACE_STILL_S:
			_history[side].pop_front()
		var height := float(h.get("height", NAN))
		if is_finite(height) and is_finite(float(_last_height[side])):
			_steps[side].append([_time_s, absf(height - float(_last_height[side]))])
		_last_height[side] = height
		while not _steps[side].is_empty() and float(_steps[side][0][0]) < _time_s - JITTER_WINDOW_S:
			_steps[side].pop_front()
	var any_in_zone: bool = left.get("in_zone", false) or right.get("in_zone", false)
	_away_s = 0.0 if any_in_zone else _away_s + delta
	if state == "waiting":
		_try_place()
		return
	if _away_s > LIFT_S:
		_reset_to_waiting()
		lifted.emit()
		return
	var current: Dictionary = hands[hand]
	var other_side := "right" if hand == "left" else "left"
	var other: Dictionary = hands[other_side]
	if not is_finite(float(current.get("height", NAN))):
		_lost_s += delta
		if _lost_s > LOST_SWITCH_S and other.get("in_zone", false) and is_finite(float(other.get("height", NAN))):
			# Continue on the other palm from the same depth: stacked palms sit cm apart.
			rest_m = float(other.height) + drop_m
			hand = other_side
			_lost_s = 0.0
		return
	_lost_s = 0.0
	# During the first presses, move to the other palm if it is clearly steadier: the hidden
	# lower hand jitters about twice as much as the upper one the headset sees.
	if hand_rule == "smooth" and _presses_since_placed < CONFIRM_PRESSES and other.get("in_zone", false) \
			and is_finite(float(other.get("height", NAN))) and _jitter(other_side) < _jitter(hand) * 0.8:
		rest_m = float(other.height) + (rest_m - float(current.height))  # carry on at the same depth
		hand = other_side
		current = other
	var height := float(current.height)
	drop_m = rest_m - height
	if not pressing:
		if drop_m >= PRESS_START_M:
			pressing = true
			max_drop_m = drop_m
			_low_m = drop_m
		elif absf(drop_m) < RETURN_M and _is_still(hand):
			rest_m = _mean(hand)  # follow a slowly settling rest between presses
		return
	if drop_m > MAX_DEPTH_M:
		pressing = false  # a tracking jump: no count
		return
	if drop_m > max_drop_m:
		max_drop_m = drop_m
		_low_m = drop_m
	_low_m = minf(_low_m, drop_m)
	if drop_m <= RETURN_M:
		_finish()
	elif max_drop_m - _low_m >= RECOIL_M and drop_m - _low_m > 0.004:
		# Recoiled part of the way, now going down again: count it and start the next press.
		_finish()
		pressing = true
		max_drop_m = drop_m
		_low_m = drop_m


func _finish() -> void:
	pressing = false
	_presses_since_placed += 1
	pressed.emit(max_drop_m)


func _try_place() -> void:
	var still := []
	for side: String in ["left", "right"]:
		if _is_still(side):
			still.append(side)
	if still.is_empty():
		return
	hand = still[0]
	if hand_rule in ["left", "right"]:
		if hand_rule not in still:
			return
		hand = hand_rule
	elif still.size() == 2:
		if hand_rule == "smooth":
			hand = "left" if _jitter("left") <= _jitter("right") else "right"
		elif hand_rule == "seen" and _seen.left != _seen.right:
			hand = "left" if _seen.left > _seen.right else "right"
		elif _mean("right") > _mean("left"):
			hand = "right"
	rest_m = _mean(hand)
	drop_m = 0.0
	_presses_since_placed = 0
	state = "placed"
	placed.emit(hand, rest_m)


func _reset_to_waiting() -> void:
	state = "waiting"
	hand = ""
	pressing = false
	drop_m = 0.0
	_lost_s = 0.0


func _is_still(side: String) -> bool:
	var samples: Array = _history[side]
	if samples.size() < 5 or _time_s - float(samples[0][0]) < PLACE_STILL_S * 0.9:
		return false
	var low := INF
	var high := -INF
	for entry in samples:
		low = minf(low, float(entry[1]))
		high = maxf(high, float(entry[1]))
	return high - low <= STILL_RANGE_M


func _mean(side: String) -> float:
	var samples: Array = _history[side]
	var total := 0.0
	for entry in samples:
		total += float(entry[1])
	return total / maxf(1.0, samples.size())


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
