extends "res://tests/suite.gd"
## Headset, 20 Nov 2026 (user): "the defibrillator guy walks and only then says 'I will
## bring the defibrillator'". He says it first: while his answer still waits for another
## voice to end he stays, and his answer cuts into a long line of somebody else.
const Helper = preload("res://scripts/scenario/aed_helper_director.gd")

class Audio extends NaretAudioManager:
	func _ready() -> void: pass

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var scenario := NaretScenario.new()
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var anna: NaretBystander = load("res://scenes/bystander.tscn").instantiate()
	var marek: NaretBystander = load("res://scenes/bystander_male.tscn").instantiate()
	var model: Node3D = load("res://assets/models/aed.glb").instantiate()
	var device := NaretAED.new()
	var director := Helper.new()
	var world := Node3D.new()
	tree.root.add_child(world)
	world.add_child(model)
	for node in [scenario, patient, anna, marek, device, director]: tree.root.add_child(node)
	device.configure(model, patient)
	director.configure(scenario, anna, marek, patient, device)
	var waiting := [true]
	director.answer_waiting = func(): return waiting[0]
	scenario.start()
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "request_aed"]:
		check(scenario.submit_action(action), "step " + action)
	director.advance(1.9)
	director.advance(1.9)
	check(director.phase == "announce", "his sentence is waiting or being said: he stays, phase " + director.phase)
	waiting[0] = false
	director.advance(0.2)
	check(director.phase == "announce", "the last word has just been said")
	director.advance(0.2)
	check(director.phase == "walk_out", "said: he goes right away, without a fixed wait, phase " + director.phase)
	const Spoken = preload("res://scripts/scenario/spoken_observation.gd")
	check(Spoken.call_comes_first("Anna, please call 112, and Marek, get the AED"), "the call is asked first")
	check(not Spoken.call_comes_first("Marek, bring the defibrillator, and Anna, call 112"), "the device is asked first")
	check(Spoken.call_comes_first("Ruf bitte die 112 an und du holst den Defibrillator"), "in German too")
	# A voice that never comes does not keep him for ever.
	scenario.reset()
	scenario.start()
	waiting[0] = true
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "request_aed"]: scenario.submit_action(action)
	for i in 23: director.advance(1.0)
	check(director.phase == "announce", "a long line before his is waited for")
	for i in 4: director.advance(1.0)
	check(director.phase != "announce", "after %.0f s he goes anyway" % Helper.ANNOUNCE_MAX_S)

	# The AED is there, he is back at his place; the trainee switches it on for the pads:
	# he comes to the side of the patient across from the trainee and presses.
	for side_sign: float in [1.0, -1.0]:
		scenario.reset()
		scenario.start()
		for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "request_aed"]: scenario.submit_action(action)
		scenario.submit_action("compression", {"source": "test", "rate_bpm": 110.0})
		check(scenario.state == NaretScenario.State.CPR, "CPR runs")
		director._end_errand(false)
		director.delivered = true
		scenario.aed_available = true
		var body: Transform3D = patient.call("get_body_transform") if patient.has_method("get_body_transform") else patient.global_transform
		var lateral := body.basis.x
		lateral.y = 0.0
		lateral = lateral.normalized()
		var chest: Vector3 = director._sternum_point()
		director.trainee = func(): return chest + lateral * 0.5 * side_sign + Vector3(0, 0.6, 0)
		device.powered = false
		director.advance(6.0)
		check(director.phase == "", "AED still off: he stays at his place")
		device.powered = true
		director.advance(0.1)
		check(director.phase == "to_chest", "AED switched on for the pads: he comes to the chest, phase " + director.phase)
		check((director._goal - chest).dot(lateral) * side_sign < -0.2, "to the side across from the trainee (trainee %s)" % ("on one side" if side_sign > 0.0 else "on the other"))
		# He walks to just outside the ring round the patient and is then set on his
		# kneeling spot: hands on the green zone, wherever the walk ended.
		check((director._goal - chest).length() > 0.6, "he walks to a point outside the patient's ring (%.2f m)" % (director._goal - chest).length())
		for i in 12: director.advance(1.0)
		var zone: Vector3 = director._chest_point()
		var flat := Vector2(marek.global_position.x - zone.x, marek.global_position.z - zone.z)
		check(director.phase in ["kneel_down", "helper_cpr"] and absf(flat.length() - Helper.HELPER_REACH) < 0.02, "he kneels a hand's reach (%.2f m) from the green zone, phase %s, at %.2f m" % [Helper.HELPER_REACH, director.phase, flat.length()])
		var facing := Vector2(marek.global_basis.z.x, marek.global_basis.z.z).normalized()
		check(facing.dot(-flat.normalized()) > 0.98, "squared to the zone, so his hands land on it")
		var trainee_at: Vector3 = director.trainee.call()
		check(Vector2(marek.global_position.x - trainee_at.x, marek.global_position.z - trainee_at.z).length() > 0.6, "not where the trainee is")
		device.powered = false

	# The answer cuts into a long line; that line is said again afterwards.
	var audio := Audio.new()
	tree.root.add_child(audio)
	for i in 2:
		var player := AudioStreamPlayer.new()
		audio.add_child(player)
		audio._players.append(player)
	var long := AudioStreamWAV.new()
	long.format = AudioStreamWAV.FORMAT_16_BITS
	long.mix_rate = 8000
	var samples := PackedByteArray()
	samples.resize(8000 * 2 * 8)
	long.data = samples
	audio._coach_clips["en:dispatcher:Where exactly are you?"] = long
	audio._coach_clips["en:marek:I will get the defibrillator."] = long
	var started: Array = []
	audio.utterance_started.connect(func(text, _l, _s, _sp): started.append(text))
	audio._api = NaretUniAPIClient.new()
	audio.add_child(audio._api)
	audio.speak("Where exactly are you?", "en", "", "dispatcher")
	check(started == ["Where exactly are you?"] and not audio.urgent_waiting(), "the dispatcher speaks, got %s" % [started])
	audio._coach_clips["en:dispatcher:Start chest compressions."] = long
	audio.speak("Start chest compressions.", "en", "", "dispatcher")
	audio.speak_urgent("I will get the defibrillator.", "en", "marek_go_aed", "marek")
	check(started == ["Where exactly are you?"] and audio.current_text == "Where exactly are you?", "nobody talks over the dispatcher or cuts her line, got %s" % [started])
	check(audio.urgent_waiting() and audio._ready_audio[0].text == "I will get the defibrillator.", "Marek's answer is the next line, before the others that wait")
	for player: AudioStreamPlayer in audio._players: player.stop()
	audio._on_playback_finished()
	check(started.size() == 2 and started[1] == "I will get the defibrillator." and audio.answer_playing() and not audio.urgent_waiting(), "the dispatcher has finished: now he says it, got %s" % [started])
	# (A player started and stopped within one frame may still report "playing" here,
	# so the end of his line is given as the app handles it: the next line is played.)
	audio._play_next()
	check(not audio.answer_playing() and audio.current_text == "Start chest compressions.", "then the next line follows, got %s, waiting %s %s" % [audio.current_text, audio._ready_audio.size(), audio._pending.size()])
	for node in [audio, world, scenario, patient, anna, marek, device, director]: node.free()
	return failures
