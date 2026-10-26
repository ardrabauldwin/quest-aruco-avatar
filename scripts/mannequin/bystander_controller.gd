class_name NaretBystander
extends Node3D
## A bystander who stays oriented to the scene: the body turns so the trainee and
## the patient are both in view, the head and eyes go to whoever matters right
## now, and tasks (walking off, phoning, carrying) have their own posture.
## NaretBystanderDirector decides what they do; this node only makes it look right.

signal arrived

@export var phase_offset := 0.0
## Matches the walk clip (tools/generate_humans.py prints NARET_KIMODO): at this
## speed a planted foot does not slide. Walks start and stop over ACCEL_S.
const WALK_SPEED := 1.3
const ACCEL_S := 0.35
## Turn only when the trainee has drifted clearly out of view, then settle.
const TURN_START_DEG := 32.0
const TURN_STOP_DEG := 6.0
const TURN_SPEED_DEG := 110.0

var emotion := "anxious"
var speaking := false:
	set(value):
		speaking = value
		if is_instance_valid(_rig):
			_rig.set_speaking(value)
## "auto" alternates between trainee and patient, "trainee" and "patient" hold.
var attention := "auto"
var patient: Node3D
var _rig: NaretRigAnimator
var _glance_left := 2.0
var _glance_patient := false
var _turning := false
var _walk_target := Vector3.INF
var _speed := 0.0
var _hand: BoneAttachment3D
var _phone: MeshInstance3D
var _floor_shadow: ShaderMaterial
var _standing_floor_y := NAN
var _floor_skeleton: Skeleton3D
var _foot_bones: Array[int] = []
var _sole_below_foot_m := 0.0

func _ready() -> void:
	process_priority = 110 # Ground the feet after RigAnimator applies its pose (100).
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	_rig = NaretRigAnimator.new()
	_rig.name = "RigAnimator"
	add_child(_rig)
	_rig.configure(model)
	_rig.enable_head_turn(model)
	_rig.set_emotion(emotion)
	_rig.set_speaking(speaking)
	_glance_left = 1.5 + phase_offset

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if _walk_target != Vector3.INF:
		_walk(delta)
	elif camera and patient:
		_face_scene(camera.global_position, delta)
	if is_instance_valid(_rig) and _rig.has_gaze() and camera:
		_rig.look_at_point(_gaze_point(camera.global_position, delta))

	_keep_feet_on_floor()

func _gaze_point(trainee: Vector3, delta: float) -> Vector3:
	## Talking means eye contact. Otherwise glance between the trainee's face and
	## the patient's chest, lingering on the trainee, like someone following the CPR.
	var chest := patient.global_position + Vector3(0, 0.22, 0) if patient else trainee
	if _walk_target != Vector3.INF:
		return global_position + global_basis.z * 3.0 + Vector3(0, 1.5, 0)
	if speaking or attention == "trainee" or patient == null:
		return trainee
	if attention == "patient":
		return chest
	_glance_left -= delta
	if _glance_left <= 0.0:
		_glance_patient = not _glance_patient
		_glance_left = randf_range(1.2, 2.2) if _glance_patient else randf_range(2.0, 3.8)
	return chest if _glance_patient else trainee

func _face_scene(trainee: Vector3, delta: float) -> void:
	## Stand so both the trainee and the patient are in view: face their midpoint.
	var focus := (trainee + patient.global_position) * 0.5
	var to_focus := Vector3(focus.x - global_position.x, 0, focus.z - global_position.z)
	if to_focus.length_squared() < 0.04:
		return
	var error := rad_to_deg(global_basis.z.signed_angle_to(to_focus.normalized(), Vector3.UP))
	if absf(error) > TURN_START_DEG:
		_turning = true
	elif absf(error) < TURN_STOP_DEG:
		_turning = false
	if _turning:
		rotate_y(deg_to_rad(clampf(error, -TURN_SPEED_DEG * delta, TURN_SPEED_DEG * delta)))
	# Nobody swivels on the spot like a statue: small steps while turning.
	if is_instance_valid(_rig):
		# A standing speaker still faces the trainee, but a turn must not replace
		# the talk clip at the start of an instruction. Actual walking uses _walk().
		var turning_steps := _turning and not speaking
		_rig.set_posture("walk" if turning_steps else _task_posture, 0.55 if turning_steps else 1.0)

var _route: Array[Vector3] = []

func walk_to(target: Vector3) -> void:
	## Walks on the floor plane and emits `arrived`; faces the way it goes. Never
	## across the patient: a path through them goes round the head or the feet.
	_route = _around_patient(global_position, target)
	_route.append(Vector3(target.x, global_position.y, target.z))
	_walk_target = _route.pop_front()
	set_posture("walk")

func _around_patient(from: Vector3, to: Vector3) -> Array[Vector3]:
	## Waypoints (world) past the nearer end of the patient, or none if the straight
	## line keeps clear. Patient-local footprint, the same as the room placement's.
	var route: Array[Vector3] = []
	if patient == null:
		return route
	var a := patient.to_local(from)
	var b := patient.to_local(to)
	const HALF := Vector2(0.5, 1.2)
	var crosses := false
	for i in 21:
		var p := a.lerp(b, i / 20.0)
		crosses = crosses or (absf(p.x) < HALF.x and absf(p.z) < HALF.y)
	if not crosses:
		return route
	var best := INF
	for end in [-1.0, 1.0]:
		var z: float = end * (HALF.y + 0.35)
		var via: Array[Vector3] = [Vector3(signf(a.x if a.x != 0.0 else 1.0) * (HALF.x + 0.35), 0, z), Vector3(signf(b.x if b.x != 0.0 else 1.0) * (HALF.x + 0.35), 0, z)]
		var length := a.distance_to(via[0]) + via[0].distance_to(via[1]) + via[1].distance_to(b)
		if length < best:
			best = length
			route.clear()
			for point in via:
				var world := patient.to_global(point)
				route.append(Vector3(world.x, global_position.y, world.z))
	return route

func _walk(delta: float) -> void:
	var offset := _walk_target - global_position
	offset.y = 0.0
	if offset.length() < 0.05 and not _route.is_empty():
		_walk_target = _route.pop_front()
		return
	if offset.length() < 0.05:
		_walk_target = Vector3.INF
		_speed = 0.0
		set_posture("")
		arrived.emit()
		return
	var direction := offset.normalized()
	# Characters model +Z forward; looking_at aims -Z, so aim it away from the goal.
	var target_basis := Basis.looking_at(-direction, Vector3.UP)
	global_basis = global_basis.slerp(target_basis, 1.0 - exp(-8.0 * delta)).orthonormalized()
	# Ease in, and ease out over the last half metre, with the clip following the pace.
	var cruise := WALK_SPEED * clampf(offset.length() / 0.5, 0.35, 1.0)
	_speed = move_toward(_speed, cruise, WALK_SPEED / ACCEL_S * delta)
	if is_instance_valid(_rig):
		_rig.set_posture("walk", maxf(_speed / WALK_SPEED, 0.35))
	global_position += direction * minf(_speed * delta, offset.length())

func is_walking() -> bool:
	return _walk_target != Vector3.INF

var _task_posture := ""

func set_posture(posture: String) -> void:
	_task_posture = posture
	if is_instance_valid(_rig):
		_rig.set_posture(posture)
	if _phone:
		_phone.visible = posture == "phone"

func show_phone() -> void:
	## A smartphone in the right hand, to the ear while calling 112.
	var hand := _hand_attachment()
	if hand == null:
		return
	if _phone == null:
		_phone = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.072, 0.15, 0.009)
		_phone.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.05, 0.05, 0.06)
		material.roughness = 0.25
		_phone.material_override = material
		hand.add_child(_phone)
		# ponytail: palm offset fitted to the MakeHuman hand in review renders.
		_place_in_hand(_phone, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.09, 0.03)))
	set_posture("phone")

func hold(node: Node3D, offset: Transform3D) -> void:
	## Carry `node` in the right hand, e.g. the AED by its strap.
	var hand := _hand_attachment()
	if hand == null:
		return
	node.reparent(hand, false)
	_place_in_hand(node, offset)

func _place_in_hand(node: Node3D, offset: Transform3D) -> void:
	# The imported rig carries its export scale; offsets are metres in the hand's frame.
	var hand := _hand_attachment()
	node.global_transform = hand.global_transform.orthonormalized() * offset

func _hand_attachment() -> BoneAttachment3D:
	if _hand:
		return _hand
	var skeletons := find_children("*", "Skeleton3D", true, false)
	var skeleton: Skeleton3D = skeletons[0] if not skeletons.is_empty() else null
	if skeleton == null or skeleton.find_bone("hand_r") < 0:
		return null
	_hand = BoneAttachment3D.new()
	_hand.name = "RightHand"
	_hand.bone_name = "hand_r"
	skeleton.add_child(_hand)
	return _hand

func set_emotion(value: String) -> void:
	emotion = value
	if is_instance_valid(_rig):
		_rig.set_emotion(value)

func set_mouth_open(amount: float) -> void:
	if is_instance_valid(_rig):
		_rig.set_mouth_open(amount)

func place_on_floor(spot: Transform3D) -> void:
	## The scan supplies floor height. Offset the model's feet, not its origin,
	## onto that floor; this also accommodates different male/female mesh origins.
	global_transform = spot
	var lowest := INF
	for child in $Model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		# Skinned bounds describe the bind pose, not the visible animated shoes.
		# Match the renderer's bone deformation before measuring floor contact.
		for surface in mesh.mesh.get_surface_count():
			for vertex in NaretSpatialAnchor.posed_vertices(mesh, surface):
				lowest = minf(lowest, (mesh.global_transform * vertex).y)
	if is_finite(lowest):
		global_position.y += spot.origin.y - lowest
		_standing_floor_y = spot.origin.y
		if _floor_skeleton == null:
			var skeletons := $Model.find_children("*", "Skeleton3D", true, false)
			if not skeletons.is_empty():
				_floor_skeleton = skeletons[0] as Skeleton3D
				for name in ["foot_l", "foot_r"]:
					var bone := _floor_skeleton.find_bone(name)
					if bone >= 0:
						_foot_bones.append(bone)
		if not _foot_bones.is_empty():
			var foot_y := INF
			for bone in _foot_bones:
				foot_y = minf(foot_y, (_floor_skeleton.global_transform * _floor_skeleton.get_bone_global_pose(bone)).origin.y)
			_sole_below_foot_m = spot.origin.y - foot_y
	if _floor_shadow:
		_floor_shadow.set_shader_parameter("floor_y", spot.origin.y)

func cast_floor_shadow(light_direction: Vector3) -> void:
	## Passthrough shows the real floor, which receives no shadow-map shadows, so
	## every mesh also draws itself flattened onto the floor as a soft dark pass.
	if _floor_shadow == null:
		_floor_shadow = ShaderMaterial.new()
		_floor_shadow.shader = preload("res://assets/floor_shadow.gdshader")
		_floor_shadow.set_shader_parameter("floor_y", global_position.y)
		for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = _floor_shadow
	_floor_shadow.set_shader_parameter("light_direction", light_direction)

func _keep_feet_on_floor() -> void:
	if not visible or not is_finite(_standing_floor_y) or _floor_skeleton == null or _foot_bones.is_empty():
		return
	var foot_y := INF
	for bone in _foot_bones:
		foot_y = minf(foot_y, (_floor_skeleton.global_transform * _floor_skeleton.get_bone_global_pose(bone)).origin.y)
	# Preserve the initial shoe-sole offset as idle/talking/turning poses change.
	global_position.y += _standing_floor_y - (foot_y + _sole_below_foot_m)
