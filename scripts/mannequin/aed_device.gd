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
const BUTTON_RANGE_M := 0.02
const BUTTON_RELEASE_M := 0.035
const PAD_GRAB_M := 0.06
## A pad let go this close to its place sticks there (pads are interchangeable).
const PAD_SNAP_M := 0.08
const ANALYSE_DELAY_S := 5.0
const SHOCK_COUNTDOWN_S := 3.0
const REASSESS_DELAY_S := 3.0
## "Shock delivered" comes a moment after the jolt, not on top of it.
const SHOCKED_VOICE_DELAY_S := 1.8
const PAD_TEXTURE := preload("res://assets/models/aed_pad.png")
const PROMPTS := {
	"de": ["PATIENT NICHT BERÜHREN", "ANALYSE BEREIT", "SCHOCK EMPFOHLEN", "ZURÜCKTRETEN · SCHOCK FOLGT", "KEIN SCHOCK · CPR", "CPR FORTSETZEN", "SCHOCK ABGEGEBEN", "KEIN SCHOCK EMPFOHLEN · PULS"],
	"pl": ["NIE DOTYKAĆ PACJENTA", "GOTOWY DO ANALIZY", "ZALECANE WYŁADOWANIE", "ODSUŃ SIĘ · WYŁADOWANIE", "BEZ WYŁADOWANIA · RKO", "KONTYNUUJ RKO", "WYŁADOWANIE PODANE", "WYŁADOWANIE NIEZALECANE · TĘTNO"],
}

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
	_led_material = _glow_copy(_led, Color("39ff5a"))
	_power_material = _glow_copy(_power, Color("39ff5a"))
	for name in PAD_POSES:
		var pad := model.find_child(name, true, false) as Node3D
		if pad == null:
			continue
		_pads[name] = pad
		_pad_rest[name] = pad.transform
		pad.visible = false
	_button_material = _glow_copy(_shock_button, Color("ffb020"))
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
	if _held:
		return
	var wanted := scenario.aed_available or scenario.aed_attached
	if scenario.state == NaretScenario.State.IDLE:
		wanted = false
	if wanted != _shown:
		_set_shown(wanted)
	if scenario.aed_attached and not _attached:
		_attach()
	elif not scenario.aed_attached and _attached:
		_detach()
	_automate(scenario)
	_announce(scenario, language)
	if not _attached:
		_set_screen("" if not powered else "ELEKTRODEN AUFKLEBEN" if language == "de" else "NAKLEJ ELEKTRODY", false)
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

func _announce(scenario: NaretScenario, language: String) -> void:
	## Each new device state is spoken once, as a real AED's voice prompts.
	var key := ""
	if powered and not _attached:
		key = "aed_pads"
	elif _attached:
		var now := Time.get_ticks_msec() / 1000.0
		if now < _shocked_until:
			key = "aed_shocked" if now > _shocked_until - 4.0 + SHOCKED_VOICE_DELAY_S else ""
		elif scenario.state == NaretScenario.State.RECOVERY:
			key = "aed_no_shock"
		elif scenario.state == NaretScenario.State.AED:
			key = ["aed_stop_cpr", "aed_analyse", "aed_shock_advised", "aed_shock_advised", "aed_no_shock"][scenario.aed_stage]
	if key == _last_voice:
		return
	_last_voice = key
	if key.is_empty() or _voice == null:
		return
	_voice_language = language
	if _voice.playing:
		_queued_voice = key
	else:
		_play_voice(key)

var _voice_language := "de"

func _play_voice(key: String) -> void:
	var path := "res://assets/audio/tts_%s/%s.wav" % [_voice_language, key]
	if not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.play()
	spoke.emit(key, _voice_language)

func is_speaking() -> bool:
	return _voice != null and (_voice.playing or not _queued_voice.is_empty())

func _automate(scenario: NaretScenario) -> void:
	## Both pads on a powered device connect it; then it analyses and, once
	## everyone is clear, counts down and shocks without a button.
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
	if stage == NaretScenario.AEDStage.READY_TO_ANALYZE and now - _stage_t > ANALYSE_DELAY_S:
		_stage_t = INF
		requested.emit("analyze_rhythm")
	elif stage == NaretScenario.AEDStage.READY_TO_SHOCK and now - _stage_t > SHOCK_COUNTDOWN_S and not is_speaking():
		# The "stand clear" announcement is always heard in full before the shock.
		_stage_t = INF
		requested.emit("shock")

func touch(pointer_id: String, tip: Vector3, grip: Vector3, pinched: bool) -> bool:
	## One tracked hand: index fingertip, pinch point, pinch state. True while the
	## hand works the device, so the caller holds back its own pointer.
	if model == null or not model.visible or _held:
		return false
	if _holding.has(pointer_id):
		var pad: Node3D = _holding[pointer_id]
		if pinched:
			pad.global_position = grip
			return true
		_holding.erase(pointer_id)
		_drop(pad)
		return true
	# Any pinch within reach takes a pad, not only the frame it closed: closing the
	# fingers moves the pinch point a few centimetres, for real hands as well.
	if pinched and powered and not _attached:
		for name in _pads:
			var pad: Node3D = _pads[name]
			if pad.visible and not pad in _placed.values() and not pad in _holding.values() and pad.global_position.distance_to(grip) < PAD_GRAB_M:
				_holding[pointer_id] = pad
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

func _power_on() -> void:
	powered = true
	_mannequin.set_arm_clear(true)
	if _power_material:
		_power_material.emission_energy_multiplier = 1.2
	for name in _pads:
		_pads[name].visible = true

func _pad_target(pose: String) -> Transform3D:
	var at: Array = PAD_POSES[pose]
	return _mannequin.get_body_transform() * Transform3D(Basis.from_euler(at[1] * PI / 180.0), at[0])

func _drop(pad: Node3D) -> void:
	var best := ""
	for pose in PAD_POSES:
		if not _placed.has(pose) and pad.global_position.distance_to(_pad_target(pose).origin) < PAD_SNAP_M:
			if best.is_empty() or pad.global_position.distance_to(_pad_target(pose).origin) < pad.global_position.distance_to(_pad_target(best).origin):
				best = pose
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

func put_down() -> void:
	## Back to its place next to the patient's right shoulder, set down with a drop.
	_held = false
	model.reparent(_home_parent, false)
	model.transform = _home_transform
	_shown = false
	_set_shown(true)

func reset() -> void:
	## Back home and hidden, wherever the scene left it (even in a carrier's hand).
	_held = false
	model.reparent(_home_parent, false)
	model.transform = _home_transform
	model.visible = false
	_shown = false
	if _attached:
		_detach()

func home_position() -> Vector3:
	return (_home_parent as Node3D).global_transform * _home_transform.origin

func shock() -> void:
	## Button flash and the body's jolt; the scenario already counted the shock.
	_shocked_until = Time.get_ticks_msec() / 1000.0 + 4.0
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
	if _button_material:
		var target := (0.5 + 0.5 * sin(_clock * TAU * 1.6)) * 3.0 if _blink else 0.0
		_button_material.emission_energy_multiplier = move_toward(_button_material.emission_energy_multiplier, target, delta * 12.0)
	if _led_material:
		# Ready LED: short green blink every two seconds while powered.
		_led_material.emission_energy_multiplier = 3.0 if _attached and fmod(_clock, 2.0) < 0.15 else 0.0

func _set_shown(value: bool) -> void:
	_shown = value
	model.visible = value
	if value:
		# Brought in by a helper: set down with a small drop instead of popping in.
		var rest := model.position
		model.position = rest + Vector3(0, 0.25, 0)
		model.create_tween().tween_property(model, "position", rest, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _attach() -> void:
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
	for i in range(0, indices.size(), 3):
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
