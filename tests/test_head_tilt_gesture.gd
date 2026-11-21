extends "res://tests/suite.gd"
## Head tilt, chin lift (12 Nov 2026, presence only): both landmarks covered together
## for 0.5 s, either hand in either role, tracking grace, release on sustained loss.

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
	_feed(detector, [rest[1], rest[0]], 10)
	check(not detector.active, "0.2 s at the landmarks is a passing reach, not a tilt")
	_feed(detector, [rest[1], rest[0]], 16)
	check(detector.active, "both landmarks covered for 0.5 s activates, hands in either role")
	detector.reset()
	var loose := _hands(Vector3(0.05, 0.04, 0.0), Vector3(0.04, 0.0, 0.16))
	_feed(detector, loose, 26)
	check(detector.active, "hands within 8 cm of the forehead and 7 cm of the chin still count")
	detector.reset()
	var far := _hands(Vector3(0.12, 0.0, 0.0), Vector3(0.0, 0.0, 0.12))
	_feed(detector, far, 40)
	check(not detector.active, "a hand 12 cm beside the forehead does not count")
	detector.reset()
	_feed(detector, rest, 26)
	check(detector.active, "rest position activates")
	_feed(detector, [{}, {}], 5)
	check(detector.active, "brief dropout holds an existing animation")
	_feed(detector, [{}, {}], 9)
	check(not detector.active, "sustained loss releases the animation")
	detector.reset()
	_feed(detector, rest, 15)
	_feed(detector, [{}, {}], 5)
	_feed(detector, rest, 12)
	check(detector.active, "a short dropout inside the hold does not restart it")
	detector.reset()
	_feed(detector, rest, 15)
	_feed(detector, [{}, {}], 20)
	check(detector.state == "waiting", "tracking loss longer than the grace resets an unfinished hold")
	return failures
