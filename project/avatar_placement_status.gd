extends Node
## User-facing placement status for either the headset Label3D or desktop Label.

@export var avatar_rig: Node3D

## OpenXR session state 5 = FOCUSED: only then does the headset deliver hands and controllers to
## the app. After a "tracking lost" dialog or a system menu the app can come back merely VISIBLE
## (state 4) and stays without any input (2026-09-24: four times, every "hands not detected").
const SESSION_FOCUSED := 5
var _openxr: OpenXRInterface


func _session_paused() -> bool:
	if _openxr == null:
		_openxr = XRServer.find_interface("OpenXR") as OpenXRInterface
	return _openxr != null and _openxr.is_initialized() and _openxr.get_session_state() != SESSION_FOCUSED


func _process(_delta: float) -> void:
	var placed := avatar_rig != null and avatar_rig.is_visible_in_tree()
	set("text", "Avatar placed" if placed else "Placing avatar…")
	if placed and avatar_rig.has_method("manual_yaw_degrees"):
		set("text", "Avatar placed · angle %+.1f°\nRight stick ← / →: turn" % avatar_rig.manual_yaw_degrees())
	if _session_paused():
		set("text", "HEADSET PAUSED THIS APP (tracking lost or menu open)\nPress the Meta button, then close the menu, to get hands back")
