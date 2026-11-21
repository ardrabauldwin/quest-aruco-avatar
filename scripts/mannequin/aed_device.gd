class_name NaretAED
extends Node
## Drives the AED prop from the scenario: it arrives when someone was sent for it,
## powers up when it is applied (on/off ring and status LED), moves both
## electrodes onto the chest with leads back to the connector, shows its voice
## prompts on the small status display and flashes the ring round the
## automatic-shock indicator while a shock is due. Once a shock brought the
## patient back (scenario outcome "rosc"), the display shows the pulse.
## In XR it is worked with the hands (touch()): a fingertip presses the power
## button, a pinch takes an electrode off the device and lets go of it on the
## chest. Like the real fully automatic AED it then analyses and shocks by itself;
## it asks for those steps through `requested`, the scenario still rules on them.

signal requested(action: String)
## A voice prompt started on the device's own speaker (key in data/bystander_lines.json).
signal spoke(key: String, language: String)
signal pad_missed(name: String)
## The trainee took the device out of the helper's hand / let go of it.
signal taken
signal placed

## Electrode placement in the authored BodyFrame (supine, head -Z, left +X):
## right pad below the right clavicle, left pad on the left mid-axillary line.
## ponytail: fixed chest poses for the one patient model; raycast if models vary.
const PAD_POSES := {
	"PadRight": [Vector3(-0.085, 0.206, -0.175), Vector3(0, 12, 0)],
	# Mid-axillary line below the armpit, on the flank rather than the chest front.
	# (The left arm is moved out of the way when the device is switched on.)
	"PadLeft": [Vector3(0.16, 0.125, -0.09), Vector3(0, -8, -48)],
}
const LEAD := Vector3(0, 0.003, -0.045)
const PAD_SIZE := Vector2(0.12, 0.09)
const PAD_GRID := Vector2i(12, 9)
## Hand-tracking reach, widened 13 Nov 2026 after headset use: a tracked fingertip is
## 1-2 cm off and the button is 2.2 cm wide, so a 2 cm sphere round its centre was
## missed more often than hit.
const BUTTON_RANGE_M := 0.06
const BUTTON_RELEASE_M := 0.09
## The power button is 2.2 cm in aed.glb, too small to find and to hit with a tracked
## fingertip (headset 13 Nov 2026: "cannot switch on"). Drawn 5 cm across and standing
## 1 cm proud of the face. The shock button below it is the same size and height (same
## day: "make the shock button similar to the on button"), orange with a white flash on
## it; the small screen moves 9 mm down the face to make room for the two.
const POWER_BUTTON_SCALE := 1.85
## Distance from the pinch point to the pad's *surface* (its 12 x 9 cm card), not to its
## centre: with the old 6 cm sphere round the centre a pinch at a corner (7.5 cm out)
## never took the pad.
const PAD_GRAB_M := 0.08
## A pad let go this close to its place sticks there (pads are interchangeable). The
## place is on the drawn avatar; the real manikin's chest can be a few centimetres off.
const PAD_SNAP_M := 0.15 # 12 cm until 13 Nov 2026: releases at 12.2 and 11.6 cm, one missed.
## Hand-over: the device travels from the helper's hand to its place in this time.
const SET_DOWN_S := 0.7
## Taking the whole device: a pinch or a closed hand this close to its housing.
const TAKE_REACH_M := 0.10
## Hand tracking drops a closed hand for a frame or two; the device is not let go for that.
const CARRY_GRACE_MS := 250
## Housing, from the model's origin on its underside (aed.glb: 25.6 x 7.9 x 25 cm).
const BOX_CENTRE := Vector3(0, 0.04, 0)
const BOX_HALF := Vector3(0.128, 0.04, 0.125)
## Held out by the helper: this far above his hand bone, lying flat.
const OFFER_LIFT_M := 0.05
const ANALYSE_DELAY_S := 5.0
const SHOCK_COUNTDOWN_S := 3.0
## After its announcement the device waits this long before it goes on by itself.
const CLEAR_DELAY_S := 2.0
## The shock button waits for the trainee; the device repeats its request this often.
const SHOCK_REMIND_S := 8.0
## Drawn larger than in aed.glb (3.4 cm) and standing proud, like the power key; a
## fingertip within SHOCK_RANGE_M presses it.
const SHOCK_BUTTON_SCALE := 1.47
const SHOCK_BUTTON_DOWN_M := 0.005
const SCREEN_DOWN_M := 0.009
const SHOCK_BUTTON_UP_M := 0.005
const SHOCK_RANGE_M := 0.08
const REASSESS_DELAY_S := 3.0
## "Shock delivered" comes a moment after the jolt, not on top of it.
const SHOCKED_VOICE_DELAY_S := 1.8
const PAD_TEXTURE := preload("res://assets/models/aed_pad.png")
const PROMPTS := {
	"en": ["DO NOT TOUCH PATIENT", "ANALYSIS READY", "SHOCK ADVISED", "STAND CLEAR · AUTOMATIC SHOCK", "NO SHOCK · CPR", "RESUME CPR", "SHOCK DELIVERED", "NO SHOCK ADVISED · PULSE"],
	"de": ["PATIENT NICHT BERÜHREN", "ANALYSE BEREIT", "SCHOCK EMPFOHLEN", "ZURÜCKTRETEN · SCHOCK FOLGT", "KEIN SCHOCK · CPR", "CPR FORTSETZEN", "SCHOCK ABGEGEBEN", "KEIN SCHOCK EMPFOHLEN · PULS"],
	"pl": ["NIE DOTYKAĆ PACJENTA", "GOTOWY DO ANALIZY", "ZALECANE WYŁADOWANIE", "ODSUŃ SIĘ · WYŁADOWANIE", "BEZ WYŁADOWANIA · RKO", "KONTYNUUJ RKO", "WYŁADOWANIE PODANE", "WYŁADOWANIE NIEZALECANE · TĘTNO"],
}

var _pad_guides: Node3D
var _floor_radius := NAN
var external_speech_busy: Callable
var manual_pad_placement_required := false
## Default-stage preview is visible before delivery; it does not bypass scenario gates.
var preview_visible := false
var _interaction_ready := false
var model: Node3D
var _mannequin: NaretMannequin
var _port: Node3D
var _led: MeshInstance3D
var _power: MeshInstance3D
var _led_material: StandardMaterial3D
var _power_material: StandardMaterial3D
var _pads := {}
var _pad_rest := {}
var _cables: Array[MeshInstance3D] = []
var _shock_button: MeshInstance3D
var ekg: NaretEKG
var _voice: AudioStreamPlayer3D
var _last_voice := ""
var _queued_voice := ""
var _screen: MeshInstance3D
var _screen_material: StandardMaterial3D
var _screen_prompt: Label
var _screen_pulse: Label
var _screen_trace: NaretEKGRenderer
var _button_material: StandardMaterial3D
var _shown := false
var _held := false
var _settle: Tween
## The helper holds it out for the trainee to take (aed_helper_director "offer").
var offered := false
var _carrier: Node3D
var _carrier_hand: Node3D
var _remind_press := false
## Per hand, whether its fingertip is on the shock button (one press per touch).
var _shock_down: Dictionary = {}
## Per hand, when its pinch on a pad was last seen.
var _pinch_seen_ms: Dictionary = {}
## The trainee's hand that carries the device, "" if none.
var _carry_pointer := ""
var _carry_offset := Vector3.ZERO
var _carry_seen_ms := 0
## () -> float: height of the surface the device rests on (main: beside the patient).
var rest_height: Callable
## Let go anywhere, it goes to its place (main: the stool), never onto the floor.
var rest_at_home := false
var _home_parent: Node
var _home_transform := Transform3D.IDENTITY
## Carried by the strap: top edge up at the hand, face turned sideways.
const CARRY := Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(0, 0.19, 0))
var _attached := false
var _blink := false
var _clock := 0.0
var _shocked_until := 0.0
var powered := false
var _placed := {}        # pose name -> pad node
var _holding := {}       # pointer id -> pad node
var _button_down := {}
var _attach_asked := false
var _stage := -1
var _stage_t := 0.0
var _due_since := -1.0

func configure(aed: Node3D, mannequin: NaretMannequin) -> void:
	model = aed
	_mannequin = mannequin
	_home_parent = model.get_parent()
	_home_transform = model.transform
	_port = model.find_child("Port", true, false) as Node3D
	_shock_button = model.find_child("ShockButton", true, false) as MeshInstance3D
	_led = model.find_child("Led", true, false) as MeshInstance3D
	_power = model.find_child("PowerButton", true, false) as MeshInstance3D
	for part in [_power, model.find_child("AED key green", true, false)]:
		if part is Node3D: (part as Node3D).scale = Vector3(POWER_BUTTON_SCALE, 2.0, POWER_BUTTON_SCALE)
	_add_power_symbol(model.find_child("AED key green", true, false) as MeshInstance3D)
	_led_material = _glow_copy(_led, Color("39ff5a"))
	_power_material = _glow_copy(_power, Color("39ff5a"))
	# A green key with a white standby mark; it was a white cap in a green ring, which
	# did not read as the on-switch. It glows once the device is on.
	if _power_material: _power_material.albedo_color = Color("2fae4f")
	for name in PAD_POSES:
		var pad := model.find_child(name, true, false) as Node3D
		if pad == null:
			continue
		_pads[name] = pad
		# Larger while they lie with the device and in the hand; on the chest a pad is
		# its real size again (placing sets its whole transform).
		pad.position.x = signf(pad.position.x) * PAD_REST_X_M
		pad.scale = Vector3(PAD_REST_SCALE, 1.0, PAD_REST_SCALE)
		_pad_rest[name] = pad.transform
		pad.visible = false
		thicken_pad(pad)
	_button_material = _glow_copy(_shock_button, Color("ffb020"))
	if _shock_button:
		_shock_button.scale = Vector3(SHOCK_BUTTON_SCALE, 5.0, SHOCK_BUTTON_SCALE)
		_shock_button.position.z += SHOCK_BUTTON_DOWN_M
		# As high as the power key: scaled about its middle it stood only 7 mm over the
		# face, half of it below, and read as sunk in ("the button is so inside").
		_shock_button.position.y += SHOCK_BUTTON_UP_M
		# Solid orange like the power key is solid green: a material of its own, since the
		# model's keeps its blue printed label whatever colour is set on it.
		_button_material = StandardMaterial3D.new()
		_button_material.albedo_color = Color("e07a10")
		_button_material.roughness = 0.5
		_button_material.emission_enabled = true
		_button_material.emission = Color("ffb020")
		_button_material.emission_energy_multiplier = 0.0
		_shock_button.material_override = _button_material
		for surface in _shock_button.get_surface_override_material_count():
			_shock_button.set_surface_override_material(surface, _button_material)
		# The model's shock button is only a rim round a label printed on the face, so the
		# "button" lay at the bottom of a ring (headset 13 Nov 2026: "the button is so
		# inside"). A solid cap fills the rim to its top; it lights with the rim.
		var top := _top_of(_shock_button)
		var cap := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.017 * SHOCK_BUTTON_SCALE * 0.97
		disc.bottom_radius = disc.top_radius
		disc.height = 0.012
		disc.radial_segments = 32
		cap.mesh = disc
		cap.material_override = _button_material
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.position = top - Vector3(0, disc.height * 0.5, 0)
		model.add_child(cap)
		_add_flash_symbol(_shock_button)
	var glass := model.find_child("Screen", true, false) as Node3D
	if glass: glass.position.z += SCREEN_DOWN_M
	# The device talks through its own speaker, alongside the people around it.
	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 3.0
	model.add_child(_voice)
	# A prompt is always finished before the next one starts.
	_voice.finished.connect(func():
		if not _queued_voice.is_empty():
			var next := _queued_voice
			_queued_voice = ""
			_play_voice(next))
	_screen = model.find_child("Screen", true, false) as MeshInstance3D
	if _screen:
		_build_screen()
	model.visible = false
	_floor_radius = floor_radius()
	_pad_guides = preload("res://scripts/mannequin/aed_pad_guides.gd").new()
	_pad_guides.name = "GoldenPadPlacementGuides"
	add_child(_pad_guides)
	_pad_guides.configure(_mannequin, PAD_POSES, PAD_SIZE)

func _build_screen() -> void:
	## The glass shows a small UI rendered live: prompt, heart rate, ECG trace.
	var view := SubViewport.new()
	view.size = Vector2i(192, 204)
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	model.add_child(view)
	var back := ColorRect.new()
	back.color = Color(0.02, 0.035, 0.035)
	back.size = Vector2(view.size)
	view.add_child(back)
	_screen_prompt = Label.new()
	_screen_prompt.position = Vector2(6, 6)
	_screen_prompt.size = Vector2(180, 64)
	_screen_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_screen_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_screen_prompt.add_theme_font_size_override("font_size", 19)
	view.add_child(_screen_prompt)
	_screen_pulse = Label.new()
	_screen_pulse.position = Vector2(0, 70)
	_screen_pulse.size = Vector2(192, 64)
	_screen_pulse.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_screen_pulse.add_theme_font_size_override("font_size", 46)
	_screen_pulse.add_theme_color_override("font_color", Color("b7f581"))
	view.add_child(_screen_pulse)
	_screen_trace = NaretEKGRenderer.new()
	_screen_trace.position = Vector2(4, 136)
	_screen_trace.size = Vector2(184, 64)
	view.add_child(_screen_trace)
	_screen_material = StandardMaterial3D.new()
	_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_material.albedo_texture = view.get_texture()
	_set_screen("", false)

func _set_screen(prompt: String, pulse: bool) -> void:
	## Dark glass while the device is off; the pulse only with a returned circulation.
	if _screen == null:
		return
	_screen.material_override = _screen_material if powered else null
	_screen_prompt.text = prompt
	_screen_pulse.visible = pulse
	_screen_trace.visible = pulse
	if pulse and ekg:
		_screen_trace.ekg = ekg
		_screen_pulse.text = "♥ %d" % roundi(ekg.bpm)

func _glow_copy(mesh: MeshInstance3D, color: Color) -> StandardMaterial3D:
	if mesh == null:
		return null
	var material := (mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.0
	mesh.material_override = material
	return material

func sync(scenario: NaretScenario, language: String) -> void:
	## Called on the UI tick; cheap when nothing changed. The device is on scene
	## once someone brought it (scenario.aed_available); in hand it is the carrier's.
	# The signs speak the trainee's language from the start (14 Nov 2026: English chosen,
	# the sign said "AED AN"). The language used to be taken over only when the device
	# first spoke, and it is switched on before it says anything, so the sign fell back
	# to the default, German.
	if language != _voice_language:
		_voice_language = language
		if not _on_card.is_empty() and (_on_card.sprite as Sprite3D).visible: _show_on(true)
	if _held:
		_update_pad_guides(scenario)
		return
	_interaction_ready = scenario.aed_available or scenario.aed_attached
	var wanted := _interaction_ready or preview_visible
	if scenario.state == NaretScenario.State.IDLE and not preview_visible:
		wanted = false
	if wanted != _shown:
		_set_shown(wanted)
	model.visible = wanted # Geometry guard may hide and later restore the device.
	# The pads lie with the device from the moment it is there (13 Nov 2026: "no chest
	# pads are seen"; they used to appear only at power-on). Taking one still needs power.
	if wanted:
		for name in _pads: _pads[name].visible = true
	if scenario.aed_attached and not _attached:
		_attach()
	elif not scenario.aed_attached and _attached:
		_detach()
	# Announce an already available outcome before automation can consume NO_SHOCK.
	# Do not delay CPR for speech; its queued device announcement survives the transition.
	_announce(scenario, language)
	_automate(scenario)
	_announce(scenario, language)
	_update_pad_guides(scenario)
	if not _attached:
		_set_screen("" if not powered else {"en": "ATTACH PADS", "de": "ELEKTRODEN AUFKLEBEN", "pl": "NAKLEJ ELEKTRODY"}.get(language, "ATTACH PADS"), false)
		return
	var texts: Array = PROMPTS.get(language, PROMPTS.de)
	var index := 5
	if scenario.state == NaretScenario.State.AED:
		index = scenario.aed_stage
	if Time.get_ticks_msec() / 1000.0 < _shocked_until:
		index = 6
	var back := scenario.state == NaretScenario.State.RECOVERY and scenario.outcome in ["rosc", "trainer_simulated_rosc"]
	if back:
		index = 7
	_set_screen(texts[index], back)
	_blink = scenario.state == NaretScenario.State.AED and scenario.aed_stage == NaretScenario.AEDStage.READY_TO_SHOCK

func _update_pad_guides(scenario: NaretScenario) -> void:
	if not is_instance_valid(_pad_guides): return
	var placing := powered and scenario.aed_available and not _held and not scenario.aed_attached and scenario.state in [NaretScenario.State.CALL_HELP, NaretScenario.State.CPR] and _mannequin.is_visible_in_tree()
	_pad_guides.show_targets(placing, _placed)

func _announce(scenario: NaretScenario, language: String) -> void:
	## Each new device state is spoken once, as a real AED's voice prompts.
	var key := ""
	if powered and not _attached:
		key = "aed_pads"
	elif _attached:
		var now := Time.get_ticks_msec() / 1000.0
		if now < _shocked_until:
			# 18 Nov 2026 (user): the AED itself says it now: "Schock abgegeben. Beginnen Sie
			# sofort mit der Herzdruckmassage." The instructor no longer repeats it.
			key = "aed_shocked"
		elif scenario.state == NaretScenario.State.RECOVERY:
			# Silent once the crew has taken over (fix 7, 17 Nov 2026).
			key = ""
		elif scenario.state == NaretScenario.State.AED:
			# One line for the shock: advised, stand clear, then press (14 Nov 2026: said as
			# two lines it read as "move away" followed by "come and press"). The button
			# starts flashing when the line is over; "press it now" follows only as a
			# reminder (_automate).
			key = ["aed_stop_cpr", "aed_analyse", "aed_shock_advised", "aed_shock_advised", "aed_no_shock"][scenario.aed_stage]
			if scenario.aed_stage == NaretScenario.AEDStage.READY_TO_SHOCK and _remind_press: key = "aed_press_shock"
			# German and Polish "shock advised" says only "stand clear"; the press prompt follows
			# at once (fix 6, 17 Nov 2026). The English line already ends with "press now".
			if scenario.aed_stage == NaretScenario.AEDStage.READY_TO_SHOCK and language != "en": key = "aed_press_shock"
	if key == _last_voice:
		return
	_last_voice = key
	if key.is_empty() or _voice == null:
		return
	_voice_language = language
	# Behind its own line still playing, and behind a person who is speaking: the device
	# does not talk into the instructor's sentence either (_process starts it then).
	if _voice.playing or _others_speaking():
		_queued_voice = key
	else:
		_play_voice(key)

func _others_speaking() -> bool:
	return external_speech_busy.is_valid() and bool(external_speech_busy.call())

var _voice_language := "de"

func _play_voice(key: String) -> void:
	var path := "res://assets/audio/tts_%s/%s.wav" % [_voice_language, key]
	if not ResourceLoader.exists(path):
		spoke.emit(key, _voice_language) # Main can supply service TTS plus exact displayed text.
		return
	_voice.stream = load(path)
	_voice.play()
	spoke.emit(key, _voice_language)

func device_voice_pending() -> bool:
	## The device itself is speaking or about to: a line playing, or one queued behind
	## it. The instructor waits for this before his next prompt
	## (main._announce_coach_step). "Shock delivered" is shown, not spoken, so the shock
	## itself does not make him wait.
	return (_voice != null and _voice.playing) or not _queued_voice.is_empty()

func is_speaking() -> bool:
	return (_voice != null and (_voice.playing or not _queued_voice.is_empty())) or (external_speech_busy.is_valid() and external_speech_busy.call())

func _automate(scenario: NaretScenario) -> void:
	## Both pads on a powered device connect it. From there the device leads, as a real
	## semi-automatic AED does (13 Nov 2026): it says not to touch the patient and
	## analyses, announces "shock advised, stand clear", lets its shock button flash and
	## waits for the trainee to press it. Nobody has to say "everyone is clear" any more;
	## a hand on the patient still stops the analysis (main: patient_contact), and the
	## device simply starts it again.
	if powered and _placed.size() == PAD_POSES.size() and not scenario.aed_attached and not _attach_asked:
		_attach_asked = true
		requested.emit("attach_aed")
	var now := Time.get_ticks_msec() / 1000.0
	# Two minutes of CPR since the last shock: the device stops CPR for a new analysis.
	if scenario.analysis_due and scenario.state == NaretScenario.State.CPR:
		if _due_since < 0.0:
			_due_since = now
		# A moment after the two minutes, as the device finishes its CPR period.
		if now - _due_since > REASSESS_DELAY_S:
			requested.emit("reassess")
	else:
		_due_since = -1.0
	var stage := scenario.aed_stage if scenario.state == NaretScenario.State.AED else -1
	if stage != _stage:
		_stage = stage
		_stage_t = now
		_remind_press = false
	if stage in [NaretScenario.AEDStage.ATTACHED, NaretScenario.AEDStage.SHOCK_ADVISED] and now - _stage_t > CLEAR_DELAY_S and not is_speaking():
		# Its own "do not touch" / "stand clear" has been heard: go on. Refused while a
		# hand is on the patient; then it asks again after the same delay.
		_stage_t = now
		requested.emit("clear_patient")
	elif stage == NaretScenario.AEDStage.READY_TO_ANALYZE and now - _stage_t > ANALYSE_DELAY_S:
		_stage_t = INF
		requested.emit("analyze_rhythm")
	elif stage == NaretScenario.AEDStage.NO_SHOCK:
		requested.emit("resume_cpr")
	elif stage == NaretScenario.AEDStage.READY_TO_SHOCK and now - _stage_t > SHOCK_REMIND_S and not is_speaking():
		# Still not pressed: "press the shock button now".
		_stage_t = now
		_remind_press = true
		_last_voice = ""

func touch(pointer_id: String, tip: Vector3, grip: Vector3, pinched: bool, palm: Vector3 = Vector3.INF, grabbing: bool = false) -> bool:
	## One tracked hand: index fingertip, pinch point, pinch state, and for carrying the
	## whole device the palm and whether the hand is closed. True while the hand works
	## the device, so the caller holds back its own pointer.
	if model == null or not model.visible:
		return false
	var closed := pinched or grabbing
	var hold := palm if grabbing and palm != Vector3.INF else grip
	if _carry_pointer == pointer_id:
		var now := Time.get_ticks_msec()
		if closed:
			_carry_seen_ms = now
			model.global_position = hold + _carry_offset
		elif now - _carry_seen_ms > CARRY_GRACE_MS:
			_let_go()
		return true
	# Taking it: only out of the helper's hand. Until 13 Nov 2026 it could also be picked
	# up again from where it lay while switched off; in the headset a hand closing on
	# the device to work it then carried the whole device off (log 13:36:36).
	var takeable := offered
	if takeable and closed and _carry_pointer.is_empty() and _box_distance(hold) < TAKE_REACH_M:
		if not (_power and not offered and tip.distance_to(_power.global_position) < BUTTON_RELEASE_M):
			_take(pointer_id, hold)
			return true
	if _held or (preview_visible and not _interaction_ready):
		return false
	# The shock: the trainee's own fingertip on the flashing button, nothing else.
	# It counts from "shock advised" on, also before the device has finished saying
	# "stand clear": the trainee who presses then has heard enough.
	if _shock_button and powered:
		var to_button := tip.distance_to(_shock_button.global_position)
		if to_button < SHOCK_RANGE_M and not _shock_down.get(pointer_id, false):
			_shock_down[pointer_id] = true
			print("NARET_AED shock_button_touched hand=", pointer_id, " stage=", _stage, " finger_cm=%.1f" % (to_button * 100.0))
			# Not while the device is still saying "shock advised, stand clear": the shock
			# and the instructor's "resume compressions" would talk over that sentence.
			if _stage == NaretScenario.AEDStage.SHOCK_ADVISED and not device_voice_pending():
				requested.emit("clear_patient")
				requested.emit("shock")
				return true
			if _stage == NaretScenario.AEDStage.READY_TO_SHOCK:
				requested.emit("shock")
				return true
		elif to_button > SHOCK_RANGE_M * 1.5:
			_shock_down[pointer_id] = false
	# A pad sticks to the hand that took it (13 Nov 2026, "I am never able to take it").
	# Holding a pinch or a fist for the half metre from the stool to the chest was the
	# part that failed: in every headset session the pad left the hand again within a
	# moment, at the stool. Now nothing has to be held. Once taken it goes with the
	# hand, and it puts itself on the chest when the hand brings it within PAD_SNAP_M
	# of a free pad place. A hand that is not seen for PAD_LOST_MS loses it (_process).
	if _holding.has(pointer_id):
		var pad: Node3D = _holding[pointer_id]
		_pinch_seen_ms[pointer_id] = Time.get_ticks_msec()
		pad.global_position = grip
		if _near_free_place(pad):
			_holding.erase(pointer_id)
			_drop(pad)
		return true
	# Taking one: a pinch or a closed hand near it, or simply a fingertip on it.
	if powered and not _attached:
		for name in _pads:
			var pad: Node3D = _pads[name]
			if pad.visible and not pad in _placed.values() and not pad in _holding.values() 					and ((closed and _pad_distance(pad, hold) < PAD_GRAB_M) or _pad_distance(pad, tip) < PAD_TOUCH_M):
				_holding[pointer_id] = pad
				_pinch_seen_ms[pointer_id] = Time.get_ticks_msec()
				print("NARET_AED pad_taken ", name, " hand=", pointer_id)
				return true
	if _power and not powered:
		var distance := tip.distance_to(_power.global_position)
		if distance < BUTTON_RANGE_M and not _button_down.get(pointer_id, false):
			_button_down[pointer_id] = true
			_power_on()
		elif distance > BUTTON_RELEASE_M:
			_button_down[pointer_id] = false
		return distance < BUTTON_RELEASE_M
	return false

## The foam card is 2 mm thick in aed.glb: a sliver that is hard to see from the side and
## to aim a pinch at (headset 13 Nov 2026). It is drawn 20 mm thick (first 8, then
## 15 mm, still too thin), like a padded electrode pouch; the icon printed on it moves up
## with its surface. The card itself is drawn 1.35 times its size (16 x 12 cm) while it
## lies with the device, the two moved apart so they do not overlap.
const PAD_FOAM_M := 0.002
const PAD_THICK_M := 0.020
const PAD_REST_SCALE := 1.35
const PAD_REST_X_M := 0.09

func _top_of(part: MeshInstance3D) -> Vector3:
	## Middle of a part's upper face, in the device's own frame.
	var to_model := Transform3D.IDENTITY
	var node: Node3D = part
	while node != null and node != model:
		to_model = node.transform * to_model
		node = node.get_parent() as Node3D
	var box: AABB = to_model * part.mesh.get_aabb()
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)

func _add_flash_symbol(button: MeshInstance3D) -> void:
	## A white lightning flash lying on the shock button.
	if button == null or button.mesh == null: return
	var outline := PackedVector2Array([Vector2(0.2, -1.0), Vector2(-0.6, 0.15), Vector2(-0.05, 0.15),
		Vector2(-0.25, 1.0), Vector2(0.6, -0.2), Vector2(0.05, -0.2)])
	var corners := Geometry2D.triangulate_polygon(outline)
	if corners.is_empty(): return
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for corner in corners:
		tool.set_normal(Vector3.UP)
		tool.add_vertex(Vector3(outline[corner].x, 0.0, outline[corner].y) * 0.016)
	var flash := MeshInstance3D.new()
	flash.mesh = tool.commit()
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash.material_override = white
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.position = _top_of(button) + Vector3(0, 0.0012, 0)
	model.add_child(flash)

func _add_power_symbol(key: MeshInstance3D) -> void:
	## The standby mark (ring with a bar through its top) in white on the green key, so
	## it reads as the on-switch from above. Flat meshes in the device's own frame.
	if key == null: key = _power
	if key == null or key.mesh == null: return
	var to_model := Transform3D.IDENTITY
	var node: Node3D = key
	while node != null and node != model:
		to_model = node.transform * to_model
		node = node.get_parent() as Node3D
	var box: AABB = to_model * key.mesh.get_aabb()
	var top := Vector3(box.get_center().x, box.end.y + 0.0012, box.get_center().z)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.0135
	torus.outer_radius = 0.0175
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	ring.scale.y = 0.15
	var bar := MeshInstance3D.new()
	var stick := BoxMesh.new()
	stick.size = Vector3(0.0045, 0.0012, 0.019)
	bar.mesh = stick
	# The bar leaves the ring on the side away from the pads (the device's upper edge),
	# on a green gap, as on a real standby mark.
	var gap := MeshInstance3D.new()
	var green := BoxMesh.new()
	green.size = Vector3(0.011, 0.0011, 0.008)
	gap.mesh = green
	var under := StandardMaterial3D.new()
	under.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	under.albedo_color = Color("39c85a")
	gap.material_override = under
	gap.position = top + Vector3(0, 0.0002, -0.0155)
	bar.position = top + Vector3(0, 0.0005, -0.0105)
	ring.position = top
	for part in [ring, gap, bar]:
		if part != gap: part.material_override = white
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(part)

static func thicken_pad(pad: Node3D) -> void:
	for child in pad.get_children():
		if not child is Node3D: continue
		if "foam" in String(child.name):
			(child as Node3D).scale.y = PAD_THICK_M / PAD_FOAM_M
			# The mesh is centred on its own thickness: lift it so it grows upward only.
			(child as Node3D).position.y += (PAD_THICK_M - PAD_FOAM_M) * 0.5
		elif "icon" in String(child.name):
			(child as Node3D).position.y += PAD_THICK_M - PAD_FOAM_M

func _box_distance(point: Vector3) -> float:
	var local := model.global_transform.orthonormalized().affine_inverse() * point - BOX_CENTRE
	var outside := (local.abs() - BOX_HALF).max(Vector3.ZERO)
	return outside.length()

func _level() -> Basis:
	## Lying flat, turned as it is now.
	var forward := model.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001: return Basis.IDENTITY
	return Basis.looking_at(-forward.normalized(), Vector3.UP)

func offer(carrier: NaretBystander) -> void:
	## The carrier holds it out flat on the open hand until someone takes it.
	if not _held: pick_up(carrier)
	_carrier = carrier
	_carrier_hand = carrier._hand_attachment()
	offered = true
	_follow_offering_hand()

func withdraw_offer() -> void:
	## Back to the strap carry (the carrier will set it down himself).
	if not offered: return
	offered = false
	if _carrier is NaretBystander: (_carrier as NaretBystander).hold(model, CARRY)

func _follow_offering_hand() -> void:
	if not offered or not is_instance_valid(_carrier_hand) or not is_instance_valid(_carrier): return
	# Lower edge toward the person he faces (characters model +Z forward).
	var facing := _carrier.global_basis.orthonormalized()
	model.global_transform = Transform3D(facing, _carrier_hand.global_position + Vector3(0, OFFER_LIFT_M, 0))

func _take(pointer_id: String, hold: Vector3) -> void:
	var from_helper := offered
	offered = false
	_held = true # In a hand: sync() and the room checks leave it alone until it rests.
	_stop_settle()
	var flat := _level()
	model.reparent(_home_parent, true)
	model.global_transform = Transform3D(flat, model.global_position)
	model.visible = true
	_carry_pointer = pointer_id
	_carry_offset = model.global_position - hold
	_carry_seen_ms = Time.get_ticks_msec()
	print("NARET_AED device_taken hand=", pointer_id, " from_helper=", from_helper)
	taken.emit()

func _let_go() -> void:
	## It rests where the trainee let go: straight down onto the patient's surface.
	_carry_pointer = ""
	_held = false
	_shown = true
	var at := model.global_position
	var rest_y: float = rest_height.call() if rest_height.is_valid() else home_position().y
	if is_finite(rest_y): at.y = rest_y
	if rest_at_home:
		at = home_position()
	else:
		_home_transform = (_home_parent as Node3D).global_transform.affine_inverse() * Transform3D(_level(), at)
	print("NARET_AED device_placed at=(%.2f, %.2f, %.2f) lowered_cm=%.0f" % [at.x, at.y, at.z, (model.global_position.y - at.y) * 100.0])
	if DisplayServer.get_name() == "headless" or not model.is_inside_tree():
		model.transform = _home_transform
	else:
		_settle = model.create_tween()
		_settle.tween_property(model, "transform", _home_transform, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	placed.emit()

func _pad_distance(pad: Node3D, point: Vector3) -> float:
	## Distance to the pad's card, so its whole face can be pinched, not only the middle.
	var local := pad.global_transform.affine_inverse() * point
	var nearest := Vector3(clampf(local.x, -PAD_SIZE.x * 0.5, PAD_SIZE.x * 0.5), 0.0, clampf(local.z, -PAD_SIZE.y * 0.5, PAD_SIZE.y * 0.5))
	return (pad.global_transform * nearest).distance_to(point)

## Being on has to be seen and heard (headset 13 Nov 2026: the device was on and the
## trainee asked "I can't switch it on. Or is it switched on already?"; a slightly
## brighter key was the only sign). Now: two rising beeps, the key lit bright, and a
## green "AED ON" sign above the device for as long as it is on.
## 14 Nov 2026 ("make this font better"): the sign was green letters with a dark
## outline in the engine's default font. It is now a card like "SHOCK DELIVERED"
## (_make_card): dark rounded panel, green edge, the standby symbol of the power key,
## white bold text.
const ON_SIGN := {"en": "AED ON", "de": "AED EIN", "pl": "AED WŁĄCZONY"}
const ON_GREEN := Color("2fd35a")
var _on_card: Dictionary = {}
var _beeper: AudioStreamPlayer3D

## The standby symbol (an open ring with a bar), as on the power key.
class PowerMark extends Control:
	var color := Color.WHITE
	func _draw() -> void:
		var middle := size * 0.5 + Vector2(0, 6)
		var radius := minf(size.x, size.y) * 0.36
		draw_arc(middle, radius, deg_to_rad(-60), deg_to_rad(240), 40, color, 9.0, true)
		draw_line(middle - Vector2(0, radius + 12), middle - Vector2(0, radius * 0.15), color, 9.0, true)

## Flash mark, as on the shock button.
class FlashMark extends Control:
	var color := Color.WHITE
	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(40, 0), Vector2(4, 56), Vector2(28, 56), Vector2(18, 100), Vector2(58, 40), Vector2(34, 40)]), color)

## The sign goes away ON_SIGN_S after power-on (14 Nov 2026, evening: "the AED ON symbol
## must go after some time"). It confirms the switching on; after that the lit power
## key and the device's voice show that it is on.
const ON_SIGN_S := 4.0
var _on_until := 0.0

func _show_on(on: bool) -> void:
	if _on_card.is_empty():
		if not on: return
		var mark := PowerMark.new()
		mark.color = ON_GREEN
		_on_card = _make_card(ON_GREEN, mark, Vector3(0.0, 0.19, 0.0), 10)
	# Shown again for a language change: the time it has left stays as it was.
	if on and not (_on_card.sprite as Sprite3D).visible:
		_on_until = Time.get_ticks_msec() / 1000.0 + ON_SIGN_S
	_card_text(_on_card, str(ON_SIGN.get(_voice_language, ON_SIGN.en)), on)

## "SHOCK DELIVERED" in large letters over the device for as long as its button glows
## after the shock (4 s).
## Drawn as a status card (later the same day: "the font or the style is not good"; it
## was orange letters with a thick dark outline in the engine's default font): a dark
## rounded panel with an orange edge and a flash mark, the text in one line in a bold
## sans-serif (the system's; the default font if there is none), white. The card is laid
## out as an ordinary 2D control, rendered to a texture and shown as a sprite that
## always faces the viewer.
const SHOCK_SIGN := {"en": "SHOCK DELIVERED", "de": "SCHOCK ABGEGEBEN", "pl": "WYŁADOWANIE WYKONANE"}
const CARD_HEIGHT_PX := 150
const CARD_PIXEL_M := 0.00062
const CARD_FONT_PX := 62
const CARD_MARK_PX := Vector2(62, 100)
const SHOCK_ORANGE := Color("ffb020")
var _shock_card: Dictionary = {}

func _make_card(accent: Color, mark: Control, at: Vector3, priority: int) -> Dictionary:
	## A status card over the device: a 2D panel rendered to a texture, shown on a sprite
	## that always faces the viewer. Returns {view, panel, label, sprite}.
	var view := SubViewport.new()
	view.size = Vector2i(400, CARD_HEIGHT_PX)
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	var panel := PanelContainer.new()
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.07, 0.09, 0.11, 0.94)
	card.border_color = accent
	card.set_border_width_all(5)
	card.set_corner_radius_all(34)
	card.content_margin_left = 36
	card.content_margin_right = 40
	card.content_margin_top = 14
	card.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", card)
	view.add_child(panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	panel.add_child(row)
	mark.custom_minimum_size = CARD_MARK_PX
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var label := Label.new()
	var face := SystemFont.new()
	face.font_names = PackedStringArray(["Roboto", "Noto Sans", "Segoe UI", "Arial", "sans-serif"])
	face.font_weight = 700
	label.add_theme_font_override("font", face)
	label.add_theme_font_size_override("font_size", CARD_FONT_PX)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var sprite := Sprite3D.new()
	sprite.texture = view.get_texture()
	sprite.pixel_size = CARD_PIXEL_M
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.render_priority = priority
	sprite.position = at
	sprite.visible = false
	model.add_child(sprite)
	return {"view": view, "panel": panel, "label": label, "sprite": sprite}

func _card_text(card: Dictionary, text: String, on: bool) -> void:
	var label: Label = card.label
	label.text = text
	# The card is as wide as its text needs (the three languages differ a lot), so
	# nothing is cut off and nothing is stretched.
	var face := label.get_theme_font("font")
	var text_px := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CARD_FONT_PX).x
	var card_px := Vector2i(int(ceil(text_px)) + 36 + int(CARD_MARK_PX.x) + 26 + 40 + 16, CARD_HEIGHT_PX)
	(card.view as SubViewport).size = card_px
	(card.panel as PanelContainer).size = Vector2(card_px)
	# Rendered while it is shown; the texture keeps its last picture otherwise.
	(card.view as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	(card.sprite as Sprite3D).visible = on

func _show_shock_sign(on: bool) -> void:
	if _shock_card.is_empty():
		if not on: return
		var mark := FlashMark.new()
		mark.color = SHOCK_ORANGE
		_shock_card = _make_card(SHOCK_ORANGE, mark, Vector3(0.0, 0.31, 0.0), 11)
	_card_text(_shock_card, str(SHOCK_SIGN.get(_voice_language, SHOCK_SIGN.en)), on)

func _beep_on() -> void:
	if not model.is_inside_tree() or DisplayServer.get_name() == "headless": return
	if _beeper == null:
		_beeper = AudioStreamPlayer3D.new()
		_beeper.unit_size = 3.0
		model.add_child(_beeper)
		# Two rising tones, 0.12 s each with a short gap, 16-bit mono.
		const RATE := 22050
		var pcm := StreamPeerBuffer.new()
		pcm.big_endian = false
		for tone in [[880.0, 0.12], [0.0, 0.05], [1320.0, 0.16]]:
			var count := int(float(tone[1]) * RATE)
			for i in count:
				var fade := minf(1.0, minf(i, count - i) / (0.008 * RATE))
				pcm.put_16(int(sin(TAU * float(tone[0]) * i / RATE) * 0.5 * fade * 32767.0))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.data = pcm.data_array
		_beeper.stream = wav
	_beeper.play()

func _power_on() -> void:
	if not powered:
		print("NARET_AED power_on device_y=%.3f" % model.global_position.y)
		_beep_on()
	powered = true
	_show_on(true)
	_mannequin.set_arm_clear(true)
	if _power_material:
		_power_material.emission_energy_multiplier = 2.5
	for name in _pads:
		_pads[name].visible = true

func _pad_target(pose: String) -> Transform3D:
	var at: Array = PAD_POSES[pose]
	return _mannequin.get_body_transform() * Transform3D(Basis.from_euler(at[1] * PI / 180.0), at[0])

## A fingertip this close to a pad takes it.
const PAD_TOUCH_M := 0.035
## A carried pad whose hand has not been seen for this long goes back to the device.
const PAD_LOST_MS := 3000

func _near_free_place(pad: Node3D) -> bool:
	for pose in PAD_POSES:
		if not _placed.has(pose) and pad.global_position.distance_to(_pad_target(pose).origin) < PAD_SNAP_M:
			return true
	return false

func _return_lost_pads() -> void:
	var now := Time.get_ticks_msec()
	for pointer_id in _holding.keys():
		if now - int(_pinch_seen_ms.get(pointer_id, 0)) > PAD_LOST_MS:
			var pad: Node3D = _holding[pointer_id]
			_holding.erase(pointer_id)
			_drop(pad)

func _drop(pad: Node3D) -> void:
	var best := ""
	for pose in PAD_POSES:
		if not _placed.has(pose) and pad.global_position.distance_to(_pad_target(pose).origin) < PAD_SNAP_M:
			if best.is_empty() or pad.global_position.distance_to(_pad_target(pose).origin) < pad.global_position.distance_to(_pad_target(best).origin):
				best = pose
	var nearest := INF
	for pose in PAD_POSES:
		if not _placed.has(pose): nearest = minf(nearest, pad.global_position.distance_to(_pad_target(pose).origin))
	print("NARET_AED pad_released %s nearest_target_cm=%.1f snap_cm=%.1f placed=%s" % [pad.name, nearest * 100.0, PAD_SNAP_M * 100.0, best])
	if best.is_empty():
		pad.create_tween().tween_property(pad, "transform", _pad_rest[String(pad.name)], 0.35).set_trans(Tween.TRANS_SINE)
		pad_missed.emit(pad.name)
		return
	_placed[best] = pad
	pad.global_transform = _pad_target(best)
	_conform(pad)
	_draw_cable(pad)

func pick_up(carrier: NaretBystander) -> void:
	_held = true
	model.visible = true
	carrier.hold(model, CARRY)
	_carrier = carrier
	_carrier_hand = carrier._hand_attachment()
	_hang_from_hand()

## Carried by its strap: the strap's middle at the hand, the device hanging plumb below
## it with its face turned away from the carrier's leg. Until 13 Nov 2026 it was fixed to
## the hand bone and turned with the wrist: it sat tilted at his hip with the hand in
## the middle of the housing ("he holds the AED funny").
const STRAP_LOCAL := Vector3(0.0, 0.02, -0.165)
const STRAP_BELOW_HAND_M := 0.04

func _hang_from_hand() -> void:
	if not _held or offered or not _carry_pointer.is_empty(): return
	if not is_instance_valid(_carrier_hand) or not is_instance_valid(_carrier): return
	if model.get_parent() != _carrier_hand: return
	# The right hand is on the carrier's -X side (characters face +Z).
	var outward := -_carrier.global_basis.x
	outward.y = 0.0
	if outward.length_squared() < 0.001: return
	outward = outward.normalized()
	# Strap edge (the model's -Z) up, face (+Y) outward.
	var basis := Basis(-outward.cross(Vector3.UP), outward, Vector3.DOWN)
	var hand := _carrier_hand.global_position + Vector3.DOWN * STRAP_BELOW_HAND_M
	model.global_transform = Transform3D(basis, hand - basis * STRAP_LOCAL)

func put_down(duration: float = SET_DOWN_S) -> void:
	## Out of the carrier's hand and onto its place beside the patient: it is lowered
	## along a straight path from where the hand is, and lands without a bounce.
	## (Until 13 Nov 2026 it jumped to its place and fell 25 cm with a bounce, which
	## read as the helper throwing the device.)
	_held = false
	offered = false
	model.reparent(_home_parent, true)
	model.scale = Vector3.ONE
	_shown = true
	model.visible = true
	_stop_settle()
	if duration <= 0.0 or not model.is_inside_tree() or DisplayServer.get_name() == "headless":
		model.transform = _home_transform
		return
	_settle = model.create_tween()
	_settle.tween_property(model, "transform", _home_transform, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_settle() -> void:
	if _settle and _settle.is_valid(): _settle.kill()
	_settle = null

func reset() -> void:
	## Back home and hidden, wherever the scene left it (even in a carrier's hand).
	_held = false
	offered = false
	_carry_pointer = ""
	_stop_settle()
	model.reparent(_home_parent, false)
	model.transform = _home_transform
	model.visible = false
	_shown = false
	_detach() # Also clear a partially placed/powered device on restart.
	_button_down.clear()
	_stage = -1
	_due_since = -1.0
	_last_voice = ""
	_queued_voice = ""
	if _voice: _voice.stop()
	if is_instance_valid(_pad_guides): _pad_guides.reset_guides()

## The places (PAD_POSES names) that have no pad on them yet.
func missing_pads() -> Array[String]:
	var missing: Array[String] = []
	for pose: String in PAD_POSES:
		if not _placed.has(pose): missing.append(pose)
	return missing

func pads_ready() -> bool:
	return powered and _placed.size() == PAD_POSES.size()

func set_home_pose(pose: Transform3D) -> void:
	if _attached or _held: return
	var home := (_home_parent as Node3D).global_transform.affine_inverse() * pose
	if home.is_equal_approx(_home_transform): return
	# Pads already taken or placed stay where the hands put them; only the box moves.
	var kept := {}
	for name in _pads:
		if _pads[name] in _placed.values() or _pads[name] in _holding.values(): kept[name] = _pads[name].global_transform
	_stop_settle()
	_home_transform = home
	model.transform = _home_transform
	for name in kept: _pads[name].global_transform = kept[name]

func floor_radius() -> float:
	if is_finite(_floor_radius): return _floor_radius
	# Bound the actual device meshes; pads are part of the stored device envelope.
	var radius := 0.0
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null: continue
		var box := mesh.get_aabb()
		for corner in 8:
			var point := model.to_local(mesh.global_transform * box.get_endpoint(corner))
			radius = maxf(radius, Vector2(point.x, point.z).length())
	return radius if radius > 0.0 else INF

func home_position() -> Vector3:
	return (_home_parent as Node3D).global_transform * _home_transform.origin

func shock() -> void:
	## Button flash and the body's jolt; the scenario already counted the shock.
	_shocked_until = Time.get_ticks_msec() / 1000.0 + 4.0
	_show_shock_sign(true)
	if _button_material:
		_button_material.emission_energy_multiplier = 4.0
	var body := _mannequin.get_node_or_null("Model") as Node3D
	if body:
		var rest := body.position
		var tween := body.create_tween()
		tween.tween_property(body, "position", rest + Vector3(0, 0.018, 0), 0.05)
		tween.tween_property(body, "position", rest, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	_clock += delta
	_follow_offering_hand()
	_hang_from_hand()
	_return_lost_pads()
	if not _shock_card.is_empty() and (_shock_card.sprite as Sprite3D).visible and Time.get_ticks_msec() / 1000.0 >= _shocked_until:
		_show_shock_sign(false)
	if not _on_card.is_empty() and (_on_card.sprite as Sprite3D).visible and Time.get_ticks_msec() / 1000.0 >= _on_until:
		_show_on(false)
	if not _queued_voice.is_empty() and _voice != null and not _voice.playing and not _others_speaking():
		var waiting := _queued_voice
		_queued_voice = ""
		_play_voice(waiting)
	if _button_material:
		var target := (0.5 + 0.5 * sin(_clock * TAU * 1.6)) * 3.0 if _blink else 0.0
		_button_material.emission_energy_multiplier = move_toward(_button_material.emission_energy_multiplier, target, delta * 12.0)
	if _led_material:
		# Ready LED: short green blink every two seconds while powered.
		_led_material.emission_energy_multiplier = 3.0 if _attached and fmod(_clock, 2.0) < 0.15 else 0.0

func _set_shown(value: bool) -> void:
	_shown = value
	model.visible = value
	# No drop-in: the helper lowers it by hand (put_down); a falling, bouncing
	# defibrillator looked thrown.

func _attach() -> void:
	if manual_pad_placement_required and not pads_ready(): return
	## Desktop and autopilot path: pads the hands did not place fly on by themselves.
	_attached = true
	_power_on()
	var delay := 0.3
	for name in _pads:
		var pad: Node3D = _pads[name]
		if pad in _placed.values():
			continue
		var pose: String = PAD_POSES.keys().filter(func(p): return not _placed.has(p))[0]
		_placed[pose] = pad
		var target := _pad_target(pose)
		var tween := pad.create_tween()
		tween.tween_interval(delay)
		tween.tween_method(func(t: float): pad.global_transform = pad.global_transform.interpolate_with(target, t), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func():
			pad.global_transform = target
			_conform(pad)
			_draw_cable(pad))
		delay += 0.5

func _detach() -> void:
	_attached = false
	_blink = false
	powered = false
	_mannequin.set_arm_clear(false)
	_placed.clear()
	_holding.clear()
	_attach_asked = false
	if _power_material:
		_power_material.emission_energy_multiplier = 0.0
	_show_on(false)
	_show_shock_sign(false)
	_set_screen("", false)
	for name in _pads:
		_pads[name].transform = _pad_rest[name]
		_pads[name].visible = false
		for child in _pads[name].get_children():
			if child.name == "Conformed":
				child.queue_free()
			elif child is Node3D:
				child.visible = true
	for cable in _cables:
		cable.queue_free()
	_cables.clear()

func _conform(pad: Node3D) -> void:
	## Electrodes stick to skin: swap the flat foam card for a grid dropped onto
	## the body as it is posed right now, 1.5 mm above the surface.
	var body := _mannequin.find_child("PatientBody", true, false) as MeshInstance3D
	# Headless (tests, CI) registers no skin with the renderer: the flat pad stays.
	if body == null or DisplayServer.get_name() == "headless":
		return
	var baked := body.bake_mesh_from_current_skeleton_pose()
	if baked == null:
		return
	var arrays := baked.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var to_world := body.global_transform
	var centre := pad.global_position
	# Only triangles near the pad, so the ray tests stay in the hundreds.
	var nearby: Array[PackedVector3Array] = []
	var torso: PackedByteArray = _pad_guides.torso_vertex_mask(body,0)
	for i in range(0, indices.size(), 3):
		if not torso[indices[i]] or not torso[indices[i+1]] or not torso[indices[i+2]]: continue
		var a := to_world * vertices[indices[i]]
		if a.distance_to(centre) > 0.14:
			continue
		nearby.append(PackedVector3Array([a, to_world * vertices[indices[i + 1]], to_world * vertices[indices[i + 2]]]))
	var normal := pad.global_basis.y.normalized()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array[Vector3] = []
	var drop := 0.08
	for y in PAD_GRID.y + 1:
		for x in PAD_GRID.x + 1:
			var local := Vector3((float(x) / PAD_GRID.x - 0.5) * PAD_SIZE.x, 0, (float(y) / PAD_GRID.y - 0.5) * PAD_SIZE.y)
			var point := pad.global_transform * local
			var best := INF
			for tri in nearby:
				var at: Variant = Geometry3D.ray_intersects_triangle(point + normal * 0.08, -normal, tri[0], tri[1], tri[2])
				if at != null and (at as Vector3).distance_to(point + normal * 0.08) < best:
					best = (at as Vector3).distance_to(point + normal * 0.08)
			# Past the body's edge, keep the last drop so the rim hugs the flank
			# instead of flapping out as a flat card.
			if best < INF:
				drop = best
			var hit := point + normal * 0.08 - normal * drop
			grid.append(pad.global_transform.affine_inverse() * (hit + normal * 0.0015))
	for y in PAD_GRID.y:
		for x in PAD_GRID.x:
			var i := y * (PAD_GRID.x + 1) + x
			for corner: int in [i, i + 1, i + PAD_GRID.x + 2, i, i + PAD_GRID.x + 2, i + PAD_GRID.x + 1]:
				var cx := corner % (PAD_GRID.x + 1)
				var cy := corner / (PAD_GRID.x + 1)
				tool.set_uv(Vector2(float(cx) / PAD_GRID.x, float(cy) / PAD_GRID.y))
				tool.add_vertex(grid[corner])
	tool.generate_normals()
	var skin := MeshInstance3D.new()
	skin.name = "Conformed"
	skin.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.albedo_texture = PAD_TEXTURE
	material.roughness = 0.85
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin.material_override = material
	for child in pad.get_children():
		if child is MeshInstance3D and not "lead" in String(child.name):
			child.visible = false
	pad.add_child(skin)
	# The lead leaves from the pad's edge, wherever the skin put that edge.
	var lead := pad.get_children().filter(func(c): return "lead" in String(c.name))
	if not lead.is_empty():
		(lead[0] as Node3D).position = grid[PAD_GRID.x / 2] + Vector3(0, 0.003, -0.004)

func _draw_cable(pad: Node3D) -> void:
	## Sagging tube from the pad's lead to the device port, resting on the floor.
	var from := pad.global_transform * LEAD
	for child in pad.get_children():
		if "lead" in String(child.name):
			from = (child as Node3D).global_position
	var to := _port.global_position if _port else model.global_position
	var floor_y := model.global_position.y + 0.006
	var c1 := Vector3(from.x, floor_y, from.z).lerp(to, 0.25)
	var c2 := Vector3(to.x, floor_y, to.z).lerp(from, 0.25)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	const STEPS := 28
	const SIDES := 6
	for i in STEPS + 1:
		var t := float(i) / STEPS
		var point := from.bezier_interpolate(c1, c2, to, t)
		var ahead := from.bezier_interpolate(c1, c2, to, minf(t + 0.01, 1.0)) - from.bezier_interpolate(c1, c2, to, maxf(t - 0.01, 0.0))
		var side := ahead.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.5:
			side = Vector3.RIGHT
		var up := side.cross(ahead).normalized()
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for s in SIDES:
			var angle := TAU * s / SIDES
			var normal := side * cos(angle) + up * sin(angle)
			ring.append(point + normal * 0.0025)
			ring_normals.append(normal)
		rings.append(ring)
		normals.append(ring_normals)
	for i in STEPS:
		for s in SIDES:
			var n := (s + 1) % SIDES
			for pair in [[i, s], [i + 1, s], [i + 1, n], [i, s], [i + 1, n], [i, n]]:
				tool.set_normal(normals[pair[0]][pair[1]])
				tool.add_vertex(rings[pair[0]][pair[1]])
	var cable := MeshInstance3D.new()
	cable.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.1, 0.11)
	material.roughness = 0.45
	cable.material_override = material
	cable.top_level = true
	model.add_child(cable)
	cable.global_transform = Transform3D.IDENTITY
	_cables.append(cable)
