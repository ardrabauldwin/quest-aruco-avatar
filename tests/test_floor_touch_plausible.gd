extends "res://tests/suite.gd"
## A fingertip floor measurement is accepted only where it can be a floor: within 30 cm
## of the headset floor, or further away only with the head at least 1.2 m above the touch
## (9 Nov 2026: a touch 64 cm up, on the manikin or a knee, was saved as the floor).

class Host extends "res://scripts/main.gd":
	var notices: Array[String] = []
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _speaker_geometry() -> Dictionary: return {}
	func _refresh_floor_reference() -> void: pass
	func _toast(text: String) -> void: notices.append(text)

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.anchor.calibration_file = "user://floor_touch_test.cfg"
	host._floor_source = "local_floor"
	host._floor_source_y = 0.0
	host.xr_camera.global_position = Vector3(0, 0.95, 0) # kneeling
	host._on_floor_measured(0.641)
	check(is_zero_approx(host.anchor.floor_touch_offset_m), "a touch 64 cm up with a kneeling head is not a floor")
	check(not host.notices.is_empty() and "64" in host.notices[-1], "the wearer is told how far from the floor the touch was: " + str(host.notices))
	host._on_floor_measured(-0.08)
	check(is_equal_approx(host.anchor.floor_touch_offset_m, -0.08), "a touch 8 cm below the headset floor is accepted")
	host.xr_camera.global_position = Vector3(0, 0.7, 0) # standing on a floor 0.9 m below the stale stage floor
	host._on_floor_measured(-0.9)
	check(is_equal_approx(host.anchor.floor_touch_offset_m, -0.9), "a large correction is accepted when the head is 1.6 m above the touch")
	host.xr_camera.global_position = Vector3(0, 1.0, 0)
	host._on_floor_measured(0.5)
	check(is_equal_approx(host.anchor.floor_touch_offset_m, -0.9), "a touch 50 cm up with the head only 50 cm above it is rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://floor_touch_test.cfg"))
	tree.root.remove_child(host)
	host.free()
	return failures
