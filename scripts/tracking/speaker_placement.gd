extends RefCounted
## Conservative circles enclose the supplied bodies. Geometry is room-space XZ.
## Guarantees concern the supplied scan, not unscanned physical objects.

static func valid(point: Vector2, radius: float, floor: PackedVector2Array, obstacles: Array, eye: Vector2, forward: Vector2) -> bool:
	if floor.size() < 3 or not is_finite(radius) or radius <= 0.0 or forward.length_squared() < 0.5:
		return false
	if not Geometry2D.is_point_in_polygon(point, floor):
		return false
	# Entire footprint must be ahead, not just its origin. Touching is rejected.
	if forward.normalized().dot(point - eye) <= radius:
		return false
	if NaretRoomLayout._distance_to_outline(floor, point) <= radius:
		return false
	for rect: Rect2 in obstacles:
		if NaretRoomLayout._distance_to_rect(rect, point) <= radius:
			return false
	return true


static func pair(floor: PackedVector2Array, obstacles: Array, patient: Vector2, radii: Vector2, eye: Vector2, forward: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var first: Array[Vector2] = []
	var second: Array[Vector2] = []
	for point in NaretRoomLayout._candidates(floor, patient) if floor.size() >= 3 else []:
		if valid(point, radii.x, floor, obstacles, eye, forward): first.append(point)
		if valid(point, radii.y, floor, obstacles, eye, forward): second.append(point)
	# Consider the complete front-facing search, not only four preselected spots.
	var rank := func(a: Vector2, b: Vector2): return a.distance_to(patient) < b.distance_to(patient)
	first.sort_custom(rank)
	second.sort_custom(rank)
	for a in first:
		for b in second:
			if a.distance_to(b) > radii.x + radii.y:
				result.append(a)
				result.append(b)
				return result
	return result
