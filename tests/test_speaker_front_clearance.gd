extends "res://tests/suite.gd"
const Placement = preload("res://scripts/tracking/speaker_placement.gd")
const Envelope = preload("res://scripts/tracking/speaker_body_envelope.gd")

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
	# Captured Quest case: the grid misses a narrow front pocket for Anna.
	var compact_floor := PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)])
	var compact_obstacles := [Rect2(-1.058073,-1.559014,0.881528,2.153313),Rect2(-1.679249,-1.317193,0.828892,1.555626)]
	var pocket_found := false
	for point in Placement.boundary_candidates(compact_floor, compact_obstacles, 0.445557):
		if Placement.valid(point,0.445557,compact_floor,compact_obstacles,Vector2(-0.380850,0.017220),Vector2(-0.104859,-0.994487)):
			pocket_found = true
	check(pocket_found, "edge-derived candidates recover Anna's valid pocket without reducing clearance")
	# A central first choice blocks both alternatives; a different independent
	# first spot permits two people without relaxing any distance.
	var choices := [[Vector2.ZERO,Vector2(-0.6,0)], [Vector2(0.6,0)], []]
	var chosen := Placement.independent_spots(choices, [0.4,0.4,0.4])
	check(chosen.size() == 2 and chosen[0] == Vector2(-0.6,0), "search moves the first choice to preserve a second independent spot")
	chosen = Placement.independent_spots([[Vector2(-1,0)],[Vector2.ZERO],[Vector2(1,0)]], [0.4,0.4,0.4])
	check(chosen.size() == 3, "three separately fitting people are retained")
	chosen = Placement.independent_spots([[Vector2.ZERO],[Vector2.ZERO],[Vector2.ZERO]], [0.4,0.4,0.4])
	check(chosen.size() == 1, "search never overlaps people to increase visibility")
	var tree := Engine.get_main_loop() as SceneTree
	for path in ["res://scenes/bystander.tscn","res://scenes/bystander_male.tscn"]:
		var person: NaretBystander = load(path).instantiate()
		tree.root.add_child(person)
		var envelope = Envelope.new()
		var radius: float = envelope.radius(person)
		check(is_finite(radius) and radius > 0.25, "actual model envelope replaces assumed 25 cm: " + path)
		# These imported resting bodies measure below 0.5 m. Reserving every inactive
		# facial morph at 2.2 previously inflated them beyond 1.1 m.
		check(radius < 0.6, "inactive facial morphs do not inflate the resting body footprint: " + path)
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
	# The timer may run while a gesture changes the body envelope. It must not
	# swap which actor owns a spot. The render guard restores a safe pose instead.
	var anna: NaretBystander = host.get_node("Bystanders/Anna")
	var instructor: NaretBystander = host.get_node("Instructor")
	var anna_spot := anna.global_position
	var instructor_spot := instructor.global_position
	var skeleton: Skeleton3D = anna.find_children("*", "Skeleton3D", true, false)[0]
	var bone_rest := skeleton.get_bone_pose_position(0)
	skeleton.set_bone_pose_position(0, bone_rest + Vector3(5,0,0))
	skeleton.force_update_all_bone_transforms()
	host._place_speakers_strict()
	check(anna.global_position.is_equal_approx(anna_spot) and instructor.global_position.is_equal_approx(instructor_spot), "animation envelope changes do not move or exchange standing spots")
	host._validate_speakers()
	check(anna.visible and instructor.visible, "an out-of-space animated pose does not blink the assigned characters")
	check(skeleton.get_bone_pose_position(0).is_equal_approx(bone_rest), "render guard restores the last pose that passed clearance")
	for repeat in 5:
		host._place_speakers_strict()
		host._validate_speakers()
		check(anna.visible and instructor.visible and anna.global_position.is_equal_approx(anna_spot) and instructor.global_position.is_equal_approx(instructor_spot), "repeated placement and validation preserve visible identities")
	var before_height := anna.global_position
	# A fingertip-measured floor is explicit and overrides the patient-derived floor.
	host.anchor.floor_touch_offset_m = 0.3
	host.anchor.floor_y = 0.3
	host._place_speakers_strict()
	check(is_equal_approx(anna.global_position.x,before_height.x) and is_equal_approx(anna.global_position.z,before_height.z), "floor correction preserves assigned horizontal spot")
	check(is_equal_approx(anna.global_position.y,before_height.y+0.3), "locked character follows a new measured floor height")
	host.anchor.floor_y = 0.0
	host._place_speakers_strict()
	host.geometry.forward = Vector2(-1,0)
	host._validate_speakers()
	check(not host.get_node("Bystanders/Anna").visible and not host.get_node("Instructor").visible, "an explicit new placement view invalidates BOTH cached positions")
	host.geometry = {}
	host._place_bystanders()
	# No scan and no play-area geometry: explicit setup message, no blind spots.
	check(not host.get_node("Bystanders/Anna").visible and not host.get_node("Instructor").visible,
		"missing geometry hides unverified spots rather than placing people through a wall")
	host.xr.free()
	host.free()
	return failures
