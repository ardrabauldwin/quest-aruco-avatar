extends "res://tests/suite.gd"

func _flat_hand(surface_y: float, outlier := 0.0) -> PackedFloat32Array:
	# Ten joint estimates within a few millimetres; one may jump away.
	var estimates := PackedFloat32Array()
	for i in 10:
		estimates.append(surface_y + (i % 3 - 1) * 0.002)
	estimates[4] += outlier
	return estimates

func run() -> Array[String]:
	failures.clear()
	var samples: Array = []
	var palm := Vector3(0.1, 0.25, -0.3)
	var result := NAN
	# Too few joints (hand half out of view) never measures.
	for step in 30:
		result = NaretChestTouch.feed(samples, PackedFloat32Array([0.2, 0.2, 0.2]), palm, step * 0.1)
	check(not is_finite(result) and samples.is_empty(), "a hand with too few tracked joints is not accepted")
	# A bent hand spreads its joints over more than SPREAD_M.
	var bent := _flat_hand(0.21)
	bent[9] += 0.04
	result = NaretChestTouch.feed(samples, bent, palm, 4.0)
	check(not is_finite(result) and samples.is_empty(), "a bent hand is not accepted")
	# A moving hand restarts the hold.
	for step in 20:
		result = NaretChestTouch.feed(samples, _flat_hand(0.21), palm + Vector3(0, 0, step * 0.02), 5.0 + step * 0.1)
	check(not is_finite(result), "a moving hand is not accepted")
	# A still flat hand is accepted after HOLD_S; the median ignores a jumping joint.
	samples.clear()
	for step in 25:
		result = NaretChestTouch.feed(samples, _flat_hand(0.21, 0.008 if step % 4 == 0 else 0.0), palm, 10.0 + step * 0.1)
		if is_finite(result):
			break
	check(is_finite(result), "a still flat hand is accepted after the hold")
	check(absf(result - 0.21) < 0.002, "chest surface is the median joint estimate, got %s" % result)
	return failures
