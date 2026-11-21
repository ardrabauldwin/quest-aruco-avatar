extends "res://tests/suite.gd"
## The hidden lower palm settles first and the first press locks setup before the
## upper palm was ever still. The upper palm must still get its saved rest later, so
## the counter can follow the palm the headset actually sees (9 Nov 2026 traces).
const DT := 1.0 / 72.0

func sample(height: float) -> Dictionary:
	return {"height": height, "in_zone": is_finite(height), "usable": true, "source": "palm"}

func stroke(counter: NaretTwoHandPressCounter, upper_rest: float, lower_rest: float, upper_travel: float, lower_travel: float) -> void:
	for i in 40:
		var s := sin(PI * i / 40.0)
		counter.update(DT, sample(upper_rest - upper_travel * s), sample(lower_rest - lower_travel * s))

func run() -> Array[String]:
	var counter := NaretTwoHandPressCounter.new()
	var counts := [0]
	counter.pressed.connect(func(_depth: float): counts[0] += 1)
	for i in 45:
		counter.update(DT, sample(NAN), sample(0.02))
	check(counter.hand == "right", "the lower palm alone completes setup first")
	# The upper palm appears already moving: one press locks setup before it was still.
	stroke(counter, 0.06, 0.02, 0.045, 0.025)
	check(counter.calibration_locked, "the first press locks setup")
	check(counter._counters.left.state != "placed", "the moving upper palm has no saved rest yet")
	for i in 45:
		counter.update(DT, sample(0.06), sample(0.02))
	check(counter._counters.left.state == "placed", "the upper palm completes setup after the lock during a pause")
	var before: int = counts[0]
	# Occluded lower palm shows 1.5 cm of a 4.5 cm stroke: below the 2 cm press start.
	for p in 20:
		stroke(counter, 0.06, 0.02, 0.045, 0.015)
	for i in 5:
		counter.update(DT, sample(0.06), sample(0.02))
	check(counter.hand == "left", "the counter follows the upper palm, not the damped lower one")
	check(counts[0] - before == 20, "all twenty strokes count through the upper palm: " + str(counts[0] - before))
	check(is_equal_approx(counter._counters.right.rest_m, 0.02), "the lower palm's saved rest is unchanged")
	# A palm lying still on a depressed chest still cannot save a rest after the lock.
	var depressed := NaretTwoHandPressCounter.new()
	for i in 45:
		depressed.update(DT, sample(NAN), sample(0.02))
	stroke(depressed, NAN, 0.02, 0.0, 0.025)
	check(depressed.calibration_locked, "lower palm alone locks setup")
	for i in 60:
		depressed.update(DT, sample(0.02), sample(-0.02))
	check(depressed._counters.left.state != "placed", "a palm still on a chest held 4 cm down acquires no late rest")
	for i in 45:
		depressed.update(DT, sample(0.06), sample(0.02))
	check(depressed._counters.left.state == "placed", "the same palm calibrates once the chest is back up")
	return failures
