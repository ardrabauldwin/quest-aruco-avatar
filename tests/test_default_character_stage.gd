extends "res://tests/suite.gd"

class Host extends "res://scripts/main.gd":
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _speaker_geometry() -> Dictionary: return {}
	func _toast(_text: String) -> void: pass

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var host = load("res://scenes/main.tscn").instantiate()
	check(host.default_character_placement, "production scene enables requested visible defaults")
	host.set_script(Host)
	host.default_character_placement = true # set_script replaces exported property values
	tree.root.add_child(host)
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = true
	host.anchor.floor_locked = true
	host.anchor.floor_y = 0.0
	host.xr_camera.global_position = Vector3(0,1.6,1.2)
	host.scenario = NaretScenario.new()
	host.scenario.aed_available = false # Same initial reset performed by the live director.
	host.add_child(host.scenario)
	host.aed = NaretAED.new()
	host.add_child(host.aed)
	host.aed.configure(host.get_node("AED"),host.mannequin)
	host.aed.manual_pad_placement_required = true
	host._place_bystanders()
	var positions: Array[Vector3] = []
	for person in host._speaker_people():
		check(person.visible, "default mode shows " + str(person.name) + " without room geometry")
		positions.append(person.global_position)
	for i in positions.size():
		for j in range(i+1,positions.size()): check(positions[i].distance_to(positions[j]) >= host.DEFAULT_SPOT_SEPARATION_M, "default people have separate standing spots")
	host.aed.sync(host.scenario,"en")
	# On the headset the device stays out of sight until Marek brings it (9 Nov 2026):
	# a defibrillator lying there from the first scene contradicts the scenario.
	check(not host.aed.model.visible, "AED is not shown on the headset before delivery")
	check(not host.scenario.aed_available, "hidden default spot does not invent a delivery event")
	check(not host.aed.touch("test",Vector3.ZERO,Vector3.ZERO,true), "preview cannot bypass delivery interaction gate")
	host._validate_speakers()
	for person in host._speaker_people(): check(person.visible, "room guard cannot hide a default character")
	host.xr_camera.global_position += Vector3(0.2,0,0.1)
	host._place_bystanders()
	for i in positions.size(): check(host._speaker_people()[i].global_position.is_equal_approx(positions[i]), "head movement does not move default characters")
	# A fingertip-measured floor is explicit and overrides the patient-derived floor.
	host.anchor.floor_touch_offset_m = 0.3
	host.anchor.floor_y = 0.3
	host._place_bystanders()
	for i in positions.size():
		var expected: Vector3 = positions[i]+Vector3(0,0.3,0)
		check(host._speaker_people()[i].global_position.is_equal_approx(expected), "default characters follow measured floor correction")
	check(host._prepare_aed_delivery(), "default helper and AED delivery do not wait on room geometry")
	host.xr.free()
	host.free()
	return failures
