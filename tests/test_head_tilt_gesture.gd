extends "res://tests/suite.gd"

func _hands(fore: Vector3, chin: Vector3) -> Array:
	return [{"palm": fore, "finger": fore}, {"palm": chin, "finger": chin}]

func _feed(detector: NaretHeadTiltGesture, hands: Array, frames: int) -> void:
	for i in frames:
		detector.observe(hands, Vector3.ZERO, Vector3(0, 0, 0.12), Vector3.UP, Vector3.FORWARD, 0.02)

func run() -> Array[String]:
	failures.clear()
	var detector := NaretHeadTiltGesture.new()
	var rest := _hands(Vector3.ZERO, Vector3(0, 0, 0.12))
	_feed(detector, [rest[0], {}], 40)
	check(not detector.active, "one hand never activates")
	_feed(detector, rest, 40)
	check(not detector.active, "two stationary nearby hands never activate")
	detector.reset()
	_feed(detector, rest, 18)
	var wrong := _hands(Vector3(0.02, 0, 0), Vector3(0.02, 0, 0.12))
	_feed(detector, wrong, 10)
	check(not detector.active, "sideways reaching does not activate")
	detector.reset()
	_feed(detector, rest, 18)
	var motion := _hands(Vector3(0, -0.009, -0.01), Vector3(0, 0.016, 0.12))
	_feed(detector, motion, 7)
	check(detector.active, "hold followed by coordinated motion activates")
	_feed(detector, [{}, {}], 5)
	check(detector.active, "brief dropout holds an existing animation")
	_feed(detector, [{}, {}], 9)
	check(not detector.active, "sustained loss releases the animation")
	detector.reset()
	_feed(detector, rest, 18)
	_feed(detector, motion, 2)
	check(not detector.active, "single motion spike cannot activate")
	_feed(detector, [{}, {}], 1)
	check(detector.state == "waiting", "tracking loss cannot preserve an unconfirmed gesture")
	return failures
