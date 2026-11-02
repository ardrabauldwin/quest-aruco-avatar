extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	# A box torso in mannequin space: 40 cm wide (x ±0.2, centred at +0.01),
	# 20 cm high, cut off at z = 0.30 toward the feet.
	var scan := PackedVector3Array()
	for x: float in [-0.19, 0.21]:
		for y: float in [0.0, 0.1, 0.2]:
			for z: float in [-0.5, 0.0, 0.3]:
				scan.append(Vector3(x, y, z))
	# Pinkies at y = 0.01 against a face 2 cm further toward the feet than the scan's.
	var pinky := func(x: float) -> Array:
		return [{"position": Vector3(x, 0.01, 0.34), "radius": 0.008},
			{"position": Vector3(x + 0.02, 0.01, 0.328), "radius": 0.008},
			{"position": Vector3(x + 0.04, 0.01, 0.335), "radius": 0.008}]
	var edge := NaretScanFitTouch.shift("edge", [pinky.call(-0.1), pinky.call(0.05)], scan)
	check(edge.is_equal_approx(Vector3(0, 0, 0.02)), "edge fit moves the scan's cut-off onto the pinkies, got %s" % [edge])
	var index := func(x: float) -> Array: return [{"position": Vector3(x, 0.1, 0.0), "radius": 0.007}]
	var sides := NaretScanFitTouch.shift("sides", [index.call(-0.2), index.call(0.24)], scan)
	check(sides.is_equal_approx(Vector3(0.01, 0, 0)), "side fit centres the scan between the index fingers, got %s" % [sides])
	check(NaretScanFitTouch.shift("sides", [index.call(0.0)], scan) == Vector3.ZERO, "one hand is no fit")
	var still: Array = []
	for i in 12:
		still.append(PackedVector3Array([Vector3(0.1 + 0.001 * (i % 2), 0, 0)]))
	check(NaretScanFitTouch.average(still)[0].is_equal_approx(Vector3(0.1005, 0, 0)), "a resting hand averages its samples")
	var moved := still.duplicate()
	moved.append(PackedVector3Array([Vector3(0.2, 0, 0)]))
	check(NaretScanFitTouch.average(moved).is_empty(), "a hand that moved fails the measurement")
	check(NaretScanFitTouch.average(still.slice(0, 5)).is_empty(), "too few samples fail the measurement")
	return failures
