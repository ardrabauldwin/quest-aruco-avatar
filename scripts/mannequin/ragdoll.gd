class_name NaretRagdoll
extends Node
## Anatomical posing of the CPR mannequin: sit-up, hinge-limited arm IK and head tilt.

const GRAB_RANGE_M := 0.22
const REACH_M := 0.52
const MAX_SITUP_DEG := 80.0
const MAX_ELBOW_FLEX_DEG := 140.0
const MAX_HEAD_TILT_DEG := 35.0

const BONES := [
	"spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
	"upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r",
	"neck_01", "head",
]
# Grab candidates per part, checked in this order; a later part only wins when strictly closer.
# Upper arm and shoulder belong to the torso so touching them moves the shoulder girdle, not the hand.
const GRAB_PARTS := {
	"torso": ["spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r"],
	"arm_l": ["hand_l", "lowerarm_l"],
	"arm_r": ["hand_r", "lowerarm_r"],
	"head": ["head", "neck_01"],
}
const SPINE_WEIGHTS := {"spine_01": 0.45, "spine_02": 0.35, "spine_03": 0.20}

var _skeleton: Skeleton3D
var _bones: Dictionary = {}
var _home: Dictionary = {}
var _rest_quats: Dictionary = {}
var _held: Dictionary = {}
var _held_targets: Dictionary = {}
var _targets: Dictionary = {}

# Articulation states
var _torso_angle := 0.0
var _torso_target_angle := 0.0
var _torso_velocity := 0.0
var _torso_roll := 0.0
var _torso_target_roll := 0.0
var _head_tilt := 0.0
var _head_target_tilt := 0.0
var _head_held := false
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
	_held_targets.clear()
	_targets.clear()
	_torso_angle = 0.0
	_torso_target_angle = 0.0
	_torso_velocity = 0.0
	_torso_roll = 0.0
	_torso_target_roll = 0.0
	_head_tilt = 0.0
	_head_target_tilt = 0.0
	_head_held = false
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

	_held[id] = {"part": chosen_part, "anchor": anchor_name}
	_held_targets[id] = world_point
	_targets[id] = world_point

	if chosen_part == "torso":
		_update_torso_targets()
	elif chosen_part == "head":
		_head_held = true
	else:
		_arms[chosen_part].held = true
		_arms[chosen_part].target = world_point

	return true

func _get_shoulder_holders() -> Dictionary:
	var left_id := ""
	var right_id := ""
	for id: String in _held:
		var info: Dictionary = _held[id]
		if info.get("part") == "torso":
			var anchor: String = info.get("anchor", "")
			if anchor in ["clavicle_l", "upperarm_l"]:
				left_id = id
			elif anchor in ["clavicle_r", "upperarm_r"]:
				right_id = id
	return {"left": left_id, "right": right_id}

func has_both_shoulders_held() -> bool:
	var holders := _get_shoulder_holders()
	var left_id: String = holders.get("left", "")
	var right_id: String = holders.get("right", "")
	return not left_id.is_empty() and not right_id.is_empty() and left_id != right_id

func _update_torso_targets() -> void:
	var holders := _get_shoulder_holders()
	var left_id: String = holders.get("left", "")
	var right_id: String = holders.get("right", "")

	# Sitting up ("Aufrichten") strictly requires 2 hands grasping both shoulders.
	if has_both_shoulders_held():
		var p_left: Vector3 = _held_targets.get(left_id, _rest_point("upperarm_l"))
		var p_right: Vector3 = _held_targets.get(right_id, _rest_point("upperarm_r"))
		var avg_y: float = (p_left.y + p_right.y) * 0.5
		var pelvis_p := limb_point("pelvis")
		var lift: float = avg_y - pelvis_p.y
		var ratio := clampf((lift - 0.08) / 0.42, 0.0, 1.0)
		_torso_target_angle = ratio * MAX_SITUP_DEG
		_torso_target_roll = clampf((p_left.y - p_right.y) * 35.0, -12.0, 12.0)
	elif not left_id.is_empty() or not right_id.is_empty():
		# Only one shoulder is held: cannot sit the person up!
		# Torso pitch stays flat (0.0). Allows slight realistic roll (shaking shoulder for consciousness check).
		_torso_target_angle = 0.0
		var pelvis_p := limb_point("pelvis")
		if not left_id.is_empty():
			var p: Vector3 = _held_targets.get(left_id, _rest_point("upperarm_l"))
			_torso_target_roll = clampf((p.y - pelvis_p.y - 0.08) * 45.0, 0.0, 14.0)
		else:
			var p: Vector3 = _held_targets.get(right_id, _rest_point("upperarm_r"))
			_torso_target_roll = -clampf((p.y - pelvis_p.y - 0.08) * 45.0, 0.0, 14.0)
	else:
		_torso_target_angle = 0.0
		_torso_target_roll = 0.0

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
	_held_targets[id] = world_point

	if part == "torso":
		_update_torso_targets()

	elif _arms.has(part):
		var side := part.right(1)
		var target := bounded_target
		if anchor_name == "lowerarm_" + side:
			var dir := (bounded_target - limb_point("upperarm_" + side)).normalized()
			if dir.is_zero_approx():
				dir = Vector3.FORWARD
			target = bounded_target + dir * (_l2 * 0.5)
		_arms[part].target = target

	elif part == "head":
		var neck_p := limb_point("neck_01")
		var tilt_delta := (world_point.y - neck_p.y) * 90.0
		_head_target_tilt = clampf(tilt_delta, 0.0, MAX_HEAD_TILT_DEG)

func release(id: String) -> void:
	if not _held.has(id):
		return
	var info: Dictionary = _held[id]
	var part: String = info.get("part", "")
	_held.erase(id)
	_held_targets.erase(id)
	_targets.erase(id)

	_update_torso_targets()

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
	_update_torso_dynamics(delta)
	_update_arm_ik(delta)
	_update_head_dynamics(delta)
	_apply_to_skeleton()
	_update_bone_markers()

func _physics_process(delta: float) -> void:
	# Running in both steps guarantees fresh bone transforms for physics raycasts and frames
	_process(delta)

func _update_torso_dynamics(delta: float) -> void:
	if has_both_shoulders_held():
		_torso_angle = move_toward(_torso_angle, _torso_target_angle, 140.0 * delta)
		_torso_velocity = 0.0
	else:
		# Gravity return back down to mat with realistic damping
		if _torso_angle > 0.0:
			_torso_velocity += 180.0 * delta
			_torso_angle = maxf(0.0, _torso_angle - _torso_velocity * delta)
			if _torso_angle == 0.0:
				_torso_velocity = 0.0

	_torso_roll = move_toward(_torso_roll, _torso_target_roll, 80.0 * delta)

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

	# 1. Torso Aufrichten across spine bones (pivoting at hips)
	var situp_rad := deg_to_rad(_torso_angle)
	var roll_rad := deg_to_rad(_torso_roll)
	for name: String in SPINE_WEIGHTS:
		if _home.has(name):
			var w: float = SPINE_WEIGHTS[name]
			var q := Quaternion(Vector3.RIGHT, situp_rad * w) * Quaternion(Vector3.FORWARD, roll_rad * w)
			_skeleton.set_bone_pose_rotation(_home[name], _rest_quats[name] * q)

	# 2. Head Tilt
	if _home.has("neck_01"):
		var neck_rad := deg_to_rad(_head_tilt)
		_skeleton.set_bone_pose_rotation(_home["neck_01"], _rest_quats["neck_01"] * Quaternion(Vector3.RIGHT, neck_rad))

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
