class_name NaretTwoHandPressCounter
extends RefCounted
## Each hand has a fixed setup baseline. ONE stroke state receives movement from
## a selected usable hand; the other hand never runs a parallel press counter.
signal placed(hand: String, rest_m: float)
signal lifted
signal pressed(depth_m: float)

const MIN_PRESS_INTERVAL_S := 0.3
var calibration_locked := false
var state := "waiting"
var hand := ""
var rest_m := 0.0
var drop_m := 0.0
var pressing := false
var _counters := {} # Setup collectors only, never updated after their baseline is saved.
var _away := {"left": 0.0, "right": 0.0}
var _time_s := 0.0
var _reported := 0
var _last_press_s := -INF
var _source := ""
var _offset := 0.0 # Handoff continuity only; never changes either saved baseline.
var _top := 0.0
var _peak := 0.0
var _recoil_top := 0.0
var _recovering := false
var _reanchor_after_stroke := false

func _init() -> void:
	for side in ["left", "right"]:
		var collector := NaretPlacedPressCounter.new()
		collector.hand_rule = side
		_counters[side] = collector

func update(delta: float, left: Dictionary, right: Dictionary) -> void:
	_time_s += delta
	var inputs := {"left": left, "right": right}
	var hands := {"left": NaretPlacedPressCounter._trusted(left), "right": NaretPlacedPressCounter._trusted(right)}
	for side in ["left", "right"]:
		_away[side] = 0.0 if inputs[side].get("in_zone", false) else float(_away[side]) + delta
	# Close setup before updating either collector, including a press starting
	# during the existing short zone-exit grace. A late hand cannot win a race.
	if not calibration_locked:
		for side in ["left", "right"]:
			if _usable(side, hands) and _raw_drop(side, hands) >= NaretPlacedPressCounter.PRESS_START_M:
				calibration_locked = true
				break
	# A palm that has no saved rest yet may still collect one after the lock, but only
	# while the chest is up: no press in progress and every calibrated palm within the existing 1 cm return tolerance
	# of its own rest. A palm lying still on a depressed chest would save a
	# wrong rest. On the headset the lower, occluded palm often settles first and the
	# first press locks setup before the upper palm was ever still; the counter then
	# followed the damped lower palm for the whole exercise (9 Nov 2026 traces: 7 of
	# about 25 strokes counted). A placed collector never changes its saved baseline.
	var chest_up := not pressing
	for side in ["left", "right"]:
		if _usable(side, hands) and _raw_drop(side, hands) >= NaretPlacedPressCounter.RETURN_M:
			chest_up = false
	if not calibration_locked or chest_up:
		for side in ["left", "right"]:
			var collector: NaretPlacedPressCounter = _counters[side]
			if collector.state == "placed": continue
			var absent := {"in_zone": false, "height": NAN}
			collector.update(delta, hands[side] if side == "left" else absent, absent if side == "left" else hands[side])
			if collector.state == "placed": collector.calibration_locked = true
	var candidates: Array[String] = []
	for side in ["left", "right"]:
		if _usable(side, hands): candidates.append(side)
	if candidates.is_empty():
		if state == "placed": lifted.emit()
		state = "waiting"
		hand = ""
		pressing = false # The interrupted stroke cannot be reconstructed through a gap.
		drop_m = 0.0
		_source = ""
		_recovering = calibration_locked
		return
	var chosen := hand if hand in candidates else candidates[0]
	# Choose the upper measured hand on acquisition, not a fixed left preference.
	# During a stroke the established handoff rules preserve the shared phase.
	if not pressing:
		# Setup may finish on different frames and tracking can return at different
		# times. Between strokes prefer the higher SAVED rest, never an instant
		# noisy height. During a stroke keep the shared phase and current source.
		for side in candidates:
			if _counters[side].rest_m > _counters[chosen].rest_m: chosen = side
	elif hand not in candidates:
		for side in candidates:
			if float(hands[side].height) > float(hands[chosen].height): chosen = side
	# Keep a usable selected palm. Relative displacement of the other hand
	# does not establish that the selected hand is frozen or wrong.
	var raw := _raw_drop(chosen, hands)
	var source := str(hands[chosen].get("source", "heel"))
	if state == "waiting":
		state = "placed"
		hand = chosen
		rest_m = _counters[hand].rest_m
		_source = source
		_offset = 0.0
		drop_m = raw
		# First reacquired reading only anchors NEW movement. It is not a press,
		# and need not reach the original resting height. Saved rest stays fixed.
		_top = maxf(0.0, raw) if _recovering else 0.0
		_peak = raw
		_recoil_top = raw
		placed.emit(hand, rest_m)
		return
	if chosen != hand or source != _source:
		# Wrist/palm estimator changes are handled like hand changes: preserve the
		# shared stroke and align the first new reading without counting its jump.
		# Missing tracking or an estimator change needs continuity alignment.
		if pressing:
			_offset = drop_m - raw
		else:
			_offset = 0.0
			# Every idle source change needs a fresh reference, even when the old
			# palm still reports tracking. A returned hand's depth is not a stroke.
			_top = maxf(0.0, raw)
			drop_m = raw
		hand = chosen
		rest_m = _counters[hand].rest_m
		_source = source
		return
	if _reanchor_after_stroke:
		# Handoff alignment belongs only to the interrupted physical stroke.
		# Keeping it across later strokes can absorb their entire movement.
		_offset = 0.0
		_top = maxf(0.0, raw)
		drop_m = raw
		pressing = false
		_reanchor_after_stroke = false
		return
	drop_m = raw + _offset
	if not pressing:
		# Lifting above the saved rest is not compression. Never move the
		# cycle reference above that rest, including after a tracking gap.
		_top = minf(_top, maxf(0.0, drop_m))
		if drop_m - _top >= NaretPlacedPressCounter.PRESS_START_M:
			calibration_locked = true
			pressing = true
			_peak = drop_m
			_recoil_top = drop_m
		return
	if drop_m > _peak:
		_peak = drop_m
		_recoil_top = drop_m
	_recoil_top = minf(_recoil_top, drop_m)
	if drop_m - _top <= NaretPlacedPressCounter.RETURN_M:
		_finish()
	elif _peak - _recoil_top >= NaretPlacedPressCounter.RECOIL_M:
		var next_top := maxf(0.0, _recoil_top)
		# Complete on sufficient upward recovery, including the final stroke
		# when the learner stops. No renewed descent is required to count it.
		_finish()
		# Continue following recovery while idle. A new stroke must descend
		# PRESS_START_M from that recovered level; a small bounce cannot arm it.
		_top = next_top

func _usable(side: String, hands: Dictionary) -> bool:
	return _counters[side].state == "placed" and float(_away[side]) <= NaretPlacedPressCounter.LIFT_S \
		and is_finite(float(hands[side].get("height", NAN)))

func _raw_drop(side: String, hands: Dictionary) -> float:
	return float(_counters[side].rest_m) - float(hands[side].height)

func _finish() -> void:
	pressing = false
	_reanchor_after_stroke = not is_zero_approx(_offset)
	if _time_s - _last_press_s < MIN_PRESS_INTERVAL_S: return
	_last_press_s = _time_s
	_reported += 1
	pressed.emit(maxf(0.0, _peak))
