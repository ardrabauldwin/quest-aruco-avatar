extends "res://tests/suite.gd"

class Manager extends Node:
	var queries := 0
	var captures := 0
	var removes := 0
	func create_scene_anchors() -> int:
		queries += 1
		return OK # Deliberately never emits a completion/missing callback.
	func are_scene_anchors_created() -> bool: return false
	func remove_scene_anchors() -> void: removes += 1
	func is_scene_capture_supported() -> bool: return true
	func request_scene_capture(_filter: String) -> bool:
		captures += 1
		return true

class Entity extends RefCounted:
	func get_boundary_2d() -> PackedVector2Array:
		return PackedVector2Array([Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)])
	func get_semantic_labels() -> PackedStringArray: return PackedStringArray(["FLOOR"])

func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var room := NaretRoomLayout.new()
	tree.root.add_child(room)
	room.set_process(false)
	var manager := Manager.new()
	room.add_child(manager)
	room._manager = manager
	var states: Array[String] = []
	room.layout_ready.connect(func(status: String): states.append(status))
	room.retry_scan()
	for i in 25: room._advance_queries(5.0)
	check(manager.queries > 2 and states.has("room_scan_missing") and not room._waiting, "accepted queries with no callbacks retry and terminate with a missing-scan message")
	check(manager.removes == 0, "empty native manager is never asked to remove nonexistent anchors")
	check(manager.captures == 0, "empty room data never opens native capture automatically")
	room.retry_scan()
	room.set_session_focused(false)
	var before := manager.queries
	room._advance_queries(200.0)
	check(manager.queries == before and room._waiting, "focus loss pauses queries without consuming the retry window")
	room.set_session_focused(true)
	check(manager.queries == before + 1 and room._retry_elapsed_s == 0.0, "wearing/resuming the headset starts a fresh localisation query")
	check(room.request_capture() and manager.captures == 1, "explicit scan action opens native capture once")
	check(not room.request_capture() and manager.captures == 1, "double clicks cannot open duplicate captures")
	room._on_capture_completed(false)
	var floor := Node3D.new()
	tree.root.add_child(floor)
	floor.rotation.x = -PI / 2.0
	var entity := Entity.new()
	room._on_anchor_created(floor, entity)
	check(room.outline_for(Vector3(0,1.5,0),Vector3.ZERO,0.0).size() == 4, "located floor containing wearer and patient is usable")
	check(room.outline_for(Vector3(10,1.5,0),Vector3(10,0,0),0.0).is_empty(), "saved floor in another room is rejected")
	floor.position.y = 3.0
	check(room.outline_for(Vector3(0,1.5,0),Vector3.ZERO,0.0).is_empty(), "saved floor on another storey is rejected")
	floor.position.y = 0.0
	check(room.outline_for(Vector3(0,1.5,0),Vector3(5,0,0),0.0).is_empty(), "floor must contain the patient as well as the wearer")
	floor.free()
	check(room.floor_outline().is_empty(), "freed anchor is skipped safely")
	room.free()
	return failures
