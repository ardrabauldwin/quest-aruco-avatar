extends RefCounted
## Foot-end exception only. Region geometry comes from the accepted rendered
## patient, never the incoming candidate. No accuracy claim follows from location.
const Checkpoint = preload("res://scripts/tracking/checkpoint_motion_gate.gd")
var checkpoint = Checkpoint.new()
var in_region := false
var eligible := false
var state := "outside"
var _visit := {}
var _patient: Node3D
var _skeleton: Skeleton3D
var _feet: Array[int] = []

func _init() -> void:
	# The finite XZ standing region replaces the 3D head-to-anchor range here.
	checkpoint.max_range_m = INF

func geometry(patient: Node3D) -> Dictionary:
	if not is_instance_valid(patient): return {}
	if patient != _patient or not is_instance_valid(_skeleton):
		_patient = patient
		_skeleton = null
		_feet.clear()
		var model := patient.get_node_or_null("Model")
		if model == null: return {}
		var found := model.find_children("*", "Skeleton3D", true, false)
		if found.is_empty(): return {}
		_skeleton = found[0] as Skeleton3D
		for name in ["foot_l", "foot_r"]:
			var index := _skeleton.find_bone(name)
			if index < 0:
				_feet.clear()
				return {}
			_feet.append(index)
	if _feet.size() != 2: return {}
	var sternum := patient.get_node_or_null("Sternum") as Node3D
	if sternum == null: return {}
	var foot := Vector3.ZERO
	for index in _feet:
		# Rest landmarks avoid moving the region with leg animation.
		foot += _skeleton.global_transform * _skeleton.get_bone_global_rest(index).origin
	foot *= 0.5
	var along := Vector2(foot.x - sternum.global_position.x, foot.z - sternum.global_position.z)
	if not foot.is_finite() or not along.is_finite() or along.length_squared() < 0.000001: return {}
	return {"foot": Vector2(foot.x, foot.z), "along": along.normalized()}

static func contains(head_position: Vector3, region: Dictionary, half_width: float, depth: float) -> bool:
	if region.is_empty() or not head_position.is_finite() or not is_finite(half_width) or not is_finite(depth) or half_width <= 0.0 or depth <= 0.0: return false
	var along: Vector2 = region.along
	var displacement := Vector2(head_position.x, head_position.z) - (region.foot as Vector2)
	var beyond := displacement.dot(along)
	var side := absf(displacement.dot(Vector2(along.y, -along.x)))
	return beyond >= 0.0 and beyond <= depth and side <= half_width

func tick(delta: float, head: Node3D, patient: Node3D, full: bool, half_width: float, depth: float) -> void:
	checkpoint.head = head
	checkpoint.tick(delta)
	var region := _visit if not _visit.is_empty() else geometry(patient)
	var inside := contains(head.global_position, region, half_width, depth)
	if inside and not in_region:
		_visit = region.duplicate()
		checkpoint._clear_candidate()
	if not inside:
		_visit.clear()
	in_region = inside
	eligible = inside and full and not checkpoint.moving
	if not eligible: checkpoint._clear_candidate()
	state = "outside" if not inside else ("hold_partial" if not full else ("hold_moving" if checkpoint.moving else "collecting"))

func evaluate(raw: Transform3D, display: Transform3D, ms: int, full: bool) -> Dictionary:
	if not in_region or not eligible or not full:
		checkpoint._clear_candidate()
		return {}
	var result: Dictionary = checkpoint.evaluate(raw, display, ms, full)
	state = "confirmed" if not result.is_empty() else checkpoint.gate_state
	return result

func reset() -> void:
	checkpoint = Checkpoint.new()
	checkpoint.max_range_m = INF
	in_region = false
	eligible = false
	state = "outside"
	_visit.clear()
