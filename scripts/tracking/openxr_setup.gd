class_name NaretOpenXRSetup
extends Node
var active := false
var interface: XRInterface
## Meta's tracked hand meshes, hidden unless switched on for testing.
var hand_meshes: Array[Node3D] = []
## Real-world occlusion from Meta environment depth: "off", "room" (patient
## excluded, hands removed from the depth map) or "all" (patient and hands too).
const OCCLUSION_MODES := ["off", "room", "all"]
var occlusion := "off"
var _environment_depth: Node3D

func _ready() -> void:
	interface = XRServer.find_interface("OpenXR")
	# OpenXR must initialize before rendering; the project setting requests that.
	if interface == null or not interface.is_initialized():
		return
	active = true
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_log_reference_space()
	var blend_modes := interface.get_supported_environment_blend_modes()
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in blend_modes:
		interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		get_viewport().transparent_bg = true
		var world_environment := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
		if world_environment != null and world_environment.environment != null:
			world_environment.environment = world_environment.environment.duplicate()
			prepare_passthrough_environment(world_environment.environment)
	if OS.get_name() == "Android":
		OS.request_permissions()

func _log_reference_space() -> void:
	## Where the app's floor (world y = 0) comes from: requested 1 = Stage (boundary
	## floor), 2 = Local Floor. Without XR_EXT_local_floor Godot emulates the local
	## floor from a start-up guess, which put the characters 7–9 cm in the air on
	## 9 Nov 2026. play_area 4 = STAGE means the boundary floor is in use.
	var local_floor_ext := "unknown"
	if ClassDB.class_exists("OpenXRAPIExtension"):
		var api = ClassDB.instantiate("OpenXRAPIExtension")
		if api != null and api.has_method("is_extension_enabled"):
			local_floor_ext = str(api.is_extension_enabled("XR_EXT_local_floor"))
	print("NARET_XR_SPACE requested=%d play_area=%d local_floor_ext=%s" % [
		int(ProjectSettings.get_setting("xr/openxr/reference_space", -1)), interface.get_play_area_mode(), local_floor_ext])

static func prepare_passthrough_environment(environment: Environment) -> void:
	# An opaque BG_COLOR/SKY can cover passthrough despite transparent_bg=true.
	# Match Godot's documented AR setup, retaining this scene's ambient color/energy.
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

func floor_height_world(origin: XROrigin3D) -> float:
	# The STAGE space (the headset's boundary floor) is requested in project.godot
	# since 9 Nov 2026; before that LOCAL_FLOOR, which Godot may emulate from a
	# start-up guess, left the characters 7–9 cm in the air. The runtime can still
	# fall back to a non-floor-based space: do not label origin Y=0 as a floor then.
	# Recentring applies XRServer's reference transform to tracked poses, so apply
	# it to the floor too.
	if not active or interface == null or not interface.is_initialized():
		return NAN
	if interface.get_play_area_mode() not in [XRInterface.XR_PLAY_AREA_ROOMSCALE, XRInterface.XR_PLAY_AREA_STAGE]:
		return NAN
	return reference_floor_height(origin.global_transform, XRServer.get_reference_frame())

static func reference_floor_height(origin_transform: Transform3D, reference: Transform3D) -> float:
	return (origin_transform * reference).origin.y

func install_hands(origin: XROrigin3D) -> void:
	## Hand tracking is the only input path; controllers are deliberately not bound.
	if not active or not ClassDB.class_exists("OpenXRFbHandTrackingMesh"):
		return
	for index in range(2):
		var side := "left" if index == 0 else "right"
		var root := XRNode3D.new()
		root.name = side.capitalize() + "TrackedHand"
		root.tracker = StringName("/user/hand_tracker/" + side)
		root.set_script(preload("res://scripts/tracking/tracked_hand_visibility.gd"))
		var mesh: Node3D = ClassDB.instantiate("OpenXRFbHandTrackingMesh")
		# The vendor node builds its skeleton on construction, but only when
		# xr/openxr/extensions/meta/hand_tracking_mesh is enabled; naming bones
		# before that logs one error per joint and leaves the mesh unskinned.
		mesh.set("hand", index)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.88, 0.82, 0.7)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.set("material", material)
		var modifier := XRHandModifier3D.new()
		modifier.hand_tracker = root.tracker
		mesh.add_child(modifier)
		# hand_mesh.gd shows/hides the root with tracking every frame, so the
		# testing toggle switches the mesh itself.
		mesh.visible = false
		root.add_child(mesh)
		origin.add_child(root)
		hand_meshes.append(mesh)

func install_environment_depth(camera: XRCamera3D) -> void:
	## OpenXRMetaEnvironmentDepth writes the real room's depth into the depth
	## buffer, so real objects in front hide virtual pixels behind them.
	if not active or not ClassDB.class_exists("OpenXRMetaEnvironmentDepth") or not Engine.has_singleton("OpenXRMetaEnvironmentDepthExtension"):
		return
	_environment_depth = ClassDB.instantiate("OpenXRMetaEnvironmentDepth")
	_environment_depth.name = "EnvironmentDepth"
	camera.add_child(_environment_depth)
	var extension: Object = Engine.get_singleton("OpenXRMetaEnvironmentDepthExtension")
	# Hand removal only takes effect once depth is running.
	extension.connect("openxr_meta_environment_depth_started", _apply_occlusion)
	# Starting needs a running OpenXR session.
	if interface.has_signal("session_begun"):
		interface.connect("session_begun", _apply_occlusion)

func set_occlusion(mode: String) -> void:
	# Do not start a native depth swapchain when the project disables it.
	if not bool(ProjectSettings.get_setting("xr/openxr/extensions/meta/environment_depth", false)):
		occlusion = "off"
		return
	occlusion = mode if mode in OCCLUSION_MODES else "off"
	_apply_occlusion()

func _apply_occlusion() -> void:
	if _environment_depth == null:
		return
	var extension: Object = Engine.get_singleton("OpenXRMetaEnvironmentDepthExtension")
	if not extension.call("is_environment_depth_supported"):
		return
	var on := occlusion != "off"
	_environment_depth.visible = on
	var started: bool = extension.call("is_environment_depth_started")
	if on and not started:
		# There is a GPU cost, so depth only runs while occlusion is on.
		extension.call("start_environment_depth")
	elif not on and started:
		extension.call("stop_environment_depth")
	if on and started and extension.call("is_hand_removal_supported"):
		# Real hands are noisy in the depth map and would cut the arm menu; in
		# "all" they stay in it so they can cover the patient.
		extension.call("set_hand_removal_enabled", occlusion == "room")
	print("NARET_OCCLUSION mode=%s started=%s" % [occlusion, extension.call("is_environment_depth_started")])

func set_hands_visible(visible: bool) -> void:
	for mesh in hand_meshes:
		mesh.visible = visible
