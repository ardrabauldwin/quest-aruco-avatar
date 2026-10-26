extends "res://tests/suite.gd"

class FakeProvider extends Node:
	## The slice of ArucoMarkerTracking's API the gizmos read.
	signal markers_updated(ids: Array)
	var poses := {}
	var ages := {}
	func get_marker_world_pose(id: int) -> Transform3D:
		return poses.get(id, Transform3D.IDENTITY)
	func marker_age_ms(id: int) -> float:
		return ages.get(id, INF)

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var provider := FakeProvider.new()
	tree.root.add_child(provider)
	var gizmos: Node3D = load("res://scripts/tracking/marker_gizmos.gd").new()
	tree.root.add_child(gizmos)
	gizmos.bind(provider)
	check(gizmos.get_child_count() == 0, "no gizmo before the first detection")
	var pose := Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.2, 0.4, -1.0))
	provider.poses[0] = pose
	provider.ages[0] = 20.0
	provider.markers_updated.emit([0])
	gizmos._process(0.0)
	var gizmo := gizmos.get_node_or_null("MarkerGizmo0") as Node3D
	check(gizmo != null and gizmo.global_transform.is_equal_approx(pose), "a detected marker gets a gizmo at its raw world pose")
	check(gizmo != null and gizmo.visible, "a fresh detection shows its gizmo")
	provider.ages[0] = 900.0
	gizmos._process(0.0)
	check(gizmo != null and not gizmo.visible, "a stale marker's gizmo hides instead of showing an old pose")
	gizmos.free()
	provider.free()
	return failures
