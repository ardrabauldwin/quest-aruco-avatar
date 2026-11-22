extends "res://tests/suite.gd"
## NaretCprDetector on synthetic motion: counts a noisy rhythm, ignores the rest.

func run() -> Array[String]:
	failures.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 20 s at 110/min, 72 Hz: wrists 6 cm, forearms 6 cm, head 12 cm, one palm with jumps.
	var detector := NaretCprDetector.new()
	var expected := int(20.0 * 110.0 / 60.0)
	_feed(detector, rng, 110.0, true, 0.03)
	check(absi(detector.count - expected) <= 1, "noisy 110/min rhythm is counted (%d of %d)" % [detector.count, expected])
	check(absf(detector.rate_bpm - 110.0) < 8.0, "rate is about 110/min (%.0f)" % detector.rate_bpm)
	check(absf(detector.last_depth_m - 0.06) < 0.015, "depth follows the wrists (%.3f m)" % detector.last_depth_m)
	check(detector.probability > 0.4, "the rhythm is confident")
	# Random movement (no rhythm) and pressing beside the chest count nothing.
	var wander := NaretCprDetector.new()
	_feed(wander, rng, 0.0, true, 0.0)
	check(wander.count == 0, "random movement counts no strokes (%d)" % wander.count)
	var beside := NaretCprDetector.new()
	_feed(beside, rng, 110.0, false, 0.03)
	check(beside.count == 0, "pressing beside the chest counts nothing")
	# Quest frames come 8-30 ms apart; the detector resamples, so the rhythm still
	# confirms within seconds instead of flickering (take 16-55-19: 16.9 s before).
	var uneven := NaretCprDetector.new()
	var t := 0.0
	var first := -1.0
	while t < 20.0:
		var wrists := 0.05 + 0.03 * sin(TAU * 110.0 / 60.0 * t) + rng.randfn(0.0, 0.002)
		var channels := {"wrists": wrists, "forearms": 0.25 + 0.03 * sin(TAU * 110.0 / 60.0 * t), "head": 0.6}
		if not uneven.step(t, 0.0, channels, true, wrists).is_empty() and first < 0.0:
			first = t
		t += rng.randf_range(0.008, 0.030)
	check(absi(uneven.count - expected) <= 1, "uneven frame times still count every stroke (%d of %d)" % [uneven.count, expected])
	check(first >= 0.0 and first < 5.0, "uneven frame times confirm the rhythm early (%.1f s)" % first)
	# Top hand: both palms move together, the upper one 2.5 cm higher, with jitter and jumps.
	var stacked := NaretCprDetector.new()
	var flicker := false
	for i in int(12.0 * 72.0):
		t = i / 72.0
		var press := 0.03 * sin(TAU * 110.0 / 60.0 * t)
		var offset := 0.025 if t < 6.0 else -0.025 # hands swap after 6 s
		var palm_l := 0.04 + press + offset + rng.randfn(0.0, 0.004)
		var palm_r := 0.04 + press + rng.randfn(0.0, 0.004)
		if rng.randf() < 0.03:
			palm_r += 0.06 # tracking jump of the lower hand
		stacked.step(t, 1.0 / 72.0, {"palm_l": palm_l, "palm_r": palm_r, "head": 0.6}, true)
		if t > 2.0 and t < 6.0 and stacked.top_hand != "left":
			flicker = true
		if t > 9.0 and stacked.top_hand != "right":
			flicker = true
	check(not flicker, "the upper palm is found and the swap follows within 3 s")
	stacked.step(20.0, 0.0, {"head": 0.6}, true)
	stacked.step(23.0, 0.0, {"head": 0.6}, true)
	check(stacked.top_hand == "", "without both palms the top hand becomes unknown")
	return failures

func _feed(detector: NaretCprDetector, rng: RandomNumberGenerator, bpm: float, on_chest: bool, amplitude: float) -> void:
	var drift := 0.0
	for i in int(20.0 * 72.0):
		var t := i / 72.0
		var phase := sin(TAU * bpm / 60.0 * t) if bpm > 0.0 else 0.0
		drift += rng.randfn(0.0, 0.004) # slow wandering of the whole body
		var wrists := 0.05 + amplitude * phase + drift + rng.randfn(0.0, 0.002)
		var palm := wrists + rng.randfn(0.0, 0.003)
		if rng.randf() < 0.03:
			palm -= 0.08 # hand-tracking jump
		var channels := {"wrists": wrists, "forearms": 0.25 + amplitude * phase + drift,
			"palm_l": palm, "head": 0.6 + 2.0 * amplitude * phase + drift}
		detector.step(t, 1.0 / 72.0, channels, on_chest, wrists)
