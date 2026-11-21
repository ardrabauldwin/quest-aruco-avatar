extends "res://tests/suite.gd"
## Breathing check needs the headset at the patient's face (12 Nov 2026): the box around
## the mouth, the 3 s hold, the 10 s hint, evidence expiry, and the scenario refusing
## "he is not breathing normally" without it.
const Scenario = preload("res://scripts/scenario/scenario_controller.gd")
const FaceCheck = preload("res://scripts/tracking/face_check.gd")

func _feed(check: RefCounted, offset: Variant, frames: int) -> bool:
	var completed := false
	for i in frames:
		completed = check.observe(offset, 0.02) or completed
	return completed

func run() -> Array[String]:
	failures.clear()
	# Offsets from the mouth, mannequin-local metres: +Z toward the feet, +Y up.
	for item in [
		[Vector3(0.20, 0.20, 0.0), true, "cheek over the mouth from the side, 20 cm up"],
		[Vector3(-0.28, 0.35, 0.10), true, "lean-in from the other side, high and toward the chest"],
		[Vector3(0.0, 0.08, -0.12), true, "head low past the face toward the crown"],
		[Vector3(0.0, 0.70, 0.0), false, "kneeling upright above the face"],
		[Vector3(0.10, 0.45, 0.0), false, "45 cm up is not a lean-in"],
		[Vector3(0.0, 0.30, 0.30), false, "hovering over the chest, 30 cm toward the feet"],
		[Vector3(0.35, 0.20, 0.0), false, "35 cm to the side is beyond the box"],
		[Vector3(0.0, 0.02, 0.0), false, "2 cm above the mouth would be inside the head"],
		[Vector3(0.0, 0.20, -0.20), false, "20 cm past the crown is behind the head"],
	]:
		check(FaceCheck.inside(item[0]) == bool(item[1]), str(item[2]))
	# The mouth landmark lies on the head side of the real mannequin scene.
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var root := Node3D.new()
	root.add_child(patient)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var mouth := patient.get_node_or_null("MouthZone") as Node3D
	check(mouth != null and mouth.position.z < -0.2, "MouthZone exists toward the head (got %s)" % (mouth.position if mouth else null))
	root.get_parent().remove_child(root)
	root.free()

	var face: RefCounted = FaceCheck.new()
	var lean := Vector3(0.2, 0.2, 0.0)
	check(not _feed(face, lean, 200), "inactive detector never counts")
	face.active = true
	check(not _feed(face, lean, 140), "2.8 s at the face is not yet a check")
	check(_feed(face, lean, 12), "3.04 s completes the check")
	check(face.evidence_recent(), "evidence after the check")
	check(not face.too_long(), "3 s is not too long")
	face.reset()
	face.active = true
	_feed(face, lean, 100)
	_feed(face, Vector3(0.0, 0.7, 0.0), 50) # head lifted for 1 s
	check(_feed(face, lean, 52), "time at the face adds up across a lift of the head")
	_feed(face, lean, 360) # 10.2 s in total
	check(face.too_long(), "more than 10 s at the face gives the hint")
	check(not face.too_long(), "...only once")
	face.reset()
	face.active = true
	_feed(face, lean, 152)
	_feed(face, null, 700) # 14 s without a pose
	check(face.evidence_recent(), "evidence still valid after 14 s")
	_feed(face, null, 700)
	check(face.evidence_recent(), "evidence still valid after 28 s")
	_feed(face, null, 200)
	check(not face.evidence_recent(), "evidence expired after 32 s")

	var scenario := Scenario.new()
	scenario.submit_action("start")
	scenario.submit_action("begin_check")
	scenario.submit_action("check_responsiveness", {"source": "speech", "shoulders_seen": true})
	scenario.submit_action("call_emergency", {"source": "speech"})
	check(not scenario.submit_action("check_breathing", {"source": "speech", "face_seen": false}), "breathing report without face evidence is refused")
	check(scenario.last_error == "error.breathing_not_seen", "refusal names the face (got %s)" % scenario.last_error)
	check(scenario.get_state_name() == "call_help", "the step stays open")
	check(scenario.submit_action("check_breathing", {"source": "speech", "face_seen": true}), "breathing report with face evidence is accepted")
	check(scenario.get_state_name() == "cpr", "...and CPR begins")
	scenario.free()
	for key in ["error.breathing_not_seen", "coach.open_airway_hint", "coach.check_time"]:
		for lang in ["en", "de", "pl"]:
			var text := NaretLanguage.text(key, lang)
			check(not text.is_empty() and text != key, "text %s exists in %s" % [key, lang])
	return failures
