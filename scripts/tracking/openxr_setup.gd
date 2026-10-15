class_name NaretOpenXRSetup
extends Node
var active := false
var interface: XRInterface

func _ready() -> void:
	interface = XRServer.find_interface("OpenXR")
	# OpenXR must initialize before rendering; the project setting requests that.
	if interface == null or not interface.is_initialized():
		return
	active = true
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
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

static func prepare_passthrough_environment(environment: Environment) -> void:
	# An opaque BG_COLOR/SKY can cover passthrough despite transparent_bg=true.
	# Match Godot's documented AR setup, retaining this scene's ambient color/energy.
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

func floor_height_world(origin: XROrigin3D) -> float:
	# Match the original xr_startup.gd floor provider. LOCAL_FLOOR is requested
	# in project.godot, but the runtime can fall back to a non-floor-based space.
	# Do not label origin Y=0 as a measured floor in that case. Recentring applies
	# XRServer's reference transform to tracked poses, so apply it to the floor too.
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
		root.set_script(load("res://addons/naret_upstream/vendors/hand_mesh.gd"))
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
		root.add_child(mesh)
		origin.add_child(root)
