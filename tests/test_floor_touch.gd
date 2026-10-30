extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var samples: Array = []
	var radius := 0.008
	var result := NAN
	# A fingertip still descending restarts the hold.
	for step in 20:
		result = NaretFloorTouch.feed(samples, Vector3(0, 0.6 - step * 0.03, 0), radius, step * 0.1)
	check(not is_finite(result), "a moving fingertip is not accepted")
	# Resting with millimetre jitter for HOLD_S gives the mean tip height minus the radius.
	var start := 5.0
	var held := 0.0
	for step in 45:
		var jitter := 0.002 if step % 2 == 0 else -0.002
		held = step * 0.1
		result = NaretFloorTouch.feed(samples, Vector3(0.1, 0.058 + jitter, 0.2), radius, start + held)
		if is_finite(result):
			break
	check(is_finite(result), "a resting fingertip is accepted after the hold")
	check(held >= NaretFloorTouch.HOLD_S - 0.001, "a shorter rest is not accepted, got %s" % held)
	check(absf(result - 0.050) < 0.003, "floor is the tip height minus the joint radius, got %s" % result)
	return failures
