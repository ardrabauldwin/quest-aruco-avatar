extends Node3D
## Debug overlay: an axis gizmo (marker_pose_gizmo.gd) at every raw detected marker pose, before
## layout fusion or patient offsets. Switched on from the hand menu's Debug row.
## Works on any provider with the tracker's API (markers_updated, get_marker_world_pose,
## marker_age_ms); one gizmo per id, created once that id is confirmed.
## DICT_4X4_50 is small enough that room texture produces false detections, so only the
## layout's ids are shown, and only poses repeated CONFIRM_SIGHTINGS times in a row count.

const MarkerPoseGizmo = preload("res://scripts/tracking/marker_pose_gizmo.gd")
## Same grace period as the tracker. Older gizmos stay at their last pose, labelled as lost:
## the mannequin does not move, and a gizmo that vanished could not be judged at all.
const FRESHNESS_MS := 500.0
const CONFIRM_SIGHTINGS := 3
const CONFIRM_RADIUS_M := 0.05

var _provider: Node
var _gizmos := {}   # id -> Node3D
var _allowed_ids: Array = []   # empty: every id
var _sightings := {}   # id -> {origin, count}
var _confirmed_ms := {}   # id -> ticks of the last confirmed pose

func bind(provider: Node, allowed_ids: Array = []) -> void:
	_provider = provider
	_allowed_ids = allowed_ids
	_provider.markers_updated.connect(_on_markers_updated)

func show_fused(pose: Transform3D) -> void:
	## The tracker's fused point, the spot the patient's sternum is placed on.
	var point := get_node_or_null("FusedPoint") as Node3D
	if point == null:
		point = Node3D.new()
		point.name = "FusedPoint"
		point.top_level = true
		add_child(point)
		MarkerPoseGizmo.attach_fused(point)
		print("NARET_GIZMO fused pos=", pose.origin)
	point.global_transform = pose

func _on_markers_updated(ids: Array) -> void:
	for id in ids:
		if not _allowed_ids.is_empty() and id not in _allowed_ids:
			continue
		var pose: Transform3D = _provider.get_marker_world_pose(id)
		var sighting: Dictionary = _sightings.get(id, {})
		var repeated: bool = not sighting.is_empty() and pose.origin.distance_to(sighting.origin) <= CONFIRM_RADIUS_M
		var count: int = sighting.count + 1 if repeated else 1
		_sightings[id] = {"origin": pose.origin, "count": count}
		if count < CONFIRM_SIGHTINGS:
			continue
		_confirmed_ms[id] = Time.get_ticks_msec()
		var gizmo: Node3D = _gizmos.get(id)
		if gizmo == null:
			gizmo = Node3D.new()
			gizmo.name = "MarkerGizmo%d" % id
			gizmo.top_level = true    # the provider's poses are world space
			add_child(gizmo)
			MarkerPoseGizmo.attach_to(gizmo, id)
			_gizmos[id] = gizmo
			print("NARET_GIZMO confirmed id=", id, " pos=", pose.origin)
		gizmo.global_transform = pose

func _process(_delta: float) -> void:
	if _provider == null:
		return
	for id in _gizmos:
		var gizmo: Node3D = _gizmos[id]
		gizmo.visible = true
		var fresh: bool = float(_provider.marker_age_ms(id)) <= FRESHNESS_MS and Time.get_ticks_msec() - int(_confirmed_ms[id]) <= FRESHNESS_MS
		gizmo.get_node("Label").text = ("Marker %d" if fresh else "Marker %d (lost)") % id
