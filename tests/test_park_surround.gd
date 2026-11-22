extends "res://tests/suite.gd"
## Park outside the play area (issue #1, 1.): walls on the boundary and a cap above;
## the patient always lies inside.

func run() -> Array[String]:
	failures.clear()
	var room := PackedVector2Array([Vector2(-2, -1.5), Vector2(2, -1.5), Vector2(2, 1.5), Vector2(-2, 1.5)])
	var area := NaretParkSurround._area(room, Vector2(0, 0))
	check(area.size() >= 4, "a room boundary gives the park's area")
	check(Geometry2D.is_point_in_polygon(Vector2(1.99, 1.49), area), "the area lies just outside the boundary")
	check(not Geometry2D.is_point_in_polygon(Vector2(2.2, 0), area), "and not much further")
	var small := PackedVector2Array([Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)])
	var grown := NaretParkSurround._area(small, Vector2(1.5, 0))
	check(Geometry2D.is_point_in_polygon(Vector2(1.5, 0), grown) and Geometry2D.is_point_in_polygon(Vector2(2.4, 0), grown),
		"a patient outside a small boundary is taken in, with room around")
	check(NaretParkSurround._area(PackedVector2Array(), Vector2.ZERO).size() >= 4, "without a boundary the area surrounds the patient")
	var park := NaretParkSurround.new()
	check(park.build(room, 0.0, Vector2.ZERO), "the park builds")
	var walls := park.get_node("Walls") as MeshInstance3D
	var cap := park.get_node("Cap") as MeshInstance3D
	check(walls != null and cap != null, "walls and cap exist")
	check(walls.mesh.get_aabb().position.y >= -0.001 and is_equal_approx(walls.mesh.get_aabb().end.y, NaretParkSurround.CAP_HEIGHT), "walls stand from the floor to the cap")
	check(cap.mesh.get_surface_count() == 1, "the cap is triangulated")
	park.free()
	return failures
