extends "res://tests/suite.gd"
## Pressing beside the green box is detected once, from palm bobbing on the chest outside
## the target, and never while the hand zone reports a heel on the box.
const OffTarget = preload("res://scripts/tracking/off_target_press.gd")

func _bob(detector: RefCounted, base: Vector3, on_target: bool, frames: int) -> bool:
	var hit := false
	for i in frames:
		var y := base.y - (0.025 if (i / 10) % 2 == 1 else 0.0) # 2.5 cm down every other 0.2 s
		hit = detector.observe([Vector3(base.x, y, base.z), null], on_target, 0.02) or hit
	return hit

func run() -> Array[String]:
	failures.clear()
	check(OffTarget.on_chest(Vector3(0.12, 0.0, 0.10)), "palm 12 cm beside the sternum at chest height is on the chest")
	check(OffTarget.on_chest(Vector3(0.0, -0.06, 0.22)), "palm on the upper belly, 6 cm lower, is on the chest")
	check(not OffTarget.on_chest(Vector3(0.0, 0.20, 0.0)), "palm 20 cm above the chest is in the air")
	check(not OffTarget.on_chest(Vector3(0.0, 0.0, 0.40)), "palm 40 cm toward the feet is off the chest")
	check(not OffTarget.on_chest(Vector3(0.0, -0.12, 0.0)), "palm 12 cm below the sternum is a tracking error")
	var detector: RefCounted = OffTarget.new()
	check(not _bob(detector, Vector3(0.12, 0.0, 0.10), true, 60), "bobbing with a heel on the box is a proper press, not a fault")
	check(not _bob(detector, Vector3(0.0, 0.20, 0.0), false, 60), "bobbing in the air is not a press")
	detector.reset()
	var hit := false
	for i in 30:
		hit = detector.observe([Vector3(0.12, 0.0, 0.10), null], false, 0.02) or hit
	check(not hit, "a hand resting still beside the box is not pressing")
	check(_bob(detector, Vector3(0.12, 0.0, 0.10), false, 60), "bobbing 2.5 cm beside the box is an off-target press")
	check(not _bob(detector, Vector3(0.12, 0.0, 0.10), false, 100), "...reported once within the cooldown")
	for i in 760:
		detector.observe([null, null], false, 0.02) # 15.2 s away
	check(_bob(detector, Vector3(-0.10, -0.02, 0.15), false, 60), "after the cooldown a new off-target press is reported")
	return failures
