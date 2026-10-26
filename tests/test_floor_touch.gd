extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var samples: Array = []
	var head_y := 1.6
	var radius := 0.008
	# A hand at the menu or on a knee is never mistaken for the floor.
	var result := NAN
	for step in 30:
		result = NaretFloorTouch.feed(samples, Vector3(0, 1.3, 0), radius, step * 0.1, head_y)
	check(not is_finite(result) and samples.is_empty(), "a still hand near the head does not measure the floor")
	# A fingertip still descending restarts the hold.
	for step in 20:
		result = NaretFloorTouch.feed(samples, Vector3(0, 0.6 - step * 0.03, 0), radius, 3.0 + step * 0.1, head_y)
	check(not is_finite(result), "a moving fingertip is not accepted")
	# Resting with millimetre jitter for HOLD_S gives the mean tip height minus the radius.
	var start := 5.0
	for step in 16:
		var jitter := 0.002 if step % 2 == 0 else -0.002
		result = NaretFloorTouch.feed(samples, Vector3(0.1, 0.058 + jitter, 0.2), radius, start + step * 0.1, head_y)
		if is_finite(result):
			break
	check(is_finite(result), "a resting fingertip is accepted after the hold")
	check(absf(result - 0.050) < 0.003, "floor is the tip height minus the joint radius, got %s" % result)
	return failures
