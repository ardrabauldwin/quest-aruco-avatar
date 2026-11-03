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
	check(two.hand == "left", "the two-hand counter ends on the steady palm: " + two.hand)
	check(two_counted[0] == 8, "every press is reported once: " + str(two_counted[0]))
	return failures
