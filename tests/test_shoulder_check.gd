extends "res://tests/suite.gd"
## Response check needs a palm at a shoulder (12 Nov 2026): zone geometry on the
## calibrated mannequin, hold timing with tracking grace, evidence expiry, and the
## scenario refusing "he is not responding" when the hands were never there.
const Scenario = preload("res://scripts/scenario/scenario_controller.gd")
const ShoulderCheck = preload("res://scripts/tracking/shoulder_check.gd")

func _feed(check: RefCounted, palms: Array, frames: int) -> bool:
	var completed := false
	for i in frames:
		completed = check.observe(palms, 0.02) or completed
	return completed

func run() -> Array[String]:
	failures.clear()
	# Zone geometry, mannequin-local metres around the sternum (-Z toward the head).
	var left: Vector3 = ShoulderCheck.zone_centre(1)
	var right: Vector3 = ShoulderCheck.zone_centre(0)
	check(left.x > 0.0 and right.x < 0.0 and is_equal_approx(left.z, right.z), "the two zones mirror each other beside the midline")
	for item in [
		[left, 1, "zone centre is inside"],
		[left + Vector3(0.07, 0.0, -0.07), 1, "7 cm sideways and up the body is still inside"],
		[left + Vector3(0.0, 0.09, 0.0), 1, "palm 9 cm above the shoulder (gripping hand) is inside"],
		[left + Vector3(0.0, -0.05, 0.0), 1, "fingers 5 cm under the shoulder are inside"],
		[left + Vector3(0.09, 0.0, 0.0), -1, "9 cm further out is beyond the arm"],
		[left + Vector3(0.0, 0.0, -0.09), -1, "9 cm further toward the head is the ear, outside"],
		[left + Vector3(0.0, 0.12, 0.0), -1, "hand 12 cm above the shoulder is hovering, outside"],
		[Vector3.ZERO, -1, "the compression point is not a shoulder"],
		[Vector3(0.0, 0.0, -0.13), -1, "the neck between the zones is not a shoulder"],
		[Vector3(0.0, 0.0, -0.30), -1, "the forehead is not a shoulder"],
		[right, 0, "right zone centre is inside"],
	]:
		check(ShoulderCheck.zone_of(item[0]) == item[1], str(item[2]))
	# The zones lie toward the head on the real mannequin scene, like the forehead landmark.
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var root := Node3D.new()
	root.add_child(patient)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var forehead: Vector3 = patient.to_local(patient.gesture_forehead())
	check(forehead.z < -0.2, "forehead lies toward -Z on the mannequin (got %s)" % forehead)
	check(signf(forehead.z) == signf(left.z), "shoulder zones lie on the head side of the sternum")
	root.get_parent().remove_child(root)
	root.free()

	# Hold timing.
	var detector: RefCounted = ShoulderCheck.new()
	check(not _feed(detector, [left, null], 60), "inactive detector never counts")
	detector.active = true
	check(not _feed(detector, [left, null], 30), "0.6 s at the shoulder is not yet a hold")
	check(not detector.evidence_recent(), "no evidence before the hold completes")
	check(_feed(detector, [left, null], 12), "0.84 s at the shoulder completes the hold")
	check(detector.evidence_recent(), "evidence after the hold")
	check(not detector.shaken(), "a resting hand is not a shake")
	detector.reset()
	detector.active = true
	_feed(detector, [left, null], 20)
	_feed(detector, [null, null], 10) # 0.2 s dropout, inside the grace
	check(_feed(detector, [left, null], 22), "a 0.2 s tracking dropout keeps the hold")
	detector.reset()
	detector.active = true
	_feed(detector, [left, null], 20)
	_feed(detector, [Vector3(0.0, 0.3, 0.0), null], 60) # 1.2 s away: start over
	check(not _feed(detector, [left, null], 22), "1.2 s away from the shoulder restarts the hold")
	check(_feed(detector, [left, null], 20), "...and a fresh 0.8 s completes it")
	# Either hand, either shoulder; shaking is detected from travel.
	detector.reset()
	detector.active = true
	var wobble := [right + Vector3(0.0, 0.0, 0.0), right + Vector3(0.02, 0.0, 0.0)]
	var done := false
	for i in 44:
		done = detector.observe([null, wobble[i % 2]], 0.02) or done
	check(done and detector.touched_side() == 0, "the other hand on the right shoulder counts")
	check(detector.shaken(), "a wobbling hand counts as shaking")
	# Evidence expires.
	detector.reset()
	detector.active = true
	_feed(detector, [left, null], 42)
	_feed(detector, [null, null], 700) # 14 s
	check(detector.evidence_recent(), "evidence still valid after 14 s")
	_feed(detector, [null, null], 1500) # 44 s
	check(detector.evidence_recent(), "evidence still valid after 44 s: the instructor's question and its answer fit in")
	_feed(detector, [null, null], 100) # 46 s
	check(not detector.evidence_recent(), "evidence expired after 46 s")
	# Deactivation freezes the count, reactivation starts clean.
	detector.active = false
	check(not _feed(detector, [left, null], 60), "no count while inactive")

	# The scenario: a report without shoulder evidence is refused, with it accepted,
	# and without the key (desktop, controllers) taken as before.
	var scenario := Scenario.new()
	scenario.submit_action("start")
	scenario.submit_action("begin_check", {"source": "speech"})
	check(not scenario.submit_action("check_responsiveness", {"source": "speech", "shoulders_seen": false}), "report without shoulder evidence is refused")
	check(scenario.last_error == "error.shoulders_not_seen", "refusal names the shoulders (got %s)" % scenario.last_error)
	check(scenario.get_state_name() == "check_patient", "the step stays open")
	check(scenario.submit_action("check_responsiveness", {"source": "speech", "shoulders_seen": true}), "report with shoulder evidence is accepted")
	check(scenario.get_state_name() == "call_help", "...and moves on to the call")
	scenario.free()
	var plain := Scenario.new()
	plain.submit_action("start")
	plain.submit_action("begin_check")
	check(plain.submit_action("check_responsiveness", {"source": "desktop"}), "desktop report without the key is accepted")
	plain.free()
	for key in ["error.shoulders_not_seen", "coach.shake_firmly"]:
		for lang in ["en", "de", "pl"]:
			var text := NaretLanguage.text(key, lang)
			check(not text.is_empty() and text != key, "text %s exists in %s" % [key, lang])
	return failures
