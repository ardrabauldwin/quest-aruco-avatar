extends Node3D
## Debug overlay: an axis gizmo (marker_pose_gizmo.gd) at every raw detected marker pose, before
## layout fusion or patient offsets. Switched on from the hand menu's Debug row.
## Works on any provider with the tracker's API (markers_updated, get_marker_world_pose,
## marker_age_ms); one gizmo per id, created on that id's first detection.

const MarkerPoseGizmo = preload("res://scripts/tracking/marker_pose_gizmo.gd")
## Same grace period as the tracker: older than this, a gizmo would only show a stale pose.
const FRESHNESS_MS := 500.0

var _provider: Node
var _gizmos := {}   # id -> Node3D

func bind(provider: Node) -> void:
	_provider = provider
	_provider.markers_updated.connect(_on_markers_updated)

func _on_markers_updated(ids: Array) -> void:
	for id in ids:
		var gizmo: Node3D = _gizmos.get(id)
		if gizmo == null:
			gizmo = Node3D.new()
			gizmo.name = "MarkerGizmo%d" % id
			gizmo.top_level = true    # the provider's poses are world space
			add_child(gizmo)
			MarkerPoseGizmo.attach_to(gizmo, id)
			_gizmos[id] = gizmo
		gizmo.global_transform = _provider.get_marker_world_pose(id)

func _process(_delta: float) -> void:
	if _provider == null:
		return
	for id in _gizmos:
		_gizmos[id].visible = float(_provider.marker_age_ms(id)) <= FRESHNESS_MS
