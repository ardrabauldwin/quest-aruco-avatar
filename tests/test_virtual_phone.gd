extends "res://tests/suite.gd"
## Step 4, Situation A (18 Nov 2026): the phone in the left hand. 112, then Speaker; then it
## lies screen up on the ground, keys gone; the call instruction says how.

func run() -> Array[String]:
	failures.clear()
	var phone := NaretVirtualPhone.new()
	phone.configure(null, null)
	var log: Array[String] = []
	phone.dialed.connect(func(): log.append("dialed"))
	phone.speaker_on.connect(func(): log.append("speaker"))
	check(phone.state == "hidden" and not phone.visible, "hidden until the call step")
	phone.offer("de")
	check(phone.in_hand() and phone.visible and phone._dial_key.visible and not phone._speaker_key.visible, "in the hand: only the green 112")
	phone._speaker()
	check(log.is_empty(), "Speaker does nothing before 112")
	phone._dial()
	check(log == ["dialed"] and phone.state == "calling" and phone._speaker_key.visible and not phone._dial_key.visible, "112 rings and shows Speaker")
	check(phone._speaker_key.label.text == "Lautsprecher", "Speaker key in the trainee's language")
	phone._speaker()
	check(log == ["dialed", "speaker"], "Speaker starts the call on speaker")
	check(phone.state == "placing" and phone.in_hand() and not phone._speaker_key.visible, "on speaker it stays in the hand until put down")
	phone.put_down(Vector3(1, 0, 2), Vector3(0, 0, -1))
	check(phone.state == "speaker" and not phone.in_hand() and not phone._speaker_key.visible, "on the ground, keys gone")
	check(phone.transform.basis.z.dot(Vector3.UP) > 0.99, "screen up")
	check(phone.transform.basis.y.dot(Vector3(0, 0, -1)) > 0.99, "top toward the head")
	phone.hide_phone()
	check(not phone.visible and phone.state == "hidden", "hidden on reset")
	phone.free()
	var steps: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/coach_steps.json"))
	for language in ["de", "pl", "en"]:
		check("112" in str(steps[language].call_alone) and not NaretLanguage.text("coach.phone_tap_112", language).is_empty() and not NaretLanguage.text("coach.phone_speaker", language).is_empty(), "phone lines exist: " + language)
	return failures
