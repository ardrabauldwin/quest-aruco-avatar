extends "res://tests/suite.gd"
const Placement = preload("res://scripts/tracking/speaker_placement.gd")
const Envelope = preload("res://scripts/tracking/speaker_body_envelope.gd")

class Host extends "res://scripts/main.gd":
	var geometry: Dictionary = {}
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _speaker_geometry() -> Dictionary: return geometry
	func _toast(_text: String) -> void: pass

func run() -> Array[String]:
	failures.clear()
	var floor := PackedVector2Array([Vector2(-2.5,-2), Vector2(2.5,-2), Vector2(2.5,2), Vector2(-2.5,2)])
	var eye := Vector2(0,1.5)
	var forward := Vector2(0,-1)
	var obstacles := [Rect2(Vector2(-0.35,-1.05),Vector2(0.7,2.1))]
	var radii := Vector2(0.35,0.45)
	var pair := Placement.pair(floor, obstacles, Vector2.ZERO, radii, eye, forward)
	check(pair.size() == 2, "find two front-facing whole-body spots in roomy floor")
	for i in pair.size():
		check(Placement.valid(pair[i],radii[i],floor,obstacles,eye,forward), "both spots independently meet front and wall rules")
	if pair.size() == 2: check(pair[0].distance_to(pair[1]) > radii.x+radii.y, "full bodies do not overlap")
	check(not Placement.valid(Vector2(0,1.6),0.3,floor,[],eye,forward), "behind point cannot be rescued by sorting")
	check(not Placement.valid(Vector2(0,1.3),0.3,floor,[],eye,forward), "centre ahead but body crossing viewer plane is rejected")
	check(not Placement.valid(Vector2(2.3,0),0.3,floor,[],eye,forward), "centre inside floor but body crossing wall is rejected")
	check(not Placement.valid(Vector2(0.5,0),0.3,floor,obstacles,eye,forward), "centre outside patient but body intersects it is rejected")
	check(Placement.pair(PackedVector2Array(),[],Vector2.ZERO,radii,eye,forward).is_empty(), "no room scan never creates unverified spots")
	var front_blocked := [Rect2(Vector2(-3,-3),Vector2(6,4.5))]
	check(Placement.pair(floor,front_blocked,Vector2.ZERO,radii,eye,forward).is_empty(), "free space behind cannot bypass front requirement")
	var tiny := PackedVector2Array([Vector2(-0.45,-0.45),Vector2(0.45,-0.45),Vector2(0.45,0.45),Vector2(-0.45,0.45)])
	check(Placement.pair(tiny,[],Vector2.ZERO,radii,Vector2(0,1),forward).is_empty(), "no partial pair when only one body can fit")
	var tree := Engine.get_main_loop() as SceneTree
	for path in ["res://scenes/bystander.tscn","res://scenes/bystander_male.tscn"]:
		var person: NaretBystander = load(path).instantiate()
		tree.root.add_child(person)
		var envelope = Envelope.new()
		var radius: float = envelope.radius(person)
		check(is_finite(radius) and radius > 0.25, "actual model envelope replaces assumed 25 cm: " + path)
		# Verify the conservative bound contains rendered, bone-deformed vertices.
		for key in ["idle","talk","reach"]:
			if person._rig.has_clip(key):
				var entry: Dictionary = person._rig._clips[key]
				var player: AnimationPlayer = entry.player
				player.play(entry.name)
				player.seek(player.get_animation(entry.name).length * 0.5, true)
				radius = envelope.radius(person)
				for child in person.find_children("*","MeshInstance3D",true,false):
					var mesh := child as MeshInstance3D
					if mesh.mesh == null: continue
					for surface in mesh.mesh.get_surface_count():
						for vertex in NaretSpatialAnchor.posed_vertices(mesh,surface):
							var offset := mesh.global_transform * vertex - person.global_position
							if Vector2(offset.x,offset.z).length() > radius + 0.0001:
								check(false,"animated skin exceeds placement envelope: " + path + " " + key)
		person.free()
	# Exercise the actual main-scene wiring without starting services or XR.
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = true
	host.anchor.floor_locked = true
	host.anchor.floor_y = 0.0
	host.geometry = {"floor":floor,"blockers":obstacles,"eye":Vector2(-1.5,0),"forward":Vector2(1,0)}
	host._place_bystanders()
	check(host.get_node("Bystanders/Anna").visible and host.get_node("Instructor").visible, "actual main places both model-sized speakers in free front space")
	host.geometry.forward = Vector2(-1,0)
	host._validate_speakers()
	check(not host.get_node("Bystanders/Anna").visible and not host.get_node("Instructor").visible, "head turn invalidates BOTH cached positions")
	host.geometry = {}
	host._place_bystanders()
	# Headset review 2026-10-29: an unscanned room must not leave the scene empty for
	# the whole exercise. Without geometry both stand patient-relative, 1.2 m apart.
	var anna: Node3D = host.get_node("Bystanders/Anna")
	var instructor: Node3D = host.get_node("Instructor")
	check(anna.visible and instructor.visible, "without a scan main falls back to patient-relative placement")
	check(absf(anna.global_position.distance_to(instructor.global_position) - 1.2) < 0.05, "fallback speakers stand 1.2 m apart")
	# Mannequin on a bed, floor not yet locked: the speakers stay on the wearer's floor.
	var anna_floor_y := anna.global_position.y
	host.anchor.floor_locked = false
	host.mannequin.global_position.y += 0.6
	host._bystanders_placed_at = Vector3(INF, INF, INF)
	host._place_bystanders()
	check(anna.visible and absf(anna.global_position.y - anna_floor_y) < 0.02, "a raised patient does not lift the speakers off the wearer's floor")
	check(absf(instructor.global_position.y - anna.global_position.y) < 0.02, "both speakers share the wearer's floor")
	host.xr.free()
	host.free()
	return failures
