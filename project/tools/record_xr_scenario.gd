extends SceneTree
## Video of Drehbuch scenario 1 (docs/DREHBUCH.md, ERC adult BLS with AED) played
## in the Meta XR Simulator with the simulator's own tracked hands (Meta hand
## mesh). The hands go through NaretXRInteraction exactly as on the Quest: the
## compressions are counted by the CPR zone from two stacked hands, the AED is
## switched on with a fingertip and both electrodes are carried by pinch. Speech
## the trainee would say is shown as a caption and sent as the matching intent.
## tools/xr_hand_driver.py steers the hands over the simulator's gRPC input API
## towards the goals streamed here over UDP. Run via tools/record_xr_scenario.sh.
## Writes build/xr_scenario/frames/*.jpg and build/xr_scenario/speech.json.

const SIZE := Vector2i(1280, 720)
const FPS := 30.0
const DRIVER_PORT := 47011
const OUT := "res://build/xr_scenario"
const RATE := 112.0 # mid-range: the simulator's stroke timing jitters by a few per minute

var _scene: Node
var _viewport: SubViewport
var _camera: Camera3D
var _caption: Label
var _udp := PacketPeerUDP.new()
var _goal := {}
var _t := 0.0
var _next_frame := 0.0
var _frame := 0
var _speech: Array = []
var _times: Array[float] = []
var _recording := false
## Always the trainee's own view (first person): "eyes" kneels at Jan's side, on
## the hands, turning to whoever speaks while the hands are free; "display" leans
## over the AED's screen. _lean brings the head down to Jan's face (look, listen,
## feel; breaths), _people_until turns it to the bystanders.
var _shot := "eyes"
var _kneel := Vector3.ZERO
## Hands free (after _hands_off): only then does the view turn to whoever speaks;
## while the hands work, the eyes stay on them, as a trainee's would.
var _idle := true
var _lean := false
var _people_until := 0.0
var _look_marek_until := 0.0
## Leaning over Jan to look at something on his far side (the lateral pad).
var _peek_until := 0.0
var _peek_point := Vector3.ZERO
var _speaker: Node3D
var _look := Vector3.ZERO

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	_udp.set_dest_address("127.0.0.1", DRIVER_PORT)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.world_3d = root.world_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.near = 0.03
	_camera.environment = preload("res://tools/review_env.tres")
	_viewport.add_child(_camera)
	_camera.make_current()
	_caption = Label.new()
	_caption.position = Vector2(40, SIZE.y - 110)
	_caption.size = Vector2(SIZE.x - 80, 100)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 26)
	_caption.add_theme_color_override("font_outline_color", Color("1f3c7b"))
	_caption.add_theme_constant_override("outline_size", 10)
	_viewport.add_child(_caption)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/frames"))
	_scene.audio_manager.set_listening(false)
	# The simulator's idle hands hold their palms to the headset, which would keep
	# opening the palm menu; this take shows the scenario, not the menu.
	_scene.hand_menu.visible = false
	_scene.hand_menu.process_mode = Node.PROCESS_MODE_DISABLED
	_scene.audio_manager.utterance_started.connect(func(text: String, lang: String, _source: String, speaker: String):
		if _recording: _speech.append({"t": _t, "text": text, "language": lang, "speaker": speaker})
		_speaker = {"anna": _scene.get_node("Bystanders/Anna"), "bystander": _scene.get_node("Bystanders/Anna"),
			"marek": _scene.get_node("Bystanders/Marek")}.get(speaker))
	_scene.aed.spoke.connect(func(key: String, lang: String):
		if _recording: _speech.append({"t": _t, "text": _scene.director.line_text(key, lang), "language": lang, "speaker": "aed"}))
	_scene.audio_manager.playback_changed.connect(func(active: bool): if not active: _speaker = null)
	_play()

## --- choreography ------------------------------------------------------------

func _say(text: String) -> void:
	_caption.text = text
	print("XR_ERC ", text.replace("\n", " · "))

func _pause(seconds: float) -> void:
	await create_timer(seconds).timeout

func _reach(hand: String, gesture: String, effector: String, point: Vector3, tolerance := 0.012, palm_down := false) -> void:
	## Streams a goal to the driver and waits until the tracked hand is there.
	_goal = {"hand": hand, "gesture": gesture, "effector": effector, "goal": point, "palm_down": palm_down}
	if hand != "head":
		_idle = false
	var close := 0
	var waited := 0.0
	while close < 6:
		await process_frame
		waited += 1.0 / 60.0
		var at: Variant = _effector(hand, effector)
		close = close + 1 if at != null and (at as Vector3).distance_to(point) < tolerance else 0
		if waited > 20.0:
			push_warning("XR_ERC %s hand did not reach %s" % [hand, point])
			break

func _hands_off() -> void:
	## Both hands up and back, clear of the patient (contact voids an AED analysis).
	var sternum := _sternum()
	# Beside Jan on the trainee's side, outside the app's contact envelope.
	await _reach("left", "default", "grip", sternum + Vector3(-0.45, 0.2, 0.1), 0.05)
	await _reach("right", "default", "grip", sternum + Vector3(-0.55, 0.2, 0.3), 0.05)
	_idle = true

func _play() -> void:
	var s: NaretScenario = _scene.scenario
	while _effector("right", "tip") == null or _effector("left", "tip") == null:
		await process_frame
	await _pause(1.0)
	# The simulated headset kneels at Jan's right side, so the bystanders, who look
	# at the headset, make eye contact with the trainee's view.
	_kneel = _sternum() + Vector3(-0.6, 0.68, 0.15)
	await _reach("head", "default", "head", _kneel, 0.04)
	_look = _sternum()
	_recording = true
	_look_people(6.0)
	var sternum := _sternum()
	var shoulder := sternum + Vector3(-0.12, 0.05, -0.12)   # Jan's right shoulder
	var other_shoulder := sternum + Vector3(0.12, 0.05, -0.12)
	_say("Szenario 1 · Jan bricht zusammen · Anna ruft um Hilfe")
	_scene._on_action("start")
	await _pause(6.0)
	_say("1.2  Umgebung sicher · Trainee: »Hallo! Hören Sie mich?« · an den Schultern rütteln")
	_scene._on_action("begin_check", {"source": "test"})
	# Both hands on both shoulders, then shake them together.
	await _reach("left", "default", "palm", other_shoulder + Vector3(0, 0.06, 0), 0.04, true)
	await _reach("right", "default", "palm", shoulder + Vector3(0, 0.06, 0), 0.04, true)
	for i in 3:
		await _reach("both", "default", "palm_right", shoulder + Vector3(0, 0.03, 0), 0.03)
		if i == 0:
			_scene._on_action("check_responsiveness", {"source": "test"})
		await _reach("both", "default", "palm_right", shoulder + Vector3(0, 0.08, 0), 0.03)
	await _pause(1.5)
	_say("1.3  Keine Reaktion · Trainee: »Hilfe! Ich brauche Hilfe!«")
	await _pause(3.5)
	_say("1.4  ERC 2025: bei fehlender Reaktion sofort 112 · Trainee zu Marek: »Rufen Sie 112 an, Lautsprecher an!«")
	await _pause(1.5)
	_scene._on_action("call_emergency", {"source": "speech"})
	await _pause(1.5)
	_say("1.5  Während der Notruf läuft: Kopf überstrecken, Kinn anheben · Atmung prüfen (höchstens 10 s)")
	# Palms turned down: flat on the forehead, fingertips under the chin.
	await _reach("left", "default", "palm", _forehead() + Vector3(0, 0.05, 0), 0.03, true)
	await _reach("right", "default", "tip", _head() + Vector3(0, 0.05, 0.12), 0.03, true)
	_lean = true
	await _pause(2.5)
	_say("1.5  Nur ein Schnappen: Schnappatmung ist keine normale Atmung → Kreislaufstillstand")
	await _pause(2.5)
	_lean = false
	_scene._on_action("check_breathing", {"source": "test"})
	_say("1.6/1.7  »Nein, er atmet nicht normal!« – zu Marek: »Holen Sie den AED!« · sofort Herzdruckmassage")
	_scene._on_action("request_aed", {"source": "speech"})
	await _place_hands()

	var cycle := 1
	while not s.aed_available:
		_say("1.7  Herzdruckmassage 30:2 · 100–120/min · 5–6 cm (Zyklus %d) · Marek holt den AED" % cycle)
		await _cpr_cycle(true)
		cycle += 1
		if not s.aed_available:
			await _place_hands()
	# ERC 2025, two rescuers: compressions go on while the pads are applied.
	_say("1.12  Marek ist mit dem AED zurück · weiterdrücken, bis er übernimmt")
	await _place_hands()
	_goal = {"mode": "pump", "hand": "both", "rate": RATE, "depth": 0.055, "effector": "heel_left", "top": _sternum().y + 0.003}
	var waited := 0.0
	while not _scene.director.marek_compressing and waited < 15.0:
		await process_frame
		waited += 1.0 / 60.0
	# Hands off the chest at once: Marek has it now.
	_goal = {"hand": "both", "gesture": "default", "effector": "heel_left", "goal": _sternum() + Vector3(-0.1, 0.2, 0.05)}
	_say("1.12  Marek übernimmt die Herzdruckmassage · die übende Person bedient den AED")
	_idle = true
	_speaker = null
	_look_marek_until = _t + 3.0
	await _pause(2.5) # Marek's line first, then the device
	await _use_aed()
	while s.state != NaretScenario.State.RECOVERY:
		await _analysis_and_shock()
	_say("1.17  Kein Schock empfohlen · der Kreislauf ist zurück · Puls auf dem AED-Display")
	_shot = "display"
	await _pause(7.0)
	_shot = "eyes"
	_look_people(8.0)
	_say("1.17  Atmung überwachen · stabile Seitenlage · auf den Rettungsdienst warten")
	await _pause(2.0)
	_say("1.18  Übergabe an den Rettungsdienst: Kollaps, CPR seit Minute 1, AED, %d Schock%s" % [s.shock_count, "" if s.shock_count == 1 else "s"])
	var ems_wait := 0.0
	while not _speech.any(func(e): return str(e.text).begins_with("Der Rettungsdienst")) and ems_wait < 25.0:
		await _pause(0.5)
		ems_wait += 0.5
	await _pause(5.0)
	_finish()

func _place_hands() -> void:
	## Palms down, the left heel on the lower half of the sternum, the right on top.
	var sternum := _sternum()
	await _reach("both", "default", "heel_left", sternum + Vector3(0, 0.12, 0), 0.04, true)
	await _reach("left", "default", "heel_left", sternum + Vector3(0, 0.04, 0), 0.015, true)
	await _reach("left", "default", "heel_left", sternum + Vector3(0, 0.003, 0), 0.012, true)
	await _reach("right", "default", "heel_right", sternum + Vector3(0, 0.03, 0), 0.015, true)

func _cpr_cycle(until_aed := false) -> void:
	## 30 compressions counted by the app from the hands, then two breaths; with
	## until_aed it hands over as soon as the AED is there.
	var s: NaretScenario = _scene.scenario
	var target := s.compressions + 30 - s.cycle_compressions
	var top := _sternum().y + 0.003
	_goal = {"mode": "pump", "hand": "both", "rate": RATE, "depth": 0.055, "effector": "heel_left", "top": top}
	var waited := 0.0
	while s.compressions < target and s.state == NaretScenario.State.CPR and waited < 40.0 and not (until_aed and s.aed_available):
		await process_frame
		waited += 1.0 / 60.0
	_goal = {"hand": "both", "gesture": "default", "effector": "heel_left", "goal": _sternum() + Vector3(0, 0.12, 0)}
	if s.state != NaretScenario.State.CPR or s.cycle_compressions < 30 or (until_aed and s.aed_available):
		return
	_say(("1.15" if s.shock_count > 0 else "1.7") + "  2 Beatmungen · Kopf überstrecken, Kinn anheben, Mund-zu-Mund")
	await _reach("left", "default", "palm", _forehead() + Vector3(0, 0.05, 0), 0.04, true)
	await _reach("right", "default", "tip", _head() + Vector3(0, 0.05, 0.12), 0.05, true)
	_lean = true
	for i in 2:
		_scene._on_action("ventilation", {"source": "test"})
		await _pause(1.2)
	_lean = false

func _use_aed() -> void:
	var aed: NaretAED = _scene.aed
	var power: Vector3 = aed._power.global_position
	await _hands_off()
	_say("1.12  AED ist da · einschalten mit dem Finger")
	await _reach("right", "poke", "tip", power + Vector3(0, 0.08, 0), 0.02)
	await _reach("right", "poke", "tip", power + Vector3(0, 0.004, 0))
	await _pause(0.4)
	await _reach("right", "poke", "tip", power + Vector3(0, 0.08, 0), 0.02)
	_say("1.12  Elektrode 1 · rechts unter das Schlüsselbein")
	await _carry(aed._pads["PadRight"], aed._pad_target("PadRight").origin)
	_say("1.12  Elektrode 2 · links seitlich am Brustkorb")
	# ponytail: the right hand places both; the left palm faces the head here and
	# would open the hand menu, which takes that hand out of the interaction.
	await _carry(aed._pads["PadLeft"], aed._pad_target("PadLeft").origin)
	_peek_point = aed._pad_target("PadLeft").origin
	_peek_until = _t + 2.5
	await _hands_off()

func _analysis_and_shock() -> void:
	var s: NaretScenario = _scene.scenario
	while s.state != NaretScenario.State.AED:
		await process_frame
	await _hands_off()
	_say(("1.13  AED analysiert" if s.shock_count == 0 else "Folgeanalyse nach 2 min CPR") + " · Trainee: »Alle weg vom Patienten!«")
	await _pause(1.2)
	_scene._on_action("clear_patient", {"source": "speech"})
	await _pause(1.8)
	if _scene.director._intrude_left > 0.0:
		_look_people(4.0)
		_say("1.14  Anna will Jan berühren · Trainee: »Abstand! Niemand berührt ihn!«")
		_scene.director.on_intent("keep_clear")
	while s.state == NaretScenario.State.AED and s.aed_stage not in [NaretScenario.AEDStage.SHOCK_ADVISED, NaretScenario.AEDStage.ATTACHED]:
		await process_frame
	if s.state != NaretScenario.State.AED:
		return
	if s.aed_stage == NaretScenario.AEDStage.ATTACHED:
		return # contact voided the analysis; the next round clears again
	_say("Schock empfohlen · Trainee: »Alle weg!« · der AED schockt selbst nach dem Countdown")
	await _pause(1.2)
	_scene._on_action("clear_patient", {"source": "speech"})
	while s.state == NaretScenario.State.AED:
		await process_frame
	_say("1.15  Schock %d abgegeben · sofort weiterdrücken" % s.shock_count)
	await _place_hands()
	await _cpr_cycle()
	# The rest of the two minutes is skipped; the device then stops CPR by itself.
	_say("1.16  … 2 Minuten CPR später · der AED unterbricht für die nächste Analyse")
	await _hands_off()
	s.advance_simulation(121.0)
	while s.state == NaretScenario.State.CPR:
		await process_frame

func _look_people(seconds: float) -> void:
	_people_until = _t + seconds

func _carry(pad: Node3D, target: Vector3) -> void:
	## Pinch the electrode where it lies, carry it, let go on the chest.
	var from := pad.global_position
	await _reach("right", "default", "grip", from + Vector3(0, 0.08, 0), 0.02)
	await _reach("right", "default", "grip", from, 0.02)
	await _reach("right", "pinch", "grip", from, 0.03)
	await _pause(0.4)
	await _reach("right", "pinch", "grip", from.lerp(target, 0.5) + Vector3(0, 0.15, 0), 0.03)
	await _reach("right", "pinch", "grip", target + Vector3(0, 0.01, 0), 0.02)
	await _pause(0.3)
	_goal["gesture"] = "default"
	await _pause(0.8)
	await _reach("right", "default", "grip", target + Vector3(0, 0.12, 0), 0.03)

func _finish() -> void:
	_recording = false
	_goal = {"hand": "", "done": true}
	_send()
	var file := FileAccess.open(OUT + "/speech.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": _frame, "times": _times, "speech": _speech}, "  "))
	file.close()
	print("XR_ERC done frames=", _frame)
	quit()

## --- per frame -----------------------------------------------------------------

func _sternum() -> Vector3:
	return _scene.mannequin.sternum.global_position

func _forehead() -> Vector3:
	return _scene.mannequin.forehead()

func _head() -> Vector3:
	var head: Node3D = _scene.mannequin.get_node_or_null("Pupils")
	return head.global_position if head else _sternum() + Vector3(0, 0, -0.45)

func _joint(hand: String, joint: int) -> Variant:
	var tracker := XRServer.get_tracker("/user/hand_tracker/" + hand) as XRHandTracker
	if tracker == null or not tracker.has_tracking_data:
		return null
	var origin: Node3D = _scene.get_node("XROrigin3D")
	return origin.global_transform * tracker.get_hand_joint_transform(joint)

func _effector(hand: String, effector: String) -> Variant:
	## "tip", "grip" (pinch point), "heel_<side>" (as the CPR zone estimates it),
	## "head" (the headset); hand "both" reports the effector's own side.
	if effector == "head":
		return (_scene.get_node("XROrigin3D/XRCamera3D") as Node3D).global_position
	var side := hand
	if effector.contains("_"):
		side = effector.get_slice("_", 1)
		effector = effector.get_slice("_", 0)
	if side == "both":
		side = "right"
	var tip: Variant = _joint(side, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	if tip == null:
		return null
	match effector:
		"tip":
			return (tip as Transform3D).origin
		"palm":
			return (_joint(side, XRHandTracker.HAND_JOINT_PALM) as Transform3D).origin
		"heel":
			var palm: Transform3D = _joint(side, XRHandTracker.HAND_JOINT_PALM)
			var wrist: Transform3D = _joint(side, XRHandTracker.HAND_JOINT_WRIST)
			return wrist.origin.lerp(palm.origin, 0.3) + palm.basis.z.normalized() * 0.008
	var thumb: Transform3D = _joint(side, XRHandTracker.HAND_JOINT_THUMB_TIP)
	return ((tip as Transform3D).origin + thumb.origin) * 0.5

func _palm_y(hand: String) -> float:
	var worst := -1.0
	for side in (["left", "right"] if hand == "both" else [hand]):
		var palm: Variant = _joint(side, XRHandTracker.HAND_JOINT_PALM)
		if palm != null:
			worst = maxf(worst, (palm as Transform3D).basis.z.normalized().y)
	return worst

func _send() -> void:
	var packet := _goal.duplicate()
	if packet.has("effector") and packet.get("hand", "") != "":
		var at: Variant = _effector(packet.hand, packet.effector)
		packet.at = [at.x, at.y, at.z] if at != null else null
		packet.palm_y = _palm_y(packet.hand)
	if packet.has("goal"):
		var goal: Vector3 = packet.goal
		packet.goal = [goal.x, goal.y, goal.z]
	_udp.put_packet(JSON.stringify(packet).to_utf8_buffer())

func _process(delta: float) -> bool:
	if _scene == null:
		return false
	_t += delta
	_send()
	_camera.global_transform = _camera.global_transform.interpolate_with(_shot_transform(), minf(1.0, delta * 2.0))
	if _recording and _t >= _next_frame:
		_next_frame = maxf(_next_frame + 1.0 / FPS, _t - 0.5)
		_save_frame.call_deferred(_frame)
		_times.append(_t)
		_frame += 1
	return false

func _shot_transform() -> Transform3D:
	var sternum := _sternum()
	var eye := _kneel if _kneel != Vector3.ZERO else sternum + Vector3(-0.6, 0.68, 0.15)
	match _shot:
		"display":
			# Leaning over the device from the kneeling spot.
			var screen: MeshInstance3D = _scene.aed._screen
			var centre := screen.global_transform * screen.get_aabb().get_center()
			var close_eye := eye.lerp(centre + Vector3(0, 0.3, 0), 0.7)
			return Transform3D(Basis.looking_at(centre - close_eye, Vector3.UP), close_eye)
	# Eyes: on the hands' current goal, up at whoever speaks.
	var focus := sternum + Vector3(-0.05, -0.05, 0.0)
	if _goal.has("goal") and _goal.get("hand", "") != "head":
		focus = focus.lerp(_goal.goal, 0.6)
	if _t < _peek_until:
		eye = eye.lerp(_peek_point + Vector3(0.02, 0.38, 0.05), 0.65)
		focus = _peek_point
	elif _lean:
		# Cheek over Jan's mouth, eyes along the chest.
		eye = eye.lerp(_head() + Vector3(-0.22, 0.2, 0.08), 0.75)
		focus = sternum
	elif _t < _look_marek_until:
		focus = (_scene.get_node("Bystanders/Marek") as Node3D).global_position + Vector3(0, 0.6, 0)
	elif _t < _people_until:
		var people := Vector3.ZERO
		var count := 0.0
		for person: Node3D in [_scene.get_node("Bystanders/Anna"), _scene.get_node("Bystanders/Marek")]:
			if person.visible:
				people += person.global_position + Vector3(0, 1.3, 0)
				count += 1.0
		if count > 0.0:
			focus = people / count
	elif _speaker and _idle:
		focus = _speaker.global_position + Vector3(0, 1.45, 0)
	_look = _look.lerp(focus, 0.06)
	return Transform3D(Basis.looking_at(_look - eye, Vector3.UP), eye)

func _save_frame(index: int) -> void:
	var image := _viewport.get_texture().get_image()
	image.save_jpg(ProjectSettings.globalize_path(OUT + "/frames/%05d.jpg" % index), 0.9)
