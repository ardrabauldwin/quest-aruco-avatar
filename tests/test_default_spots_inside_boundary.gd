extends "res://tests/suite.gd"
## Default (patient-relative) character spots respect the headset boundary: Anna,
## Marek, the instructor and the AED spot are pulled inside the play area with a body
## margin and kept off the patient. A roomy boundary leaves the spots untouched
## (9 Nov 2026: in small rooms the characters stood in walls).
const Placement = preload("res://scripts/tracking/speaker_placement.gd")

class Host extends "res://scripts/main.gd":
	var bounds := PackedVector2Array()
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _speaker_geometry() -> Dictionary: return {}
	func _play_area_outline_world() -> PackedVector2Array: return bounds
	func _toast(_text: String) -> void: pass

func _distance_to_edges(point: Vector2, outline: PackedVector2Array) -> float:
	var best := INF
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return best

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	host.default_character_placement = true
	tree.root.add_child(host)
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = true
	host.anchor.floor_locked = true
	host.anchor.floor_y = 0.0
	host.xr_camera.global_position = Vector3(0, 1.6, 1.5)
	host.aed = NaretAED.new()
	host.add_child(host.aed)
	host.aed.configure(host.get_node("AED"), host.mannequin)
	# Roomy boundary: the free default spots stand.
	host.bounds = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])
	host._place_bystanders()
	var free := {}
	for person in host._speaker_people():
		free[person.name] = person.global_position
	var free_aed: Vector3 = host.aed.home_position()
	# Small boundary, 2.4 m x 2.0 m around the patient: every spot must come inside.
	host._reset_speaker_view()
	host.bounds = PackedVector2Array([Vector2(-1.2, -1.0), Vector2(1.2, -1.0), Vector2(1.2, 1.0), Vector2(-1.2, 1.0)])
	host._place_bystanders()
	var centre: Vector3 = host._patient_floor_centre()
	var moved := false
	for person in host._speaker_people():
		var p := Vector2(person.global_position.x, person.global_position.z)
		check(Geometry2D.is_point_in_polygon(p, host.bounds), str(person.name) + " stands inside the boundary")
		check(_distance_to_edges(p, host.bounds) >= host.DEFAULT_SPOT_MARGIN_M - 0.01, str(person.name) + " keeps the body margin from the boundary")
		check(p.distance_to(Vector2(centre.x, centre.z)) >= host.DEFAULT_SPOT_PATIENT_M - 0.01, str(person.name) + " is kept off the patient")
		if not person.global_position.is_equal_approx(free[person.name]): moved = true
	check(moved, "a small boundary actually moves the default spots")
	# The AED lies on the stool beside the patient; the boundary does not move it, and
	# nobody stands on the stool.
	check(host.aed.home_position().is_equal_approx(free_aed), "the stool with the AED stays beside the patient")
	var stool: Vector2 = host._stool_centre()
	for person in host._speaker_people():
		check(Vector2(person.global_position.x, person.global_position.z).distance_to(stool) >= 0.45, str(person.name) + " does not stand on the stool")
	# A patient outside the boundary: the boundary is not the working area and limits nobody.
	host._reset_speaker_view()
	host.bounds = PackedVector2Array([Vector2(2.0, -1.0), Vector2(4.0, -1.0), Vector2(4.0, 1.0), Vector2(2.0, 1.0)])
	host._place_bystanders()
	for person in host._speaker_people():
		check(person.global_position.is_equal_approx(free[person.name]), str(person.name) + " stays by a patient who lies outside the boundary")
	# Roomy again: the free spots return.
	host._reset_speaker_view()
	host.bounds = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])
	host._place_bystanders()
	for person in host._speaker_people():
		check(person.global_position.is_equal_approx(free[person.name]), str(person.name) + " returns to the free default spot in a roomy boundary")
	check(host.aed.home_position().is_equal_approx(free_aed), "the AED spot returns to its free default")
	# No boundary at all: free spots, nothing hidden.
	host._reset_speaker_view()
	host.bounds = PackedVector2Array()
	host._place_bystanders()
	for person in host._speaker_people():
		check(person.global_position.is_equal_approx(free[person.name]), str(person.name) + " uses the free default spot without a boundary")
	tree.root.remove_child(host)
	host.free()
	return failures
