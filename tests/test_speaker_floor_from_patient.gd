extends "res://tests/suite.gd"
## Anna, Marek and the AED stand on the floor the headset reports (Stage = boundary
## floor), never on the patient's height: trainings happen in different rooms and a
## patient on a bed must not lift them (decision of 9 Nov 2026).

class Host extends "res://scripts/main.gd":
	var notices: Array[String] = []
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _speaker_geometry() -> Dictionary: return {}
	func _toast(text: String) -> void: notices.append(text)

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	host.default_character_placement = true
	tree.root.add_child(host)
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.floor_locked = true
	host.anchor.floor_y = 0.0
	host.anchor.locked = true
	for sternum_y in [0.13, 0.21, 0.95]:
		host.anchor.global_position.y = sternum_y
		check(is_equal_approx(host._speaker_floor_y(), 0.0), "speakers stay on the headset floor with the sternum at %.2f m" % sternum_y)
	host.anchor.floor_touch_offset_m = -0.07
	host.anchor.floor_y = -0.07
	check(is_equal_approx(host._speaker_floor_y(), -0.07), "a fingertip-measured floor correction is used as measured")
	host.anchor.floor_touch_offset_m = 0.0
	host.anchor.floor_y = 0.0
	host._log_floor_check_once()
	host._log_floor_check_once()
	check(host.notices.is_empty(), "no floor notice is shown; the floor comes from the headset")
	host._place_bystanders()
	for person in host._speaker_people():
		check(is_equal_approx(person.global_position.y, 0.0), str(person.name) + " stands on the headset floor")
	if host.aed:
		check(is_equal_approx(host.aed.home_position().y, 0.0), "the AED home spot is on the headset floor")
		check(not host.aed.model.visible, "the AED stays hidden until Marek brings it, no flicker from the default spot")
	tree.root.remove_child(host)
	host.free()
	return failures
