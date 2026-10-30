class_name NaretRoomLayout
extends Node
## Places bystanders on real, free floor from the headset's room scan.
## Headset speakers remain hidden without free scanned floor. Training still runs
## using audio, and the scan is read only — nothing is written back.

signal layout_ready(status: String)

## Meta scene labels that a person cannot stand on or inside.
const OBSTACLES := ["couch", "table", "bed", "screen", "storage", "lamp", "plant",
	"other", "wall", "wall_face", "wall_art", "window_frame", "door_frame"]
## Reduced 2026-10-29 from 0.45 / 0.35 / 0.9 m: with those the strict search needed
## roughly 3 x 3.5 m of free floor. People do stand near walls; a shoulder sits
## about 0.25 m from the body centre.
const WALL_CLEARANCE := 0.30
const OBSTACLE_CLEARANCE := 0.25
const SPOT_SEPARATION := 0.6
## Tried in order: a comfortable distance first, closer only if the room forces it.
## The trainee needs kneeling room beside the patient that a bystander must not take.
const RADII := [1.8, 2.2, 1.5, 2.6, 1.2, 0.9]
## Scored fallback (score_spots) for rooms where the strict search finds nothing.
## A spot's clearance is the distance from its centre to the nearest wall or object.
## A standing body is ~0.5 m across the shoulders and needs half of that; with less
## the character would stand inside the wall, so it stays hidden. Body size, not tuning.
const STAND_CLEARANCE_M := 0.25
## Clearance beyond this earns no extra score; distance to the patient decides.
const SCORE_CLEARANCE_CAP_M := 0.6
const PREFERRED_DISTANCE_M := 1.5
const MIN_SCORED_SEPARATION_M := 0.4
## An idle headset answers the layout query before it has localised into its room.
const SCAN_RETRIES := 6
const SCAN_RETRY_SECONDS := 5.0

var available := false
var floor_y := 0.0
var _manager: Node
var _entries: Array[Dictionary] = []
var _scan_attempts := 0
var _next_retry_ms := 0
var _capture_poll_s := 0.0

func configure(origin: XROrigin3D) -> void:
	if origin == null or not ClassDB.class_exists("OpenXRFbSceneManager"):
		layout_ready.emit("room_scan_unsupported")
		return
	_manager = ClassDB.instantiate("OpenXRFbSceneManager")
	_manager.name = "RoomScan"
	# Anchors are only queried for geometry; drawing the room over passthrough
	# would hide the real room the trainee is standing in.
	_manager.set("visible", false)
	_manager.set("auto_create", false)
	# Entities without a scene are silently skipped, so every anchor gets a bare
	# pose holder; the geometry is read from the entity, not from this node.
	var holder := Node3D.new()
	holder.set_script(load("res://scripts/tracking/room_anchor.gd"))
	var packed := PackedScene.new()
	packed.pack(holder)
	holder.free()
	_manager.set("default_scene", packed)
	_manager.connect("openxr_fb_scene_anchor_created", _on_anchor_created)
	_manager.connect("openxr_fb_scene_data_missing", _on_scene_data_missing)
	_manager.connect("openxr_fb_scene_capture_completed", _on_capture_completed)
	origin.add_child(_manager)
	# Main creates this manager after XR initialization. Query explicitly;
	# auto_create listens for a session-start signal that may already have fired.
	_query_scene.call_deferred()

func _query_scene() -> void:
	if _manager == null:
		return
	var result: int = _manager.call("create_scene_anchors")
	print("NARET_ROOM query_result=", result)
	if result != OK:
		_on_scene_data_missing()

func _on_anchor_created(scene_node: Object, entity: Object) -> void:
	var labels: PackedStringArray = entity.call("get_semantic_labels")
	var label := String(labels[0]).to_lower() if labels.size() > 0 else ""
	_entries.append({"node": scene_node, "entity": entity, "label": label})
	if label == "floor":
		available = true
		_scan_attempts = 0
		floor_y = (scene_node as Node3D).global_position.y
		layout_ready.emit("room_scan_ready")

func anchor_count() -> int:
	return _entries.size()

func floor_height_world() -> float:
	# Scene anchors can be refined or recentered after the initial callback.
	# Read the current node transform instead of the height cached on creation.
	for entry in _entries:
		if entry.label == "floor" and is_instance_valid(entry.node):
			var node := entry.node as Node3D
			if node is XRNode3D and not node.get_has_tracking_data():
				continue
			return node.global_position.y
	return NAN

func _on_scene_data_missing() -> void:
	## An empty answer usually means the headset has not localised into its room yet
	## rather than that the room is unscanned, so keep asking for a while. NaReT
	## deliberately never starts the system room capture: pulling a trainee out of a
	## running resuscitation is worse than the authored fallback layout.
	var now := Time.get_ticks_msec()
	if now < _next_retry_ms:
		return # The manager repeats this signal per query; retry once per round.
	_next_retry_ms = now + int(SCAN_RETRY_SECONDS * 1000.0)
	_scan_attempts += 1
	if _scan_attempts > SCAN_RETRIES:
		layout_ready.emit("room_scan_missing")
		return
	if _scan_attempts == 1:
		layout_ready.emit("room_scan_waiting")
	await get_tree().create_timer(SCAN_RETRY_SECONDS).timeout
	if available or _manager == null:
		return
	_query_scene()

func floor_outline() -> PackedVector2Array:
	## Room outline on the ground plane, in world X/Z metres.
	for entry in _entries:
		if entry.label != "floor":
			continue
		var node: Node3D = entry.node
		var boundary: PackedVector2Array = entry.entity.call("get_boundary_2d")
		var outline := PackedVector2Array()
		for point in boundary:
			var world := node.global_transform * Vector3(point.x, point.y, 0.0)
			outline.append(Vector2(world.x, world.z))
		return outline
	return PackedVector2Array()

func obstacle_footprints() -> Array:
	## Axis-aligned world X/Z rectangles for everything a person cannot stand in.
	var result: Array = []
	for entry in _entries:
		if not OBSTACLES.has(entry.label):
			continue
		var node: Node3D = entry.node
		var box: AABB = entry.entity.call("get_bounding_box_3d")
		if not box.has_volume():
			# Walls are planes, so their 3D bounding box may have zero thickness.
			var boundary: PackedVector2Array = entry.entity.call("get_boundary_2d")
			if boundary.is_empty():
				continue
			var wall_min := Vector2(INF, INF)
			var wall_max := Vector2(-INF, -INF)
			for point in boundary:
				var world := node.global_transform * Vector3(point.x, point.y, 0.0)
				wall_min = wall_min.min(Vector2(world.x, world.z))
				wall_max = wall_max.max(Vector2(world.x, world.z))
			result.append(Rect2(wall_min, wall_max - wall_min))
			continue
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for corner in range(8):
			var world := node.global_transform * box.get_endpoint(corner)
			minimum = minimum.min(Vector2(world.x, world.z))
			maximum = maximum.max(Vector2(world.x, world.z))
		result.append(Rect2(minimum, maximum - minimum))
	return result

func find_spots(center: Vector3, count: int, keep_clear: Array = [], clearance: float = WALL_CLEARANCE, allowed_outline: PackedVector2Array = PackedVector2Array()) -> Array[Transform3D]:
	## World transforms for `count` bystanders standing on free floor, facing `center`.
	## `keep_clear` adds world X/Z rectangles the room scan cannot know about, such
	## as the floor the patient is lying on.
	var spots: Array[Transform3D] = []
	if not available:
		return spots
	var blockers := obstacle_footprints()
	blockers.append_array(keep_clear)
	var height := floor_height_world()
	if not is_finite(height):
		return spots
	var flat := pick_spots(floor_outline(), blockers, Vector2(center.x, center.z), count, clearance, allowed_outline)
	for point in flat:
		spots.append(_facing_transform(point, height, center))
	return spots

func find_spots_scored(center: Vector3, count: int, keep_clear: Array = [], allowed_outline: PackedVector2Array = PackedVector2Array()) -> Array[Dictionary]:
	## find_spots with the soft rules of score_spots, for rooms where the strict
	## search fails. Each entry: "transform", "clearance_m".
	var result: Array[Dictionary] = []
	if not available:
		return result
	var blockers := obstacle_footprints()
	blockers.append_array(keep_clear)
	var height := floor_height_world()
	if not is_finite(height):
		return result
	for item in score_spots(floor_outline(), blockers, Vector2(center.x, center.z), count, allowed_outline):
		result.append({"transform": _facing_transform(item.position, height, center), "clearance_m": item.clearance_m})
	return result

static func _facing_transform(point: Vector2, height: float, center: Vector3) -> Transform3D:
	var position := Vector3(point.x, height, point.y)
	var facing := Vector3(center.x - point.x, 0.0, center.z - point.y)
	if facing.length_squared() < 0.0001:
		facing = Vector3.BACK
	# The characters model facing +Z, while looking_at aims -Z at its target.
	return Transform3D(Basis.looking_at(-facing, Vector3.UP), position)

static func pick_spots(outline: PackedVector2Array, obstacles: Array, center: Vector2, count: int, clearance: float = WALL_CLEARANCE, allowed_outline: PackedVector2Array = PackedVector2Array(), body_scale: float = 1.0) -> Array[Vector2]:
	## Pure geometry so the placement rules stay testable without a headset.
	var chosen: Array[Vector2] = []
	if outline.size() < 3 or count <= 0:
		return chosen
	# Inset keeps a standing person off the walls; a narrow room can inset to nothing.
	var regions := Geometry2D.offset_polygon(outline, -maxf(clearance, WALL_CLEARANCE * body_scale))
	if regions.is_empty():
		return chosen
	var allowed_regions: Array = []
	if allowed_outline.size() >= 3:
		allowed_regions = Geometry2D.offset_polygon(allowed_outline, -maxf(clearance, WALL_CLEARANCE * body_scale))
		if allowed_regions.is_empty():
			return chosen
	var blocked: Array[Rect2] = []
	for item: Rect2 in obstacles:
		blocked.append(item.grow(maxf(clearance, OBSTACLE_CLEARANCE * body_scale)))
	for candidate in _candidates(outline, center):
		if chosen.size() >= count:
			return chosen
		if not _inside(regions, candidate):
			continue
		if not allowed_regions.is_empty() and not _inside(allowed_regions, candidate):
			continue
		if blocked.any(func(rect: Rect2) -> bool: return rect.has_point(candidate)):
			continue
		if chosen.any(func(other: Vector2) -> bool: return other.distance_to(candidate) < maxf(SPOT_SEPARATION * body_scale, 2.0 * clearance)):
			continue
		chosen.append(candidate)
	return chosen

static func _candidates(outline: PackedVector2Array, center: Vector2) -> Array[Vector2]:
	## Rings around the patient first (preferred distance first), then a 25 cm grid.
	## Ring-only sampling missed usable corners and smaller rooms.
	var candidates: Array[Vector2] = []
	for radius: float in RADII:
		for step in range(24):
			var angle := TAU * float(step) / 24.0
			candidates.append(center + Vector2(cos(angle), sin(angle)) * radius)
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		bounds = bounds.expand(point)
	for ix in mini(int(ceil(bounds.size.x / 0.25)) + 1, 128):
		for iz in mini(int(ceil(bounds.size.y / 0.25)) + 1, 128):
			candidates.append(bounds.position + Vector2(ix, iz) * 0.25)
	return candidates

static func score_spots(outline: PackedVector2Array, obstacles: Array, center: Vector2, count: int, allowed_outline: PackedVector2Array = PackedVector2Array()) -> Array[Dictionary]:
	## Soft version of pick_spots: never empty while any floor is left. Hard rules
	## stay hard (on the floor, never inside the patient, trainee or furniture
	## rectangles); wall/object clearance and distance to the patient become a score.
	## Entries: "position" (Vector2), "clearance_m". A spot with less than the standing
	## clearance is unusable: nobody is placed half inside a wall. Pure geometry.
	var chosen: Array[Dictionary] = []
	if outline.size() < 3 or count <= 0:
		return chosen
	var scored: Array[Dictionary] = []
	for candidate in _candidates(outline, center):
		if not Geometry2D.is_point_in_polygon(candidate, outline):
			continue
		if allowed_outline.size() >= 3 and not Geometry2D.is_point_in_polygon(candidate, allowed_outline):
			continue
		if obstacles.any(func(rect: Rect2) -> bool: return rect.has_point(candidate)):
			continue
		var clearance := _distance_to_outline(outline, candidate)
		if allowed_outline.size() >= 3:
			clearance = minf(clearance, _distance_to_outline(allowed_outline, candidate))
		for rect: Rect2 in obstacles:
			clearance = minf(clearance, _distance_to_rect(rect, candidate))
		if clearance < STAND_CLEARANCE_M:
			continue
		# More room than the cap buys nothing; being near the preferred distance does.
		var score := minf(clearance, SCORE_CLEARANCE_CAP_M) - 0.5 * absf(candidate.distance_to(center) - PREFERRED_DISTANCE_M)
		scored.append({"position": candidate, "clearance_m": clearance, "score": score})
	for _slot in count:
		var best: Dictionary = {}
		var best_score := -INF
		for item in scored:
			var score: float = item.score
			var too_close := false
			for other in chosen:
				var distance: float = (item.position as Vector2).distance_to(other.position)
				too_close = too_close or distance < MIN_SCORED_SEPARATION_M
				score -= 0.5 * maxf(0.0, SPOT_SEPARATION - distance)
			if too_close or score <= best_score:
				continue
			best_score = score
			best = item
		if best.is_empty():
			break
		chosen.append({"position": best.position, "clearance_m": best.clearance_m})
	return chosen

static func _distance_to_outline(outline: PackedVector2Array, point: Vector2) -> float:
	var best := INF
	for i in outline.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, outline[i], outline[(i + 1) % outline.size()])
		best = minf(best, point.distance_to(closest))
	return best

static func _distance_to_rect(rect: Rect2, point: Vector2) -> float:
	## Distance from a point outside the rectangle to its edge; 0 inside.
	var dx := maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0)
	var dy := maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)
	return Vector2(dx, dy).length()

static func _inside(regions: Array, point: Vector2) -> bool:
	for region: PackedVector2Array in regions:
		if Geometry2D.is_point_in_polygon(point, region):
			return true
	return false

func _process(delta: float) -> void:
	_capture_poll_s += delta
	if _capture_poll_s < 1.0 or _manager == null:
		return
	_capture_poll_s = 0.0
	# A one-shot diagnostic request opens native setup only when explicitly asked.
	if not FileAccess.file_exists("user://room_capture.request"):
		return
	DirAccess.remove_absolute("user://room_capture.request")
	if not bool(_manager.call("is_scene_capture_supported")):
		layout_ready.emit("room_scan_unsupported")
		return
	var started: bool = _manager.call("request_scene_capture", "")
	print("NARET_ROOM capture_requested=", started)

func _on_capture_completed(success: bool) -> void:
	print("NARET_ROOM capture_completed=", success)
	if not success:
		layout_ready.emit("room_scan_missing")
		return
	# Old anchors refer to the previous scan; replace them after native setup.
	_manager.call("remove_scene_anchors")
	_entries.clear()
	available = false
	_scan_attempts = 0
	_next_retry_ms = 0
	_query_scene()
