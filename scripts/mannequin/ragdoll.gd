class_name NaretRagdoll
extends Node
## Anatomical posing of the CPR mannequin: hinge-limited arm IK and head tilt.

const GRAB_RANGE_M := 0.22
const REACH_M := 0.52
const MAX_ELBOW_FLEX_DEG := 140.0
# Head tilt is signed: positive bends the head forward, negative tilts it back.
const MAX_HEAD_FLEXION_DEG := 35.0
const MAX_HEAD_EXTENSION_DEG := 35.0
# Closer to the ear line than this, the hand's angle around it is only noise.
const HEAD_MIN_LEVER_M := 0.03
# Midpoint of the ears on the rest mesh, in skeleton space (ears at x = ±0.085).
const EAR_LINE_POINT := Vector3(0.0, 1.615, 0.040)

const BONES := [
	"spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
	"upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r",
	"neck_01", "head",
]
# Grab candidates per part, checked in this order; a later part only wins when strictly closer.
const GRAB_PARTS := {
	"arm_l": ["hand_l", "lowerarm_l"],
	"arm_r": ["hand_r", "lowerarm_r"],
	"head": ["head", "neck_01"],
}
# A hand nearer one of these than any limb holds nothing, so reaching for the
# chest or shoulder does not catch the head or an elbow within GRAB_RANGE_M.
const UNGRABBABLE_BONES := ["spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r"]
const SPINE_BONES := ["spine_01", "spine_02", "spine_03"]

var _skeleton: Skeleton3D
var _bones: Dictionary = {}
var _home: Dictionary = {}
var _rest_quats: Dictionary = {}
var _held: Dictionary = {}
var _targets: Dictionary = {}

# Articulation states
var _head_tilt := 0.0
var _head_target_tilt := 0.0
var _head_held := false
var _head_posed := false
var _head_pivot := Vector3.ZERO
var _neck_pivot := Vector3.ZERO
var _head_rest_position := Vector3.ZERO
# Per-arm state keyed by grab part; the side suffix ("l"/"r") is part.right(1).
var _arms := {
	"arm_l": {"flexion": 0.0, "rot": Quaternion.IDENTITY, "target": Vector3.ZERO, "held": false},
	"arm_r": {"flexion": 0.0, "rot": Quaternion.IDENTITY, "target": Vector3.ZERO, "held": false},
}

var _l1 := 0.251
var _l2 := 0.256

func configure(model: Node3D) -> void:
	var found := model.find_children("*", "Skeleton3D", true, false)
	_skeleton = found[0] if not found.is_empty() else null
	if _skeleton == null or _skeleton.get_bone_count() == 0:
		return

	_bones.clear()
	_home.clear()
	_rest_quats.clear()

	for name: String in BONES:
		var idx := _skeleton.find_bone(name)
		if idx >= 0:
			_home[name] = idx
			_rest_quats[name] = _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
			# Marker object to satisfy limb_point queries and tests
			var marker := Marker3D.new()
			marker.name = "PB_" + name
			_skeleton.add_child(marker)
			_bones[name] = marker

	if _home.has("upperarm_l") and _home.has("lowerarm_l") and _home.has("hand_l"):
		var s := _skeleton.get_bone_global_rest(_home["upperarm_l"]).origin
		var e := _skeleton.get_bone_global_rest(_home["lowerarm_l"]).origin
		var w := _skeleton.get_bone_global_rest(_home["hand_l"]).origin
		_l1 = s.distance_to(e)
		_l2 = e.distance_to(w)

	if _home.has("head"):
		_head_pivot = _skeleton.get_bone_global_rest(_home["head"]).affine_inverse() * EAR_LINE_POINT
		_head_rest_position = _skeleton.get_bone_rest(_home["head"]).origin
	if _home.has("neck_01"):
		_neck_pivot = _skeleton.get_bone_global_rest(_home["neck_01"]).affine_inverse() * EAR_LINE_POINT

	reset_to_skeleton()
	process_priority = 200
	process_physics_priority = 200

func is_active() -> bool:
	return _skeleton != null and not _bones.is_empty()

func limb_count() -> int:
	return _bones.size()

func limb_point(name: String) -> Vector3:
	var idx: int = _home.get(name, -1)
	if idx >= 0 and _skeleton != null:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx).origin
	return Vector3.ZERO

func holds(id: String) -> bool:
	return _held.has(id)

func held_target(id: String) -> Vector3:
	return _targets.get(id, Vector3.ZERO)

func reset_to_skeleton() -> void:
	_held.clear()
	_targets.clear()
	_head_tilt = 0.0
	_head_target_tilt = 0.0
	_head_held = false
	_head_posed = false
	for arm: Dictionary in _arms.values():
		arm.flexion = 0.0
		arm.rot = Quaternion.IDENTITY
		arm.held = false
	if _skeleton != null:
		_skeleton.reset_bone_poses()
		_skeleton.force_update_all_bone_transforms()
		_update_bone_markers()

func grab(id: String, world_point: Vector3) -> bool:
	if not is_active():
		return false

	var best_dist := GRAB_RANGE_M
	var chosen_part := ""
	var anchor_name := ""
	for part: String in GRAB_PARTS:
		for name: String in GRAB_PARTS[part]:
			var dist := limb_point(name).distance_to(world_point)
			if dist < best_dist:
				best_dist = dist
				chosen_part = part
				anchor_name = name

	if chosen_part.is_empty():
		return false
	for name: String in UNGRABBABLE_BONES:
		if limb_point(name).distance_to(world_point) < best_dist:
			return false

	_held[id] = {"part": chosen_part, "anchor": anchor_name}
	_targets[id] = world_point

	if chosen_part == "head":
		_head_held = true
		_head_target_tilt = _head_tilt
		_held[id]["angle"] = _head_hand_angle(world_point)
	else:
		_arms[chosen_part].held = true
		_arms[chosen_part].target = world_point

	return true

func move(id: String, world_point: Vector3) -> void:
	if not _held.has(id):
		return
	var info: Dictionary = _held[id]
	var part: String = info.get("part", "")
	var anchor_name: String = info.get("anchor", "")

	# Bounded reach relative to bone rest point
	var home := _rest_point(anchor_name)
	var bounded_target := home + (world_point - home).limit_length(REACH_M)
	_targets[id] = bounded_target

	if _arms.has(part):
		var side := part.right(1)
		var target := bounded_target
		if anchor_name == "lowerarm_" + side:
			var dir := (bounded_target - limb_point("upperarm_" + side)).normalized()
			if dir.is_zero_approx():
				dir = Vector3.FORWARD
			target = bounded_target + dir * (_l2 * 0.5)
		_arms[part].target = target

	elif part == "head":
		# The head follows the hand around the ear line from wherever it was grabbed.
		var angle := _head_hand_angle(world_point)
		if is_finite(angle):
			var previous: float = info.angle
			if is_finite(previous):
				var turned := rad_to_deg(wrapf(angle - previous, -PI, PI))
				_head_target_tilt = clampf(_head_target_tilt + turned, -MAX_HEAD_EXTENSION_DEG, MAX_HEAD_FLEXION_DEG)
			info.angle = angle

func _head_hand_angle(world_point: Vector3) -> float:
	## The hand's angle around the ear line, in the plane of the tilt; NAN too close to it.
	var neck := _skeleton.global_transform * _skeleton.get_bone_global_pose(_home["neck_01"])
	var lever := neck.affine_inverse() * world_point - _neck_pivot
	if Vector2(lever.y, lever.z).length() < HEAD_MIN_LEVER_M:
		return NAN
	return atan2(lever.z, lever.y)

func release(id: String) -> void:
	if not _held.has(id):
		return
	var info: Dictionary = _held[id]
	var part: String = info.get("part", "")
	_held.erase(id)
	_targets.erase(id)

	# Check if any remaining grab holds this part
	var still_holding := false
	for other_id: String in _held:
		if _held[other_id].get("part") == part:
			still_holding = true
			break

	if not still_holding:
		if _arms.has(part):
			_arms[part].held = false
		elif part == "head":
			_head_held = false
			_head_target_tilt = 0.0

func _process(delta: float) -> void:
	if not is_active():
		return
	_update_arm_ik(delta)
	_update_head_dynamics(delta)
	_apply_to_skeleton()
	_update_bone_markers()

func _physics_process(delta: float) -> void:
	# Running in both steps guarantees fresh bone transforms for physics raycasts and frames
	_process(delta)

func _update_head_dynamics(delta: float) -> void:
	if _head_held:
		_head_tilt = move_toward(_head_tilt, _head_target_tilt, 90.0 * delta)
	else:
		_head_tilt = move_toward(_head_tilt, 0.0, 45.0 * delta)

func _update_arm_ik(delta: float) -> void:
	for part: String in _arms:
		var arm: Dictionary = _arms[part]
		var rot: Quaternion = arm.rot
		if arm.held and arm.target != Vector3.ZERO:
			var side := part.right(1)
			var ik := _solve_2bone_ik(limb_point("upperarm_" + side), arm.target, side)
			arm.rot = rot.slerp(ik.shoulder_rot, clampf(18.0 * delta, 0.0, 1.0))
			arm.flexion = move_toward(arm.flexion, ik.elbow_flexion, deg_to_rad(240.0) * delta)
		else:
			# Smooth return to anatomical rest beside body
			arm.rot = rot.slerp(Quaternion.IDENTITY, clampf(7.0 * delta, 0.0, 1.0))
			arm.flexion = move_toward(arm.flexion, 0.0, deg_to_rad(150.0) * delta)

func _solve_2bone_ik(shoulder_world: Vector3, target_world: Vector3, side: String) -> Dictionary:
	var l1 := _l1
	var l2 := _l2
	var dist := clampf(shoulder_world.distance_to(target_world), absf(l1 - l2) + 0.01, l1 + l2 - 0.002)

	# Law of cosines for elbow flexion
	var cos_e := clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0)
	var angle_e := acos(cos_e)
	var elbow_flexion := PI - angle_e
	# Strict anatomical limit: 0° to 140° (no backward hyperextension!)
	elbow_flexion = clampf(elbow_flexion, 0.0, deg_to_rad(MAX_ELBOW_FLEX_DEG))

	# Upper arm rest direction in world coordinates
	var u_idx: int = _home.get("upperarm_" + side, -1)
	var l_idx: int = _home.get("lowerarm_" + side, -1)
	var rest_shoulder_w := _skeleton.global_transform * _skeleton.get_bone_global_rest(u_idx).origin
	var rest_elbow_w := _skeleton.global_transform * _skeleton.get_bone_global_rest(l_idx).origin
	var rest_dir_w := (rest_elbow_w - rest_shoulder_w).normalized()

	# World direction from current shoulder to target
	var target_dir_w := (target_world - shoulder_world).normalized()
	var q_w := Quaternion(rest_dir_w, target_dir_w)

	# Convert world delta rotation into bone local coordinates
	var bone_basis_w := _skeleton.global_transform.basis * _skeleton.get_bone_global_rest(u_idx).basis
	var bone_q_w := bone_basis_w.get_rotation_quaternion()
	var shoulder_rot := bone_q_w.inverse() * q_w * bone_q_w

	return {
		"shoulder_rot": shoulder_rot,
		"elbow_flexion": elbow_flexion
	}

func _apply_to_skeleton() -> void:
	if _skeleton == null:
		return

	# 1. The torso stays at rest.
	for name: String in SPINE_BONES:
		if _home.has(name):
			_skeleton.set_bone_pose_rotation(_home[name], _rest_quats[name])

	# 2. Head Tilt: the head alone turns about the line through the ears; the neck stays at rest.
	if _home.has("neck_01"):
		_skeleton.set_bone_pose_rotation(_home["neck_01"], _rest_quats["neck_01"])
	if _home.has("head") and (_head_tilt != 0.0 or _head_posed):
		var tilt := Quaternion(Vector3.RIGHT, deg_to_rad(_head_tilt))
		var head_rest: Quaternion = _rest_quats["head"]
		_skeleton.set_bone_pose_rotation(_home["head"], head_rest * tilt)
		_skeleton.set_bone_pose_position(_home["head"], _head_rest_position + head_rest * (_head_pivot - tilt * _head_pivot))
		_head_posed = _head_tilt != 0.0

	# 3. Arms
	for part: String in _arms:
		var side := part.right(1)
		if _home.has("lowerarm_" + side):
			var flexion: float = _arms[part].flexion
			var q_elbow := Quaternion(Vector3.RIGHT, flexion)
			_skeleton.set_bone_pose_rotation(_home["lowerarm_" + side], _rest_quats["lowerarm_" + side] * q_elbow)
		if _home.has("upperarm_" + side):
			_skeleton.set_bone_pose_rotation(_home["upperarm_" + side], _rest_quats["upperarm_" + side] * _arms[part].rot)

	_skeleton.force_update_all_bone_transforms()

func _update_bone_markers() -> void:
	if _skeleton == null:
		return
	for name: String in _bones:
		var marker: Node3D = _bones[name]
		var idx: int = _home.get(name, -1)
		if is_instance_valid(marker) and idx >= 0:
			marker.global_transform = _skeleton.global_transform * _skeleton.get_bone_global_pose(idx)

func _rest_point(name: String) -> Vector3:
	var idx: int = _home.get(name, -1)
	if idx < 0 or _skeleton == null:
		return Vector3.ZERO
	return _skeleton.global_transform * _skeleton.get_bone_global_rest(idx).origin
