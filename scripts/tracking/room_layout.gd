class_name NaretRoomLayout
extends Node
## Read saved room geometry first. System capture runs only after an explicit request.
signal layout_ready(status: String)

const OBSTACLES := ["couch", "table", "bed", "screen", "storage", "lamp", "plant",
	"other", "wall", "wall_face", "wall_art", "window_frame", "door_frame"]
const WALL_CLEARANCE := 0.30
const OBSTACLE_CLEARANCE := 0.25
const SPOT_SEPARATION := 0.6
const RADII := [1.8, 2.2, 1.5, 2.6, 1.2, 0.9]
const STAND_CLEARANCE_M := 0.25
const SCORE_CLEARANCE_CAP_M := 0.6
const PREFERRED_DISTANCE_M := 1.5
const MIN_SCORED_SEPARATION_M := 0.4
const SCAN_RETRY_SECONDS := 5.0
const SCAN_WAIT_SECONDS := 120.0
## Reject a saved floor from another storey; this never changes the patient's floor.
const ROOM_FLOOR_TOLERANCE_M := 0.30

var available := false
var floor_y := 0.0
var _manager: Node
var _entries: Array[Dictionary] = []
var _scan_attempts := 0
var _capture_poll_s := 0.0
var _retry_elapsed_s := 0.0
var _retry_next_s := SCAN_RETRY_SECONDS
var _waiting := false
var _focused := true
var _capture_in_progress := false
var _viewer: Node3D
var _origin: XROrigin3D

func configure(origin: XROrigin3D, viewer: Node3D = null) -> void:
	_origin = origin
	_viewer = viewer
	if origin == null or not ClassDB.class_exists("OpenXRFbSceneManager"):
		layout_ready.emit("room_scan_unsupported")
		return
	_manager = ClassDB.instantiate("OpenXRFbSceneManager")
	_manager.name = "RoomScan"
	_manager.set("visible", false)
	_manager.set("auto_create", false)
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
	if XRServer.has_signal("reference_frame_changed"):
		XRServer.reference_frame_changed.connect(_on_reference_frame_changed)
	retry_scan.call_deferred()

func _on_reference_frame_changed() -> void:
	if _focused and not _capture_in_progress: retry_scan()

func set_session_focused(focused: bool) -> void:
	_focused = focused
	if focused and not _capture_in_progress:
		retry_scan()

func retry_scan() -> void:
	if _manager == null:
		layout_ready.emit("room_scan_unsupported")
		return
	if _capture_in_progress: return
	# A resumed session may be in another room. Rebuild geometry rather than
	# assuming that anchors retained from the last location still describe it.
	if bool(_manager.call("are_scene_anchors_created")):
		_manager.call("remove_scene_anchors")
	_entries.clear()
	available = false
	_scan_attempts = 0
	_retry_elapsed_s = 0.0
	_retry_next_s = SCAN_RETRY_SECONDS
	_waiting = true
	layout_ready.emit("room_scan_waiting")
	if _focused: _query_scene()

func _query_scene() -> void:
	if _manager == null or not _focused: return
	_scan_attempts += 1
	var result: int = _manager.call("create_scene_anchors")
	print("NARET_ROOM query_result=", result, " attempt=", _scan_attempts, " anchors=", anchor_count())
	# Schedule independently of callbacks: OK means accepted, not that anchors exist.
	_retry_next_s = _retry_elapsed_s + SCAN_RETRY_SECONDS

func _on_anchor_created(scene_node: Object, entity: Object) -> void:
	if not is_instance_valid(scene_node) or not scene_node is Node3D: return
	for entry in _entries:
		if entry.node == scene_node: return
	var labels: PackedStringArray = entity.call("get_semantic_labels")
	var label := ""
	for semantic in labels:
		var value := semantic.to_lower()
		if value == "floor" or label.is_empty(): label = value
	_entries.append({"node": scene_node, "entity": entity, "label": label})
	print("NARET_ROOM anchor_labels=", labels, " anchors=", anchor_count())
	_refresh_available()

func anchor_count() -> int:
	return _entries.size()

func _entry_outline(entry: Dictionary) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if not is_instance_valid(entry.node) or not is_instance_valid(entry.entity): return outline
	var node := entry.node as Node3D
	var tracking_node := node if node is XRNode3D else node.get_parent()
	if tracking_node is XRNode3D and not tracking_node.get_has_tracking_data(): return outline
	if not node.global_transform.is_finite(): return outline
	var boundary: PackedVector2Array = entry.entity.call("get_boundary_2d")
	for point in boundary:
		var world := node.global_transform * Vector3(point.x, point.y, 0.0)
		if not world.is_finite(): return PackedVector2Array()
		outline.append(Vector2(world.x, world.z))
	return outline

func outline_for(viewer: Vector3, patient: Vector3, expected_floor_y: float) -> PackedVector2Array:
	# Several saved rooms may be returned. Select one containing the current
	# wearer and patient on this floor, not simply the first FLOOR callback.
	for entry in _entries:
		if entry.label != "floor" or not is_instance_valid(entry.node): continue
		var node := entry.node as Node3D
		if is_finite(expected_floor_y) and absf(node.global_position.y - expected_floor_y) > ROOM_FLOOR_TOLERANCE_M: continue
		var outline := _entry_outline(entry)
		if outline.size() < 3 or absf(_polygon_area(outline)) < 0.001: continue
		if viewer.is_finite() and not Geometry2D.is_point_in_polygon(Vector2(viewer.x, viewer.z), outline): continue
		if patient.is_finite() and not Geometry2D.is_point_in_polygon(Vector2(patient.x, patient.z), outline): continue
		return outline
	return PackedVector2Array()

static func _polygon_area(outline: PackedVector2Array) -> float:
	var area := 0.0
	for i in outline.size(): area += outline[i].cross(outline[(i + 1) % outline.size()])
	return area * 0.5

func _reference_floor_y() -> float:
	return (_origin.global_transform * XRServer.get_reference_frame()).origin.y if is_instance_valid(_origin) else NAN

func _viewer_position() -> Vector3:
	return _viewer.global_position if is_instance_valid(_viewer) else Vector3(NAN, NAN, NAN)

func _refresh_available() -> void:
	var outline := outline_for(_viewer_position(), Vector3(NAN, NAN, NAN), _reference_floor_y())
	var was_available := available
	available = outline.size() >= 3
	if available:
		_waiting = false
		floor_y = floor_height_world()
		if not was_available: layout_ready.emit("room_scan_ready")
	elif was_available:
		# Tracking or room matching was lost. Start another bounded query window.
		_waiting = true
		_retry_elapsed_s = 0.0
		_retry_next_s = SCAN_RETRY_SECONDS
		layout_ready.emit("room_scan_waiting")

func floor_height_world() -> float:
	var viewer := _viewer_position()
	var outline := outline_for(viewer, Vector3(NAN, NAN, NAN), _reference_floor_y())
	if outline.is_empty(): return NAN
	for entry in _entries:
		if entry.label == "floor" and _entry_outline(entry) == outline:
			return (entry.node as Node3D).global_position.y
	return NAN

func floor_outline() -> PackedVector2Array:
	return outline_for(_viewer_position(), Vector3(NAN, NAN, NAN), _reference_floor_y())

func _on_scene_data_missing() -> void:
	print("NARET_ROOM empty_result anchors=", anchor_count())
	# _process drives retries even when the native API sends no such signal.

func request_capture() -> bool:
	if _manager == null or not bool(_manager.call("is_scene_capture_supported")):
		layout_ready.emit("room_scan_unsupported")
		return false
	if _capture_in_progress: return false
	_capture_in_progress = bool(_manager.call("request_scene_capture", ""))
	if _capture_in_progress:
		_waiting = false
		layout_ready.emit("room_scan_capturing")
	else: layout_ready.emit("room_scan_missing")
	print("NARET_ROOM capture_requested=", _capture_in_progress)
	return _capture_in_progress

func _on_capture_completed(success: bool) -> void:
	_capture_in_progress = false
	print("NARET_ROOM capture_completed=", success)
	if success: retry_scan()
	else: layout_ready.emit("room_scan_missing")

func _advance_queries(delta: float) -> void:
	if not _focused or not _waiting or _manager == null: return
	_retry_elapsed_s += delta
	if _retry_elapsed_s >= SCAN_WAIT_SECONDS:
		_waiting = false
		layout_ready.emit("room_scan_missing")
	elif _retry_elapsed_s >= _retry_next_s:
		_query_scene()

func _process(delta: float) -> void:
	_advance_queries(delta)
	_capture_poll_s += delta
	if _capture_poll_s < 1.0: return
	_capture_poll_s = 0.0
	_refresh_available()
	# Existing developer trigger remains explicit; never auto-open system setup.
	if FileAccess.file_exists("user://room_capture.request"):
		DirAccess.remove_absolute("user://room_capture.request")
		request_capture()

func obstacle_footprints() -> Array:
	## Axis-aligned world X/Z rectangles for everything a person cannot stand in.
	var result: Array = []
	for entry in _entries:
		if not is_instance_valid(entry.node) or not is_instance_valid(entry.entity): continue
		if entry.node is XRNode3D and not entry.node.get_has_tracking_data(): continue
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


