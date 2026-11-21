extends "res://tests/suite.gd"
const Placement = preload("res://scripts/tracking/speaker_placement.gd")

class Host extends "res://scripts/main.gd":
	var bounds := PackedVector2Array()
	func _ready() -> void:
		default_character_placement = false
		set_process(false)
	func _process(_delta: float) -> void: pass
	func _play_area_outline_world() -> PackedVector2Array: return bounds
	func _toast(_text: String) -> void: pass

func run() -> Array[String]:
	var points := PackedVector3Array([Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(2,0,2),Vector3(-2,0,2)])
	var origin := Transform3D(Basis(Vector3.UP,0.5),Vector3(4,0,2))
	var outline := Placement.play_area_outline(points, origin)
	check(outline.size() == 4 and outline[0].distance_to(Vector2((origin * points[0]).x,(origin * points[0]).z)) < 0.0001, "play-area points use the origin transform exactly once")
	check(Placement.play_area_outline(PackedVector3Array(), origin).is_empty(), "absent bounds do not invent a rectangle")
	check(Placement.play_area_outline(PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ONE]), origin).is_empty(), "invalid repeated bounds are rejected")
	var floor := PackedVector2Array([Vector2(-2.5,-2),Vector2(2.5,-2),Vector2(2.5,2),Vector2(-2.5,2)])
	var smaller := PackedVector2Array([Vector2(-1.8,-1.5),Vector2(1.8,-1.5),Vector2(1.8,1.5),Vector2(-1.8,1.5)])
	var radii := Vector2(0.35,0.45)
	var pair := Placement.pair(floor,[],Vector2.ZERO,radii,Vector2(0,1.0),Vector2(0,-1),smaller)
	check(pair.size() == 2, "search can place a complete pair within available play-area bounds")
	for i in pair.size():
		check(Placement.valid(pair[i],radii[i],smaller,[],Vector2(0,1),Vector2(0,-1)), "whole body stays inside the bounded fallback")
	var tree := Engine.get_main_loop() as SceneTree
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = true
	host.anchor.floor_locked = true
	host.anchor.floor_y = 0.0
	host.xr_camera.global_position = Vector3(-1.5,1.6,0)
	host.xr_camera.look_at(Vector3(0,1.6,0))
	host.bounds = floor
	host._place_bystanders()
	var anna: Node3D = host.get_node("Bystanders/Anna")
	var instructor: Node3D = host.get_node("Instructor")
	check(anna.visible and instructor.visible and host._speaker_issue == "play_area", "actual scene uses bounded fallback when no scan exists")
	var before := anna.global_position
	host.xr_camera.rotate_y(PI)
	host._place_bystanders()
	host._validate_speakers()
	check(anna.visible and instructor.visible and anna.global_position.is_equal_approx(before), "turning the head does not drag or hide the placed speakers")
	host._speaker_view.clear()
	host.mannequin.global_position = Vector3(3.0,0,0)
	host.xr_camera.global_position = Vector3(-3.0,1.6,0)
	host.xr_camera.look_at(Vector3(0,1.6,0))
	host._place_bystanders()
	check(not host._speaker_geometry().is_empty(),"outside viewer/patient do not discard valid speaker floor geometry")
	check(anna.visible and instructor.visible,"both speakers can remain inside valid bounds while viewer and patient are outside")
	host.bounds = PackedVector2Array()
	host._place_bystanders()
	check(not anna.visible and not instructor.visible and host._speaker_issue == "scan_or_floor_missing", "missing scan and bounds never trigger fixed patient-relative positions")
	var menu := NaretHandMenu.new()
	tree.root.add_child(menu)
	menu.configure(host.origin, 0)
	menu.set_process(false)
	var setup := NaretScenario.new()
	for language in ["en", "de", "pl"]:
		menu.language = language
		menu.update_session(setup)
		check(menu._reposition_key.get_parent()==menu._controls and menu._setup_keys.size() == 4, "wrist controls: Reposition plus the four setup fold-out keys")
		check(menu._action_keys.all(func(key): return not key.visible), "setup contains no scan/retry actions in any language")
	check(is_equal_approx(menu._large_start.position.y, menu._large_align.position.y) and menu._large_start.position.x < 0.0 and menu._large_align.position.x > 0.0 and menu._large_start.position.y < menu._setup_keys["situation"].position.y, "Start and Save side by side below the setup keys (on the hand's screen since 20 Nov 2026)")
	setup.start()
	menu.update_session(setup)
	check(not menu.has_signal("room_scan_requested") and not menu.has_signal("room_retry_requested"), "hand menu cannot initiate room scanning")
	check(not host.has_method("_request_room_scan") and not host.has_method("_update_room_scan_prompt"), "app has no room-capture or automatic-popup handlers")
	setup.free()
	menu.free()
	host.xr.free()
	host.free()
	return failures
