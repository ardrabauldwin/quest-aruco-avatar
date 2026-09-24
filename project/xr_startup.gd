extends XROrigin3D

# Minimal OpenXR startup: find the interface, initialise it, and switch the
# viewport to XR. Works on both desktop (no headset -> flat fallback) and Quest.

var xr_interface: XRInterface
var _input_diag_elapsed := 0.0


func _ready() -> void:
	print("available interfaces:",XRServer.get_interfaces())
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialised successfully; requested reference space: LOCAL_FLOOR")
		print("OpenXR play-area mode: ", xr_interface.get_play_area_mode(),
			" (ROOMSCALE means a floor-based space is active)")
		xr_interface.play_area_changed.connect(_on_play_area_changed)
		# The XR compositor drives frame pacing; disable the desktop v-sync. (dont wait
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		_enable_passthrough()
	else:
		print("OpenXR not initialised - running in flat (non-XR) mode")


func _on_play_area_changed(mode: XRInterface.PlayAreaMode) -> void:
	print("OpenXR play-area changed: ", mode)


## Include the active profile and raw actions: a tracked hand can be active while exposing
## no thumbstick. Run before placement too, so controller diagnosis does not need markers.
func _process(delta: float) -> void:
	_input_diag_elapsed += delta
	if _input_diag_elapsed < 1.0:
		return
	_input_diag_elapsed = 0.0
	var openxr := xr_interface as OpenXRInterface
	if openxr == null or not openxr.is_initialized():
		return
	var inputs: Array[String] = []
	for hand in ["left_hand", "right_hand"]:
		var tracker := XRServer.get_tracker(hand) as XRControllerTracker
		if tracker == null:
			inputs.append(hand + "=missing")
			continue
		inputs.append("%s profile=%s primary=%s trigger=%s ax=%s" % [
			hand, tracker.get_tracker_profile(), str(tracker.get_input("primary")),
			str(tracker.get_input("trigger")), str(tracker.get_input("ax_button"))])
	print("XR input: state=%s godot_active=%s %s" % [
		openxr.get_session_state(), openxr.is_action_set_active("godot"), " | ".join(inputs)])


## With the LOCAL_FLOOR reference space this origin sits on the physical floor, so its world
## height is the Quest floor height. In flat desktop mode there is no floor estimate.
func has_floor() -> bool:
	return (xr_interface != null and xr_interface.is_initialized()
		and xr_interface.get_play_area_mode() in [XRInterface.XR_PLAY_AREA_ROOMSCALE, XRInterface.XR_PLAY_AREA_STAGE])


func floor_height_world() -> float:
	# Apply recentering consistently with the hand/camera poses.
	return (global_transform * XRServer.get_reference_frame()).origin.y

# Meta passthrough (AR): composite the rendered scene over the real world by switching the
# XR environment blend mode to alpha-blend and clearing the viewport to transparent. Wherever
# the scene draws nothing, the real-world camera shows through; opaque meshes render on top.
func _enable_passthrough() -> void:
	var modes := xr_interface.get_supported_environment_blend_modes()
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		get_viewport().transparent_bg = true
		print("passthrough enabled (alpha blend)")
	else:
		print("alpha-blend passthrough not supported; available modes: ", modes)
