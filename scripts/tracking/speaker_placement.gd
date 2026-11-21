extends RefCounted
## Conservative circles enclose the supplied bodies. Geometry is room-space XZ.
## Guarantees concern the supplied scan, not unscanned physical objects.

static func valid(point: Vector2, radius: float, floor: PackedVector2Array, obstacles: Array, eye: Vector2, forward: Vector2, bounds: PackedVector2Array = PackedVector2Array()) -> bool:
	if not point.is_finite() or not eye.is_finite() or not forward.is_finite(): return false
	if bounds.size() >= 3 and not valid(point, maxf(radius, NaretRoomLayout.WALL_CLEARANCE), bounds, [], eye, forward): return false
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


static func pair(floor: PackedVector2Array, obstacles: Array, patient: Vector2, radii: Vector2, eye: Vector2, forward: Vector2, bounds: PackedVector2Array = PackedVector2Array()) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var first: Array[Vector2] = []
	var second: Array[Vector2] = []
	for point in NaretRoomLayout._candidates(floor, patient) if floor.size() >= 3 else []:
		if valid(point, radii.x, floor, obstacles, eye, forward, bounds): first.append(point)
		if valid(point, radii.y, floor, obstacles, eye, forward, bounds): second.append(point)
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

## Pull a default (patient-relative) spot inside the play-area outline: at least `margin`
## from its edges, at least `keep_away_m` from `keep_away` (the lying patient) and
## `separation_m` from the `placed` spots where the outline allows it. Priority in a tiny
## room: inside the outline, then off the patient, then apart from the others. Without a
## usable outline, or one smaller than the margin, the spot is returned unchanged.
static func inside_outline(point: Vector2, outline: PackedVector2Array, margin: float, keep_away: Vector2,
		keep_away_m: float, placed: Array = [], separation_m: float = 0.0) -> Vector2:
	if outline.size() < 3 or not point.is_finite() or not is_finite(margin): return point
	var polygon := PackedVector2Array()
	var nearest := INF
	for candidate: PackedVector2Array in Geometry2D.offset_polygon(outline, -margin):
		if candidate.size() < 3: continue
		if Geometry2D.is_point_in_polygon(point, candidate):
			polygon = candidate
			break
		var distance := point.distance_to(closest_on_outline(candidate, point))
		if distance < nearest:
			nearest = distance
			polygon = candidate
	if polygon.size() < 3: return point
	var acceptable := func(p: Vector2, check_separation: bool) -> bool:
		if keep_away_m > 0.0 and p.distance_to(keep_away) < keep_away_m: return false
		if check_separation:
			for other: Vector2 in placed:
				if p.distance_to(other) < separation_m: return false
		return true
	var inside := point if Geometry2D.is_point_in_polygon(point, polygon) else closest_on_outline(polygon, point)
	if acceptable.call(inside, true): return inside
	# Walk the inset outline in 10 cm steps; the nearest acceptable spot wins.
	var best_full := Vector2(INF, INF)
	var best_part := Vector2(INF, INF)
	var full_distance := INF
	var part_distance := INF
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var steps := maxi(1, int(ceil(a.distance_to(b) / 0.1)))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			var distance := p.distance_to(inside)
			if acceptable.call(p, true):
				if distance < full_distance:
					full_distance = distance
					best_full = p
			elif acceptable.call(p, false) and distance < part_distance:
				part_distance = distance
				best_part = p
	if best_full.is_finite(): return best_full
	if best_part.is_finite(): return best_part
	return inside

static func closest_on_outline(polygon: PackedVector2Array, point: Vector2) -> Vector2:
	var best := point
	var nearest := INF
	for i in polygon.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
		var distance := point.distance_to(candidate)
		if distance < nearest:
			nearest = distance
			best = candidate
	return best

static func play_area_outline(points: PackedVector3Array, origin: Transform3D) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if points.size() < 3 or not origin.is_finite(): return outline
	for point in points:
		if not point.is_finite(): return PackedVector2Array()
		var world := origin * point
		var flat := Vector2(world.x, world.z)
		if outline.has(flat): return PackedVector2Array()
		outline.append(flat)
	if absf(NaretRoomLayout._polygon_area(outline)) < 0.001 or Geometry2D.triangulate_polygon(outline).is_empty():
		return PackedVector2Array()
	return outline


static func independent_spots(options: Array, radii: Array) -> Dictionary:
	# Plan independent spots together: the first actor must not consume the only
	# space that would let a second actor fit. Inputs already pass geometry gates.
	if options.size() != 3 or radii.size() != 3: return {}
	for a: Vector2 in options[0]:
		for b: Vector2 in options[1]:
			if a.distance_to(b) <= radii[0] + radii[1]: continue
			for c: Vector2 in options[2]:
				if a.distance_to(c) > radii[0] + radii[2] and b.distance_to(c) > radii[1] + radii[2]:
					return {0:a, 1:b, 2:c}
	# Prefer the two speakers already needed before AED delivery.
	for pair_indices in [[0,1], [0,2], [1,2]]:
		var i: int = pair_indices[0]
		var j: int = pair_indices[1]
		for a: Vector2 in options[i]:
			for b: Vector2 in options[j]:
				if a.distance_to(b) > radii[i] + radii[j]: return {i:a, j:b}
	for i in options.size():
		if not options[i].is_empty(): return {i:options[i][0]}
	return {}


static func boundary_candidates(floor: PackedVector2Array, obstacles: Array, radius: float) -> Array[Vector2]:
	# Configuration-space edges expose narrow valid pockets missed by a 25 cm
	# grid. The epsilon only keeps candidates off strict geometric boundaries.
	var result: Array[Vector2] = []
	if floor.size() < 3 or not is_finite(radius) or radius <= 0.0: return result
	const EDGE_EPSILON_M := 0.0001
	var regions: Array = Geometry2D.offset_polygon(floor, -radius - EDGE_EPSILON_M)
	for obstacle: Rect2 in obstacles:
		var grown := obstacle.grow(radius + EDGE_EPSILON_M)
		var cut := PackedVector2Array([grown.position, Vector2(grown.end.x,grown.position.y), grown.end, Vector2(grown.position.x,grown.end.y)])
		var remaining: Array = []
		for region: PackedVector2Array in regions:
			remaining.append_array(Geometry2D.clip_polygons(region, cut))
		regions = remaining
	for region: PackedVector2Array in regions:
		for i in region.size():
			result.append(region[i])
			result.append((region[i]+region[(i+1)%region.size()])*0.5)
		var triangles := Geometry2D.triangulate_polygon(region)
		for i in range(0,triangles.size(),3):
			result.append((region[triangles[i]]+region[triangles[i+1]]+region[triangles[i+2]])/3.0)
	return result
