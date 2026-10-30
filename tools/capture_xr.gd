extends SceneTree
## Renders the real main scene through the active OpenXR runtime and saves the view
## from the headset position. With the Meta XR Simulator as runtime this reviews
## XR-only behaviour (hand menu, ragdoll, gaze) on a Mac. Requires forward+:
##   godot --path . --xr-mode on --rendering-method forward_plus \
##         --rendering-driver vulkan --script tools/capture_xr.gd -- --name idle
## macOS OpenXR has no OpenGL binding, so the Quest's compatibility renderer cannot
## be used here; geometry and layout match, lighting is close but not identical.
## In XR the root viewport renders into the swapchain and reads back blank, so a
## spectator camera pinned to the XR camera renders the same world separately.

const SIZE := Vector2i(1440, 900)

var _scene: Node
var _viewport: SubViewport
var _camera: Camera3D
var _name := "xr"
var _frames := 0
var _settle := 240
var _tug_from := Vector3.ZERO

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--name" and index + 1 < args.size():
			_name = args[index + 1]
		if args[index] == "--settle" and index + 1 < args.size():
			_settle = int(args[index + 1])
	_start.call_deferred()

func _start() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.world_3d = root.world_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	root.add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 78.0
	_camera.near = 0.03
	# The app renders for passthrough: transparent background and a hidden room.
	# A review shot needs its own lit environment, or everything reads as black.
	_camera.environment = preload("res://tools/review_env.tres")
	_viewport.add_child(_camera)
	_camera.make_current()
	var interface := XRServer.find_interface("OpenXR")
	print("CAPTURE_XR runtime=", "none" if interface == null else interface.get_name(),
		" initialized=", interface != null and interface.is_initialized())

func _process(delta: float) -> bool:
	if _scene == null:
		return false
	_frames += 1
	if _frames == 1:
		_apply_arguments()
	_aim_camera()
	_apply_tug(delta)
	if _frames < _settle:
		return false
	_capture.call_deferred()
	_scene = null
	return false

func _aim_camera() -> void:
	## Stand where the headset stands, but look at what is being reviewed. The raw
	## head pose of an idle simulator points past a patient lying on the floor.
	var head := _scene.get_node_or_null("XROrigin3D/XRCamera3D") as Node3D
	if head == null:
		return
	var args := OS.get_cmdline_user_args()
	if "--head" in args:
		_camera.global_transform = head.global_transform
		return
	var target: Node3D = _scene.get_node_or_null("SpatialAnchor/Mannequin/Sternum")
	if target == null:
		_camera.global_transform = head.global_transform
		return
	var focus := target.global_position
	if "--overview" in args:
		# Whole scene from outside: checks where bystanders stand and which way
		# they face, which the trainee's own viewpoint cannot show.
		_camera.global_position = focus + Vector3(2.6, 2.4, 2.6)
		_camera.look_at(focus, Vector3.UP)
		return
	if "--face" in args:
		var face: Node3D = _scene.get_node_or_null("SpatialAnchor/Mannequin/Pupils/Left")
		if face: focus = face.global_position
	var eye := head.global_position
	if "--face" in args:
		eye = focus + (head.global_position - focus).normalized() * 0.55
	if eye.distance_to(focus) < 0.05:
		return
	_camera.global_position = eye
	_camera.look_at(focus, Vector3.UP)

func _apply_tug(delta: float) -> void:
	## Scripted pull on a hand, so the ragdoll can be reviewed without hands.
	if not "--tug" in OS.get_cmdline_user_args():
		return
	var mannequin: Node = _scene.get_node_or_null("SpatialAnchor/Mannequin")
	var ragdoll: NaretRagdoll = mannequin.get("ragdoll") if mannequin else null
	if ragdoll == null or not ragdoll.is_active():
		return
	if _frames < 90:
		return
	if _frames == 90:
		_tug_from = ragdoll.limb_point("hand_l")
		ragdoll.grab("review", _tug_from)
		print("CAPTURE_XR tugging hand_l from ", _tug_from)
	var progress := clampf(float(_frames - 90) / 90.0, 0.0, 1.0)
	ragdoll.move("review", _tug_from + Vector3(0.10, 0.34, 0.16) * progress)

func _apply_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	if "--cpr" in args:
		for action in ["start", "begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
			_scene._on_action(action)
	if "--pl" in args:
		_scene._set_language("pl")
	if "--neighbour" in args:
		_scene._set_mode("neighbour")

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var ignore := FileAccess.open("res://build/.gdignore", FileAccess.WRITE)
	if ignore: ignore.close()
	var path := "res://build/xr-%s.png" % _name
	image.save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE_XR saved ", path, " ", image.get_width(), "x", image.get_height())
	quit()
