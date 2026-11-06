extends "res://tests/suite.gd"

const DT := 1.0 / 72.0

var _counter: NaretPlacedPressCounter
var _depths: Array[float] = []
var _placed := 0
var _lifted := 0


func _step(left_height: float, left_in: bool = true, right_height: float = NAN, right_in: bool = false) -> void:
	_counter.update(DT, {"in_zone": left_in, "height": left_height}, {"in_zone": right_in, "height": right_height})


func _hold(height: float, seconds: float, jitter := 0.0) -> void:
	for i in int(seconds / DT):
		_step(height + jitter * sin(i * 1.7))


## One press per period: down by depth, back up by depth - recoil_short.
func _presses(rest: float, depth: float, count: int, period := 0.55, recoil_short := 0.0) -> void:
	var frames := int(period / DT)
	for p in count:
		for i in frames:
			var phase := float(i) / frames
			var down := depth * sin(phase * PI)
			if phase > 0.5:
				down = maxf(down, recoil_short)
			_step(rest - down)


func run() -> Array[String]:
	failures.clear()
	_counter = NaretPlacedPressCounter.new()
	_counter.pressed.connect(func(depth: float): _depths.append(depth))
	_counter.placed.connect(func(_hand: String, _rest: float): _placed += 1)
	_counter.lifted.connect(func(): _lifted += 1)

	# Hands come down onto the chest from 15 cm: arriving is not a press.
	for i in 60:
		_step(0.15 - i * 0.002, i > 40)
	check(_depths.is_empty(), "hands arriving from above are not counted")
	# Resting with tracking jitter: placed, still no presses.
	_hold(0.03, 1.0, 0.004)
	check(_placed == 1 and _counter.state == "placed", "hands held still are placed")
	check(absf(_counter.rest_m - 0.03) < 0.003, "the resting height is zero: " + str(_counter.rest_m))
	_hold(0.03, 2.0, 0.008)
	check(_depths.is_empty(), "resting jitter is not counted")

	_presses(0.03, 0.045, 5)
	check(_depths.size() == 5, "five presses count five: " + str(_depths.size()))
	check(_depths.all(func(d: float): return absf(d - 0.045) < 0.004), "depth is measured from the resting hand: " + str(_depths))

	# Hands that come back only part of the way still count every press.
	_depths.clear()
	_presses(0.03, 0.04, 6, 0.55, 0.018)
	check(_depths.size() >= 5, "presses without full recoil still count: " + str(_depths.size()))

	# Lifting the hands ends the placement; a new placement sets a new zero.
	_hold(0.03, 0.3)  # back at rest: the last unfinished press completes here
	for i in 50:
		_step(NAN, false)
	check(_lifted == 1 and _counter.state == "waiting", "lifted hands wait for a new placement")
	_depths.clear()
	_hold(0.05, 1.0)
	check(_placed == 2 and absf(_counter.rest_m - 0.05) < 0.003, "the next placement sets a new zero")
	_presses(0.05, 0.05, 3)
	check(_depths.size() == 3, "counting resumes from the new zero: " + str(_depths))

	# Rule "higher": the upper (higher) palm is chosen when both rest in the zone.
	var both := NaretPlacedPressCounter.new()
	both.hand_rule = "higher"
	for i in 60:
		both.update(DT, {"in_zone": true, "height": 0.02}, {"in_zone": true, "height": 0.06})
	check(both.state == "placed" and both.hand == "right", "the higher palm is used")

	# Default rule "smooth": the hidden lower hand jitters, so the steady palm is followed even
	# when the jittery one reads higher, and its presses are counted.
	var smooth := NaretPlacedPressCounter.new()
	var counted := [0]
	smooth.pressed.connect(func(_d: float): counted[0] += 1)
	var frame := [0]
	var tick := func(left_h: float, right_extra: float):
		frame[0] += 1
		var jitter := 0.004 if frame[0] % 2 == 0 else -0.004
		smooth.update(DT, {"in_zone": true, "height": left_h}, {"in_zone": true, "height": left_h + right_extra + jitter})
	for i in 150:
		tick.call(0.03, 0.01)
	for p in 6:
		for i in 40:
			tick.call(0.03 - 0.04 * sin(PI * i / 40.0), 0.01)
	check(smooth.hand == "left", "the steady palm is followed, not the jittery higher one: " + smooth.hand)
	check(counted[0] >= 5, "presses on the steady palm are counted: " + str(counted[0]))

	# Two-hand counter: the jittery lower palm is placed first, the steady upper palm a moment
	# later; changing to it keeps every press, including those before the change.
	var two := NaretTwoHandPressCounter.new()
	var two_counted := [0]
	two.pressed.connect(func(_d: float): two_counted[0] += 1)
	var f := [0]
	var both_tick := func(top: float, lower_in: bool, top_in: bool):
		f[0] += 1
		var j := 0.004 if f[0] % 2 == 0 else -0.004
		two.update(DT, {"in_zone": top_in, "height": top if top_in else NAN}, {"in_zone": lower_in, "height": top + 0.01 + j})
	for i in 50:
		both_tick.call(0.03, true, false)
	for i in 60:
		both_tick.call(0.03, true, true)
	for p in 8:
		for i in 40:
			both_tick.call(0.03 - 0.04 * sin(PI * i / 40.0), true, true)
	# Since 2026-11-05 the palm that presses leads; either palm may be shown here.
	check(two.hand in ["left", "right"], "the two-hand counter follows a placed palm: " + two.hand)
	check(two_counted[0] == 8, "every press is reported once: " + str(two_counted[0]))

	# A palm that is only partly tracked comes back 3.5 cm lower (headset, 2026-11-04): no press.
	var partial := NaretPlacedPressCounter.new()
	partial.hand_rule = "left"
	var partial_counted := [0]
	partial.pressed.connect(func(_d: float): partial_counted[0] += 1)
	var seen_step := func(height: float, seen: int):
		partial.update(DT, {"in_zone": true, "height": height, "seen": seen}, {"in_zone": false, "height": NAN})
	for i in 60:
		seen_step.call(0.06, 26)
	for i in 12:
		seen_step.call(0.06 - i * 0.003, 2 if i < 9 else 21)
	for i in 60:
		seen_step.call(0.025, 26)
	check(partial.state == "placed" and partial_counted[0] == 0, "a jump while partly tracked is no press: " + str(partial_counted[0]))
	for p in 3:
		for i in 40:
			seen_step.call(0.025 - 0.045 * sin(PI * i / 40.0), 26)
	check(partial_counted[0] == 3, "presses after the jump count from the new height: " + str(partial_counted[0]))

	# Changing palms mid-series does not add the other palm's own presses.
	var change := NaretTwoHandPressCounter.new()
	var change_counted := [0]
	change.pressed.connect(func(_d: float): change_counted[0] += 1)
	var g := [0]
	var change_tick := func(left_h: float, right_h: float):
		g[0] += 1
		var j := 0.004 if g[0] % 2 == 0 else -0.004
		change.update(DT, {"in_zone": is_finite(left_h), "height": left_h}, {"in_zone": true, "height": right_h + j})
	for i in 100:
		change_tick.call(0.03, 0.04)
	for p in 4:
		for i in 40:
			# The jittery right palm makes two presses out of each real one.
			var down := 0.04 * sin(PI * i / 40.0)
			change_tick.call(0.03 - down, 0.04 - 0.04 * absf(sin(TAU * i / 40.0)))
	for i in 60:
		change_tick.call(NAN, 0.04)  # left palm lost: carry on with the right one
	check(change.hand == "right", "a lost palm hands over to the other one: " + change.hand)
	check(change_counted[0] == 4, "the change adds no presses: " + str(change_counted[0]))

	# The hidden lower palm freezes (perfectly steady) while the upper palm presses
	# (headset, 2026-11-05: 8 of 23 counted when the steady palm was followed).
	var frozen := NaretTwoHandPressCounter.new()
	var frozen_counted := [0]
	frozen.pressed.connect(func(_d: float): frozen_counted[0] += 1)
	for i in 80:
		frozen.update(DT, {"in_zone": true, "height": 0.07 + (0.003 if i % 2 == 0 else -0.003)}, {"in_zone": true, "height": 0.04})
	for p in 10:
		for i in 40:
			frozen.update(DT, {"in_zone": true, "height": 0.07 - 0.045 * sin(PI * i / 40.0)}, {"in_zone": true, "height": 0.04})
	check(frozen_counted[0] == 10, "the pressing palm is counted, not the frozen hidden one: " + str(frozen_counted[0]))
	return failures
