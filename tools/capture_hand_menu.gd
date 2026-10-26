extends SceneTree
## Renders the palm menu alone, lit like the main scene, with a fake tracked hand
## instead of a headset, so its look can be reviewed on a Mac with the Quest's
## gl_compatibility renderer:
##   godot --path . --xr-mode off --script tools/capture_hand_menu.gd -- --state cpr --pl
## The primary key is shown hovered by a fingertip; the shot lands in build/.

const SIZE := Vector2i(1200, 1000)

var _stage: Node3D
var _viewport: SubViewport
var _menu: NaretHandMenu
var _scenario: NaretScenario
var _frames := 0

func _initialize() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.34, 0.36)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.76, 0.82)
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_stage.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 30, 0)
	key.light_energy = 1.4
	_stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.5
	_stage.add_child(fill)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.world_3d = root.world_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	# The menu opens toward the root viewport's camera; a twin in the offscreen
	# viewport renders the same view into the PNG.
	var eye := Camera3D.new()
	eye.position = Vector3(0.05, 1.62, 0)
	_stage.add_child(eye)
	eye.make_current()
	var camera := Camera3D.new()
	camera.fov = 40.0
	_viewport.add_child(camera)
	camera.make_current()
	var origin := XROrigin3D.new()
	_stage.add_child(origin)
	var palm_position := Vector3(-0.02, 1.34, -0.42)
	# Palm turned to the face but rolled a little, so the cuff and nodes read as 3D.
	var to_head := ((eye.position - palm_position).normalized() + Vector3(0.35, -0.1, 0)).normalized()
	var x_axis := Vector3.UP.cross(to_head).normalized()
	var palm := Transform3D(Basis(x_axis, to_head.cross(x_axis).normalized(), to_head), palm_position)
	var hand: XRHandTracker = load("res://tests/test_tracking.gd").synth_hand(palm)
	XRServer.add_tracker(hand)
	_draw_hand(hand)
	_menu = NaretHandMenu.new()
	_stage.add_child(_menu)
	_menu.configure(origin, 0)
	_scenario = NaretScenario.new()
	_stage.add_child(_scenario)
	var args := OS.get_cmdline_user_args()
	var state := "idle"
	for index in args.size():
		if args[index] == "--state" and index + 1 < args.size():
			state = args[index + 1]
	if "--pl" in args:
		_menu.set_language("pl")
	if state != "idle":
		_scenario.start()
		for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
			_scenario.submit_action(action)
			if _scenario.state == NaretScenario.State[state.to_upper()]:
				break
	_menu.set_listening("--mic" in args)
	_menu._debug_choices.visible = "--debug" in args
	var ekg := NaretEKG.new()
	ekg.set_rhythm(NaretEKG.Rhythm.VF if state == "cpr" else NaretEKG.Rhythm.SINUS)
	ekg.advance(3.0)
	_stage.add_child(ekg)
	_menu.ekg = ekg
	_menu.update_session(_scenario)
	print("CAPTURE_MENU state=", state, " actions=", _scenario.get_available_actions())
	# Look at the hand from the wearer's eye.
	eye.look_at_from_position(eye.position, palm_position + Vector3(0, 0.02, 0), Vector3.UP)
	camera.transform = eye.transform

func _draw_hand(hand: XRHandTracker) -> void:
	## Ghost joints so the review shot shows what the UI is anchored to.
	for joint in [XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_THUMB_TIP,
		XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
		XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]:
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.008
		sphere.height = 0.016
		dot.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.85, 0.7, 0.6)
		dot.material_override = material
		dot.position = hand.get_hand_joint_transform(joint).origin
		_stage.add_child(dot)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 30 and _frames < 60:
		_menu._action_keys[0].pointer_hover(-0.003)
	if _frames == 45:
		_menu.update_session(_scenario)
	if _frames == 60:
		_capture.call_deferred()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var suffix := "-".join(OS.get_cmdline_user_args()).replace("--", "")
	var path := "res://build/hand-menu%s.png" % ("" if suffix.is_empty() else "-" + suffix)
	image.save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE_MENU saved ", path)
	quit()
