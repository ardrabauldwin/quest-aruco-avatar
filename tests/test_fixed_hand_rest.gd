extends "res://tests/suite.gd"
const DT := 1.0 / 72.0

func sample(height: float) -> Dictionary:
	return {"in_zone": is_finite(height), "height": height, "seen": 26}

func hold(counter: NaretTwoHandPressCounter, left: float, right: float, frames := 50) -> void:
	for i in frames: counter.update(DT, sample(left), sample(right))

func press(counter: NaretTwoHandPressCounter, left_rest: float, right_rest: float) -> void:
	for i in 40:
		var drop := 0.045 * sin(PI * i / 40.0)
		counter.update(DT, sample(left_rest - drop if is_finite(left_rest) else NAN), sample(right_rest - drop if is_finite(right_rest) else NAN))
	hold(counter, left_rest, right_rest, 3)

func run() -> Array[String]:
	var counter := NaretTwoHandPressCounter.new()
	var counts := [0]
	counter.pressed.connect(func(_depth: float): counts[0] += 1)
	hold(counter, 0.04, NAN)
	check(counter._counters.left.state == "placed" and counter._counters.right.state == "waiting", "only the initially visible hand has a baseline")
	press(counter, 0.04, NAN)
	check(counts[0] == 1 and counter.calibration_locked, "first compression locks setup before further calibration")
	var rest: float = counter._counters.left.rest_m
	hold(counter, 0.045, 0.005, 90)
	check(is_equal_approx(counter._counters.left.rest_m,rest), "slow settling between compressions cannot modify the saved rest")
	# The chest is up (the calibrated palm sits at its rest), so the lower palm that
	# appears still may save its own rest late; counting stays with the upper palm.
	check(counter._counters.right.state == "placed" and is_equal_approx(counter._counters.right.rest_m,0.005), "a palm appearing still while the chest is up acquires a late baseline")
	check(counter.hand == "left", "the upper calibrated palm keeps counting after a late lower baseline")
	for i in 3: press(counter,NAN,0.005)
	check(counts[0] == 4, "the late-calibrated palm counts when the upper palm is lost: " + str(counts[0]))
	check(is_equal_approx(counter._counters.left.rest_m,rest), "extended tracking loss preserves the original rest")
	hold(counter,0.005,NAN,80)
	check(counts[0] == 4, "a returning hand below rest neither recalibrates nor generates a phantom stroke")
	hold(counter,0.04,NAN,4)
	press(counter,0.04,NAN)
	check(counts[0] == 5 and is_equal_approx(counter._counters.left.rest_m,rest), "return to the saved rest lets the calibrated hand count again without resetting totals")
	var both := NaretTwoHandPressCounter.new()
	var both_counts := [0]
	both.pressed.connect(func(_depth: float): both_counts[0] += 1)
	hold(both,0.02,0.06)
	press(both,0.02,0.06)
	hold(both,NAN,NAN,60)
	hold(both,0.02,0.06,4)
	press(both,0.02,0.06)
	check(both_counts[0] == 2, "both calibrated hands resume after a shared tracking gap with no duplicate or reset counts")
	check(is_equal_approx(both._counters.left.rest_m,0.02) and is_equal_approx(both._counters.right.rest_m,0.06), "each hand retains its separate original resting height")
	# Right-hand first-press detection must freeze a left hand whose setup window
	# would otherwise finish earlier in the same frame's left-to-right update loop.
	var ordered := NaretTwoHandPressCounter.new()
	hold(ordered,NAN,0.06)
	hold(ordered,0.01,0.06,19) # window closes at 0.27 s = 19.4 frames (0.3 s rest, 12 Nov 2026)
	ordered.update(DT,sample(0.01),sample(0.03))
	hold(ordered,0.01,0.03,60)
	check(ordered.calibration_locked and ordered._counters.left.state == "waiting", "new-hand calibration cannot race a first compression in the same update")
	var edge := NaretTwoHandPressCounter.new()
	hold(edge,NAN,0.06)
	hold(edge,0.01,0.06,19)
	edge.update(DT,sample(0.01),{"in_zone": false,"height": 0.03,"seen": 26})
	check(edge.pressing and edge.calibration_locked and edge._counters.left.state == "waiting", "a press beginning during the existing zone-exit grace also closes setup")
	var zone = load("res://addons/naret_upstream/avatar/cpr_hand_zone.tscn").instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(zone)
	zone.set_process(false)
	zone._placed_counter = counter
	zone.reset_placement()
	check(zone._placed_counter == null, "explicit setup reset discards frozen baselines so new placement can calibrate")
	zone._update_placed_counting(DT,false)
	hold(zone._placed_counter,0.08,NAN)
	check(not zone._placed_counter.calibration_locked and is_equal_approx(zone._placed_counter._counters.left.rest_m,0.08), "deliberate reset allows a new resting height")
	zone.free()
	return failures
