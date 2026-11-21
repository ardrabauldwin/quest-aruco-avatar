extends "res://tests/suite.gd"

class Envelope extends "res://scripts/tracking/speaker_body_envelope.gd":
	func radius(_person: Node3D) -> float: return 0.3

class Host extends "res://scripts/main.gd":
	var geometry: Dictionary = {}
	func _ready() -> void:
		default_character_placement = false
		set_process(false)
	func _process(_delta: float) -> void: pass
	func _speaker_geometry() -> Dictionary: return geometry
	func _toast(_text: String) -> void: pass

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = true
	host.anchor.floor_locked = true
	host.anchor.floor_y = 0.0
	host._speaker_envelope = Envelope.new()
	var floor := PackedVector2Array([Vector2(-0.5,-0.5),Vector2(0.5,-0.5),Vector2(0.5,0.5),Vector2(-0.5,0.5)])
	host.geometry = {"floor":floor,"blockers":[],"eye":Vector2(0,2),"forward":Vector2(0,-1)}
	host._place_bystanders()
	var anna: Node3D = host.get_node("Bystanders/Anna")
	var instructor: Node3D = host.get_node("Instructor")
	var marek: Node3D = host.get_node("Bystanders/Marek")
	check(anna.visible and not instructor.visible and not marek.visible, "one legal spot shows one person; missing helper space does not hide Anna")
	host._validate_speakers()
	check(anna.visible, "independent pre-render guard retains valid actor")
	floor = PackedVector2Array([Vector2(-3,-3),Vector2(3,-3),Vector2(3,3),Vector2(-3,3)])
	host.geometry.floor = floor
	host._place_bystanders()
	check(anna.visible and instructor.visible and marek.visible, "three independent spots when space permits")
	for a in [anna, instructor, marek]:
		for b in [anna, instructor, marek]:
			if a == b: continue
			check(a.global_position.distance_to(b.global_position) > 0.6, "character circles never overlap")
	host.xr.free()
	host.free()
	return failures
