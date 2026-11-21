extends "res://tests/suite.gd"
## 20 Nov 2026 (user: "the welcome should start only when we see the instructor"): in the
## headset the greeting waits until the instructor stands in front of the trainee and has
## been in the line of sight for a moment. It used to start with the app.

class Audio extends NaretAudioManager:
	var lines: Array = []
	func _ready() -> void: pass
	func is_speaking() -> bool: return false
	func speak(text: String, _lang: String = "pl", _key: String = "calm", speaker: String = "bystander", _keep: bool = false) -> void:
		lines.append({"text": text, "speaker": speaker})

class Host extends "res://scripts/main.gd":
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_welcome_choices.cfg"))
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.language_file = "user://test_welcome_choices.cfg"
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = false
	host.anchor.floor_locked = true
	host.anchor.floor_y = 0.0
	host.scenario = NaretScenario.new()
	host.add_child(host.scenario)
	var audio := Audio.new()
	host.audio_manager = audio
	host.add_child(audio)
	host._language = "en"
	var greeting: String = host.WELCOME.en
	var instructor: Node3D = host.get_node("Instructor")
	instructor.visible = false

	# The app starts; the headset has no pose yet (the camera is on the floor).
	host.xr_camera.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	host._welcome()
	await tree.process_frame
	host._update_welcome_instructor()
	check(audio.lines.is_empty() and not instructor.visible, "no greeting at app start, before the instructor is there, got %s" % [audio.lines])

	# The headset is on: the instructor is put in front. Seen for an instant is not enough.
	host.xr_camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	host._update_welcome_instructor()
	check(instructor.visible and host._welcome_instructor_placed, "the instructor is placed in front of the trainee")
	check(absf(instructor.global_position.z + host.WELCOME_INSTRUCTOR_M) < 0.05 and absf(instructor.global_position.x) < 0.05, "1.6 m straight ahead, at %s" % instructor.global_position)
	host._update_welcome_instructor()
	check(audio.lines.is_empty(), "the greeting does not start in the frame he appears")

	# The trainee looks away (to the side): the wait starts over.
	host.xr_camera.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), Vector3(0, 1.6, 0))
	await tree.create_timer(0.5).timeout
	host._update_welcome_instructor()
	check(audio.lines.is_empty(), "no greeting while the instructor is out of sight")

	# He is in view and stays there: now the greeting, once.
	host.xr_camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	host._update_welcome_instructor()
	check(audio.lines.is_empty(), "back in view: still the short wait")
	await tree.create_timer(0.5).timeout
	host._update_welcome_instructor()
	check(audio.lines.size() == 1 and audio.lines[0].text == greeting and audio.lines[0].speaker == "instructor", "seen for a moment: the instructor greets, got %s" % [audio.lines])
	check(host.speech_bubble != null and host.speech_bubble.visible, "the greeting's subtitles show")
	check(host.speech_bubble.shown_text() == greeting and host.speech_bubble._heading.text == host.WELCOME_TITLE.en, "the card carries the heading and the greeting")
	# One place per sentence (20 Nov 2026): what the card shows is not repeated on the hand.
	check(host._on_card(greeting), "the greeting is on the card, so it is kept off the hand notice")
	check(not host._on_card("Floor calibrated: +0.4 cm"), "a message the card does not show still goes to the hand")
	await tree.create_timer(0.5).timeout
	host._update_welcome_instructor()
	check(audio.lines.size() == 1, "the greeting is said once")

	# The patient is placed: the palm line follows as before.
	host.anchor.locked = true
	host._update_welcome_instructor()
	check(audio.lines.size() == 2 and audio.lines[1].text == host.WELCOME_PALM.en, "after the placement he asks for the open palm, got %s" % [audio.lines])

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_welcome_choices.cfg"))
	host.xr.free()
	host.free()
	return failures
