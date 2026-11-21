extends SceneTree
## The hand menu in a desktop window, to try it with the mouse instead of the headset
## (20 Nov 2026):
##   godot --path . --xr-mode off --script tools/preview_hand_menu.gd
## A fake tracked left hand holds the menu; a click presses the key under the pointer like
## a fingertip. Language, mode and the setup choices are applied as the app does, "Start
## training" starts a scenario, so the keys change as they would in the headset.
## Esc closes the window. Nothing is saved.

var _menu: NaretHandMenu
var _scenario: NaretScenario
var _camera: Camera3D
var _status: Label
var _answers := {"language": "de", "mode": "own", "situation": "B", "breaths": "yes"}
var _held: NaretHandMenu.Key3D

class Pointer extends Node:
	var owner_tree: SceneTree
	func _unhandled_input(event: InputEvent) -> void:
		owner_tree.call("_on_input", event)

func _initialize() -> void:
	root.title = "NaReT hand menu preview 3 (all keys stay, NaReT header)"
	root.size = Vector2i(1280, 960)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.34, 0.36)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.76, 0.82)
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	# The wearer's eye; the palm is held up 45 cm in front, turned to the face.
	_camera = Camera3D.new()
	_camera.position = Vector3(0.05, 1.62, 0)
	_camera.fov = 40.0
	stage.add_child(_camera)
	_camera.make_current()
	var palm_position := Vector3(-0.02, 1.34, -0.42)
	var to_head := ((_camera.position - palm_position).normalized() + Vector3(0.35, -0.1, 0)).normalized()
	var x_axis := Vector3.UP.cross(to_head).normalized()
	var palm := Transform3D(Basis(x_axis, to_head.cross(x_axis).normalized(), to_head), palm_position)
	_camera.look_at_from_position(_camera.position, palm_position + Vector3(0.0, 0.03, 0), Vector3.UP)
	var hand: XRHandTracker = load("res://tests/test_tracking.gd").synth_hand(palm)
	XRServer.add_tracker(hand)
	for joint in [XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_THUMB_TIP,
		XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
		XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]:
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.008
		sphere.height = 0.016
		dot.mesh = sphere
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.85, 0.7, 0.6)
		dot.material_override = skin
		dot.position = hand.get_hand_joint_transform(joint).origin
		stage.add_child(dot)
	var origin := XROrigin3D.new()
	stage.add_child(origin)
	_menu = NaretHandMenu.new()
	stage.add_child(_menu)
	_menu.configure(origin, 0)
	_scenario = NaretScenario.new()
	stage.add_child(_scenario)
	_menu.set_setup(_answers)
	_menu.language_requested.connect(func(code: String):
		_answers["language"] = code
		_menu.set_language(code)
		_say("language -> " + code))
	_menu.mode_requested.connect(func(mode: String):
		_menu.set_mode(mode)
		_say("mode -> " + mode))
	_menu.setup_requested.connect(func(step: String, value: String):
		_answers[step] = value
		_menu.set_setup(_answers)
		_say(step + " -> " + value))
	_menu.action_requested.connect(func(action: String):
		if action in ["start", "restart"]:
			_scenario.reset()
			_scenario.start()
			# A sample conversation, to see the dialogue page (the cuff's key turns to the menu).
			_menu.clear_dialogue()
			_menu.add_dialogue("Instruktor", "Du siehst eine Person, die Hilfe braucht. Was tust du zuerst?", false)
			_menu.add_dialogue("Du", "Zuerst schaue ich, ob die Umgebung sicher ist.", true)
			_menu.add_dialogue("Instruktor", "Ist die Umgebung sicher? Bitte antworte mit ja oder nein.", false)
		else:
			_scenario.submit_action(action)
		_say("action: " + action))
	_menu.occlusion_requested.connect(func(mode: String):
		_menu.set_occlusion(mode)
		_say("depth -> " + mode))
	_menu.sensor_log_requested.connect(func(on: bool):
		_menu.set_sensor_log("http://192.168.0.10:8080/?pin=1234" if on else "")
		_say("sensor log " + ("on" if on else "off")))
	_menu.take_requested.connect(func(start: bool):
		_menu.set_take(start)
		_say("take " + ("started" if start else "stopped")))
	_menu.recording_requested.connect(func(on: bool): _say("microphone " + ("on" if on else "off")))
	for signal_name in ["export_requested", "reposition_requested", "alignment_save_requested", "floor_calibration_requested",
		"chest_calibration_requested", "fresh_start_requested"]:
		_menu.connect(signal_name, func(): _say(signal_name.trim_suffix("_requested").replace("_", " ")))
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_status = Label.new()
	_status.position = Vector2(20, 16)
	_status.add_theme_font_size_override("font_size", 20)
	layer.add_child(_status)
	_say("")
	var pointer := Pointer.new()
	pointer.owner_tree = self
	root.add_child(pointer)

func _say(what: String) -> void:
	_status.text = "Click a key, as a fingertip would touch it.   Esc: close\n" + ("" if what.is_empty() else "Last: " + what)
	if not what.is_empty(): print("PREVIEW ", what)

func _key_at(screen: Vector2) -> NaretHandMenu.Key3D:
	## The visible key whose face the pointer's ray meets first.
	var from := _camera.project_ray_origin(screen)
	var direction := _camera.project_ray_normal(screen)
	var best: NaretHandMenu.Key3D = null
	var best_distance := INF
	for node in _menu.find_children("*", "Node3D", true, false):
		var key := node as NaretHandMenu.Key3D
		if key == null or not key.is_visible_in_tree(): continue
		var plane := Plane(key.global_basis.z.normalized(), key.global_position)
		var hit: Variant = plane.intersects_ray(from, direction)
		if hit == null: continue
		var local: Vector3 = key.global_transform.affine_inverse() * (hit as Vector3)
		if absf(local.x) > key.size.x * 0.5 or absf(local.y) > key.size.y * 0.5: continue
		var distance := from.distance_to(hit as Vector3)
		if distance < best_distance:
			best_distance = distance
			best = key
	return best

func _on_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		quit()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_held = _key_at(event.position)
			if _held: _held.pointer_press(true)
		elif _held:
			_held.pointer_press(false)
			_held = null

var _frames := 0

func _selftest() -> void:
	## -- --selftest: clicks the language key and then "Polski" by their screen positions,
	## saves build/preview-selftest.png and quits.
	_frames += 1
	if _frames == 40 or _frames == 60:
		var target: Node3D = _menu._language_menu if _frames == 40 else _menu._language_keys["pl"]
		var key := _key_at(_camera.unproject_position(target.global_position))
		print("PREVIEW selftest click hits ", "the intended key" if key == target else "ANOTHER key or nothing")
		if key:
			key.pointer_press(true)
			key.pointer_press(false)
	if _frames == 50:
		print("PREVIEW selftest popup open=", _menu.popup_open())
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/preview-selftest.png"))
	if _frames == 70:
		print("PREVIEW selftest language=", _menu.language, " popup open=", _menu.popup_open())
		quit()

func _process(_delta: float) -> bool:
	if _menu == null: return false
	if "--selftest" in OS.get_cmdline_user_args(): _selftest()
	_menu.update_session(_scenario)
	var hovered := _key_at(root.get_mouse_position())
	if hovered: hovered.pointer_hover(0.0)
	return false
