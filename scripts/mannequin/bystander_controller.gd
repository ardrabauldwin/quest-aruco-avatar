class_name NaretBystander
extends Node3D
## A bystander who stays oriented to the scene: the body turns so the trainee and
## the patient are both in view, the head and eyes go to whoever matters right
## now, and tasks (walking off, phoning, carrying) have their own posture.
## NaretBystanderDirector decides what they do; this node only makes it look right.

signal arrived

@export var phase_offset := 0.0
@export_range(0.0,1.0,0.05) var speech_jaw_scale := 1.0
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
## Set while a task fixes where the body points (setting the AED down): the usual
## turn toward trainee and patient would swing a kneeling helper round on the spot.
var facing_locked := false
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

## Real collision bodies (14 Nov 2026, "cannot every character be a physics body, so
## that nothing passes through"). Each character owns a solid capsule on BODY_LAYER and
## moves a second capsule, the mover, through the physics world when he walks: the
## engine stops it at the other characters, the patient, the stool and the trainee
## (main builds those three) and slides it along them. The circles of `obstacles` stay
## as the planner's map and as a second line. All shapes are 3 m tall, so only the
## floor plan counts: a patient on a table and one on the floor block the same way.
const BODY_LAYER := 1 << 5
const BODY_RADIUS_M := 0.22
const BODY_TALL_M := 3.0
var _solid: StaticBody3D
var _mover: CharacterBody3D

func _build_bodies() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS_M
	capsule.height = BODY_TALL_M
	_solid = StaticBody3D.new()
	_solid.name = "SolidBody"
	_solid.collision_layer = BODY_LAYER
	_solid.collision_mask = 0
	var solid_shape := CollisionShape3D.new()
	solid_shape.shape = capsule
	solid_shape.position = Vector3(0, BODY_TALL_M * 0.5, 0)
	_solid.add_child(solid_shape)
	add_child(_solid)
	_mover = CharacterBody3D.new()
	_mover.name = "WalkMover"
	_mover.top_level = true
	_mover.collision_layer = 0
	_mover.collision_mask = BODY_LAYER
	_mover.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var mover_shape := CollisionShape3D.new()
	mover_shape.shape = capsule
	mover_shape.position = Vector3(0, BODY_TALL_M * 0.5, 0)
	_mover.add_child(mover_shape)
	add_child(_mover)
	_mover.add_collision_exception_with(_solid)

## Walking straight at a flat side (the stool, the patient's flank) there is nothing to
## slide along: he then follows that side for DODGE_S at a time, always to the same
## hand, until the way to his goal is open again.
const DODGE_S := 0.35
var _dodge := Vector3.ZERO
var _dodge_left_s := 0.0
var _dodge_side := 0.0

func _step_solid(step: Vector3, delta: float) -> void:
	## One walking step through the physics world: stopped by a body, then along it.
	if _mover == null or not is_inside_tree() or DisplayServer.get_name() == "headless":
		global_position += step
		return
	_mover.global_position = global_position
	var length := step.length()
	if _dodge_left_s > 0.0:
		_dodge_left_s -= delta
		_mover.move_and_collide(_dodge * length)
	else:
		var hit := _mover.move_and_collide(step)
		if hit:
			var along := hit.get_remainder().slide(hit.get_normal())
			along.y = 0.0
			if along.length() < length * 0.2:
				var side := hit.get_normal().cross(Vector3.UP)
				side.y = 0.0
				if side.length() > 0.01:
					# The same hand as last time; first time, the side nearer his heading.
					if _dodge_side == 0.0: _dodge_side = 1.0 if side.dot(step) >= 0.0 else -1.0
					_dodge = side.normalized() * _dodge_side
					_dodge_left_s = DODGE_S
					along = _dodge * length
			_mover.move_and_collide(along)
		else:
			_dodge_side = 0.0 # A free step toward the goal: the obstacle is behind him.
	global_position = Vector3(_mover.global_position.x, global_position.y, _mover.global_position.z)

func _ready() -> void:
	process_priority = 110 # Ground the feet after RigAnimator applies its pose (100).
	_build_bodies()
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	_rig = NaretRigAnimator.new()
	_rig.speech_jaw_scale = speech_jaw_scale
	_rig.name = "RigAnimator"
	add_child(_rig)
	_rig.configure(model)
	_rig.enable_head_turn(model)
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var hands := HandsOutOfTrunk.new()
		hands.name = "HandsOutOfTrunk"
		(skeletons[0] as Skeleton3D).add_child(hands)
	_rig.set_emotion(emotion)
	_rig.set_speaking(speaking)
	_glance_left = 1.5 + phase_offset

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if _walk_target != Vector3.INF:
		_walk(delta)
	elif camera and patient and not facing_locked:
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
## () -> Array of {"point": Vector2 (world x, z), "radius": float}: people and things in
## the way (main: the other characters, the trainee, the stool).
var obstacles: Callable
## Kept between his body and an obstacle's edge when the path is planned.
const PASS_CLEAR_M := 0.30
## Bodies are solid (13 Nov 2026): while he walks he cannot come nearer than this to an
## obstacle's edge. Whatever is in the way then, also someone who stepped into his path
## after it was planned, pushes him out and he slides round it. Smaller than
## PASS_CLEAR_M, so a planned path never touches.
const BODY_CLEAR_M := 0.20

func walk_to(target: Vector3) -> void:
	## Walks on the floor plane and emits `arrived`; faces the way it goes. Never
	## across the patient: a path through them goes round the head or the feet. Never
	## through another person or the stool either: each leg that would pass through one
	## gets a waypoint beside it.
	_route = _around_patient(global_position, target)
	_route.append(Vector3(target.x, global_position.y, target.z))
	_route = _around_obstacles(global_position, _route)
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

func _around_obstacles(from: Vector3, route: Array[Vector3]) -> Array[Vector3]:
	if not obstacles.is_valid(): return route
	var blocks: Array = obstacles.call()
	var clear: Array[Vector3] = []
	var start := Vector2(from.x, from.z)
	for stop in route:
		var end := Vector2(stop.x, stop.z)
		var leg := end - start
		if leg.length() > 0.1:
			for block: Dictionary in blocks:
				var centre: Vector2 = block.point
				var keep: float = float(block.radius) + PASS_CLEAR_M
				# Only an obstacle the leg passes counts: one whose nearest point is the
				# leg's own start or end is being left or approached, not walked through.
				# (An obstacle merely close to the start still counts: in a small play
				# area Anna stands within a step of Marek's spot.)
				var along := (centre - start).dot(leg) / leg.length_squared()
				if along <= 0.0 or along >= 1.0: continue
				var nearest := start + leg * along
				if nearest.distance_to(centre) >= keep: continue
				var aside := nearest - centre
				if aside.length() < 0.01: aside = leg.orthogonal()
				var via := centre + aside.normalized() * (keep + 0.05)
				clear.append(Vector3(via.x, from.y, via.y))
				break # One detour per leg; a second obstacle on it is rare in this scene.
		clear.append(stop)
		start = end
	return clear

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
	_step_solid(direction * minf(_speed * delta, offset.length()), delta)
	_collide(Vector2(direction.x, direction.z), delta)

func _collide(heading: Vector2, delta: float) -> void:
	if not obstacles.is_valid(): return
	var goal := _route[-1] if not _route.is_empty() else _walk_target
	var here := Vector2(global_position.x, global_position.z)
	for block: Dictionary in obstacles.call():
		var centre: Vector2 = block.point
		var solid: float = float(block.radius) + BODY_CLEAR_M
		# Where he is going may be close to it (setting the device on the stool): then it
		# is solid only up to that spot. It used to stop being solid altogether, and he
		# walked straight through it from the far side (headset 13 Nov 2026).
		solid = minf(solid, Vector2(goal.x, goal.z).distance_to(centre) - 0.02)
		if solid <= 0.05: continue
		var out := here - centre
		if out.length() >= solid: continue
		var normal := out.normalized() if out.length() > 0.01 else -heading
		# Out to the surface, and along it on the side his heading points to.
		var along := normal.orthogonal()
		if along.dot(heading) < 0.0: along = -along
		here = centre + normal * solid + along * _speed * delta
	global_position = Vector3(here.x, global_position.y, here.y)

func path_length_m() -> float:
	## What is left of the way he is on: to the current waypoint and on through the rest.
	if _walk_target == Vector3.INF: return 0.0
	var length := 0.0
	var from := global_position
	for stop: Vector3 in [_walk_target] + _route:
		length += Vector2(stop.x - from.x, stop.z - from.z).length()
		from = stop
	return length

func is_walking() -> bool:
	return _walk_target != Vector3.INF

func halt(at: Vector3 = Vector3.INF) -> void:
	## Ends a walk without `arrived`; with a point, stands there (floor height kept).
	_route.clear()
	_walk_target = Vector3.INF
	_speed = 0.0
	if at != Vector3.INF:
		global_position = Vector3(at.x, global_position.y, at.z)
	set_posture("")

func standing_floor_y() -> float:
	return _standing_floor_y if is_finite(_standing_floor_y) else global_position.y

## Per-person look on a shared model: the instructor and Marek are the same GLB.
## `shirt` recolours the "NaReT everyday shirt" surface; `skin` replaces the body's
## skin texture (Marek's has the beard painted in, tools/paint_beard.gd).
func set_look(shirt: Color, skin: Texture2D = null) -> void:
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null: continue
			var is_shirt := "everyday shirt" in source.resource_name
			var is_skin := skin != null and String(mesh.name).ends_with("Body") and source.albedo_texture != null
			if not is_shirt and not is_skin: continue
			var copy := source.duplicate() as StandardMaterial3D
			if is_shirt: copy.albedo_color = shirt
			if is_skin: copy.albedo_texture = skin
			mesh.set_surface_override_material(surface, copy)

var _task_posture := ""
var _offer: OfferPose

## Several motion clips put an arm inside the body: in the woman's "anxious" loop the
## left elbow and forearm sink into the shirt at the waist (side render 13 Nov 2026), and
## two of her talking takes do the same with the right. Seen in the headset as a hand
## going into the shirt. After every clip the elbow, the middle of the forearm and the
## wrist are tested against the trunk, an ellipse round the line from hips to chest
## (wider than deep), and whatever is inside is swung out to its surface: the upper
## arm about the shoulder for the elbow, the forearm about the elbow for the rest.
class HandsOutOfTrunk extends SkeletonModifier3D:
	## Bone centres are kept this far from the trunk's centre line: half the trunk plus
	## half an arm, to the side and to the front or back.
	const SIDE_M := 0.19
	const DEPTH_M := 0.15
	## The trunk ends below the neck; hands at the throat or face are not inside it.
	const TOP := 0.85
	const ARMS := [["upperarm_l", "lowerarm_l", "hand_l"], ["upperarm_r", "lowerarm_r", "hand_r"]]

	func _process_modification() -> void:
		var skeleton := get_skeleton()
		if skeleton == null: return
		var low := skeleton.find_bone("pelvis")
		var high := skeleton.find_bone("neck_01")
		var left := skeleton.find_bone("upperarm_l")
		var right := skeleton.find_bone("upperarm_r")
		if low < 0 or high < 0 or left < 0 or right < 0: return
		var a := skeleton.get_bone_global_pose(low).origin
		var line := skeleton.get_bone_global_pose(high).origin - a
		var across := skeleton.get_bone_global_pose(right).origin - skeleton.get_bone_global_pose(left).origin
		if line.length_squared() < 0.0001 or across.length_squared() < 0.0001: return
		var up := line.normalized()
		var side := (across - up * across.dot(up)).normalized()
		var front := side.cross(up)
		for arm: Array in ARMS:
			var shoulder := skeleton.find_bone(arm[0])
			var elbow := skeleton.find_bone(arm[1])
			var wrist := skeleton.find_bone(arm[2])
			if shoulder < 0 or elbow < 0 or wrist < 0: continue
			_swing(skeleton, shoulder, skeleton.get_bone_global_pose(elbow).origin, a, line, side, front)
			var from := skeleton.get_bone_global_pose(elbow).origin
			var hand := skeleton.get_bone_global_pose(wrist).origin
			var middle := (from + hand) * 0.5
			var pushed := _outside(middle, a, line, side, front)
			if pushed != middle:
				_swing_to(skeleton, elbow, hand, hand + (pushed - middle) * 2.0)
			_swing(skeleton, elbow, skeleton.get_bone_global_pose(wrist).origin, a, line, side, front)

	func _outside(point: Vector3, a: Vector3, line: Vector3, side: Vector3, front: Vector3) -> Vector3:
		## `point` itself, or the nearest point on the trunk's surface if it is inside.
		var along := (point - a).dot(line) / line.length_squared()
		if along < 0.0 or along > TOP: return point
		var centre := a + line * along
		var x := (point - centre).dot(side)
		var z := (point - centre).dot(front)
		var inside := sqrt(pow(x / SIDE_M, 2.0) + pow(z / DEPTH_M, 2.0))
		if inside >= 1.0: return point
		if inside < 0.05: return centre + side * SIDE_M * (1.0 if x >= 0.0 else -1.0)
		return centre + side * (x / inside) + front * (z / inside)

	func _swing(skeleton: Skeleton3D, bone: int, tip: Vector3, a: Vector3, line: Vector3, side: Vector3, front: Vector3) -> void:
		var wanted := _outside(tip, a, line, side, front)
		if wanted != tip: _swing_to(skeleton, bone, tip, wanted)

	func _swing_to(skeleton: Skeleton3D, bone: int, tip: Vector3, wanted: Vector3) -> void:
		var pose := skeleton.get_bone_global_pose(bone)
		var now := tip - pose.origin
		var then := wanted - pose.origin
		if now.length_squared() < 1.0e-6 or then.length_squared() < 1.0e-6: return
		skeleton.set_bone_global_pose(bone, Transform3D(Basis(Quaternion(now.normalized(), then.normalized())) * pose.basis, pose.origin))

## Handing something over (13 Nov 2026, headset review): the body leans a little toward
## the other person from the hips and the right forearm comes up and forward, on top of
## whatever clip is playing, so he keeps breathing and looking. The "reach" clip that
## was used for this bends him 50 cm forward and holds him there; the "relief" clip that
## "calm" started leaned him 22 cm backward. Both read as wrong for a hand-over.
class OfferPose extends SkeletonModifier3D:
	const SPINE := ["spine_01", "spine_02", "spine_03"]
	## Forward lean, and upper arm and forearm directions as (forward, up) parts; sideways
	## stays as it is. The values in use ease toward the wanted ones, so going from
	## holding out to setting down is one movement.
	var lean_deg := 14.0
	var upper_arm := Vector2(0.55, -0.83)
	var forearm := Vector2(0.97, 0.24)
	var _lean := 14.0
	var _upper := Vector2(0.55, -0.83)
	var _fore := Vector2(0.97, 0.24)
	var amount := 0.0
	var target := 0.0
	## Model forward and up in skeleton space.
	var forward := Vector3.BACK
	var up := Vector3.UP
	func _process_modification() -> void:
		var dt := get_process_delta_time()
		amount = move_toward(amount, target, dt * 1.4)
		if amount <= 0.0:
			_lean = lean_deg
			_upper = upper_arm
			_fore = forearm
			return
		_lean = move_toward(_lean, lean_deg, dt * 45.0)
		_upper = _upper.move_toward(upper_arm, dt * 1.5)
		_fore = _fore.move_toward(forearm, dt * 1.5)
		var skeleton := get_skeleton()
		if skeleton == null: return
		var weight := smoothstep(0.0, 1.0, amount)
		var hinge := up.cross(forward).normalized()
		for bone_name: String in SPINE:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0: continue
			var pose := skeleton.get_bone_global_pose(bone)
			skeleton.set_bone_global_pose(bone, Transform3D(Basis(hinge, deg_to_rad(_lean / SPINE.size()) * weight) * pose.basis, pose.origin))
		_aim(skeleton, "upperarm_r", "lowerarm_r", _upper, weight)
		_aim(skeleton, "lowerarm_r", "hand_r", _fore, weight)
	func _aim(skeleton: Skeleton3D, bone_name: String, child_name: String, direction: Vector2, weight: float) -> void:
		var bone := skeleton.find_bone(bone_name)
		var child := skeleton.find_bone(child_name)
		if bone < 0 or child < 0: return
		var pose := skeleton.get_bone_global_pose(bone)
		var now := skeleton.get_bone_global_pose(child).origin - pose.origin
		if now.length_squared() < 1.0e-6: return
		var want := (forward * direction.x + up * direction.y).normalized()
		var swing := Quaternion.IDENTITY.slerp(Quaternion(now.normalized(), want), weight)
		skeleton.set_bone_global_pose(bone, Transform3D(Basis(swing) * pose.basis, pose.origin))

func _offer_pose() -> OfferPose:
	if _offer: return _offer
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty(): return null
	var skeleton := skeletons[0] as Skeleton3D
	_offer = OfferPose.new()
	_offer.name = "OfferPose"
	skeleton.add_child(_offer)
	return _offer

## Setting something down on a surface this high above his floor ("place" posture): he
## bends just as far as his hand has to go, 12 degrees for a table top, 50 for a low stool.
var place_height_m := 0.8
## Rig measures: hips to shoulder, shoulder to hand, and how far the carried device
## hangs below the hand (NaretAED.CARRY).
const TRUNK_M := 0.47
const ARM_M := 0.55
const CARRIED_BELOW_HAND_M := 0.22
const HIP_HEIGHT_M := 0.93
const PLACE_ARM_DEG := 25.0

static func place_lean_deg(height_m: float) -> float:
	var hand_y := height_m + CARRIED_BELOW_HAND_M
	var shoulder_y := hand_y + ARM_M * cos(deg_to_rad(PLACE_ARM_DEG))
	return clampf(rad_to_deg(acos(clampf((shoulder_y - HIP_HEIGHT_M) / TRUNK_M, -1.0, 1.0))), 12.0, 50.0)

static func place_reach_m(height_m: float) -> float:
	## How far in front of his feet the hand is in that pose: where he has to stand.
	return TRUNK_M * sin(deg_to_rad(place_lean_deg(height_m))) + ARM_M * sin(deg_to_rad(PLACE_ARM_DEG))

func set_posture(posture: String) -> void:
	## "offer" (hand-over) and "place" (setting down) are the pose above; every other
	## name is a clip of the rig.
	var offering := posture in ["offer", "place"]
	if offering or _offer:
		var pose := _offer_pose()
		if pose:
			var skeleton := pose.get_skeleton()
			if skeleton:
				pose.forward = (skeleton.global_basis.inverse() * global_basis.z).normalized()
				pose.up = (skeleton.global_basis.inverse() * Vector3.UP).normalized()
			pose.target = 1.0 if offering else 0.0
			if posture == "offer":
				pose.lean_deg = 14.0
				pose.upper_arm = Vector2(0.55, -0.83)
				pose.forearm = Vector2(0.97, 0.24)
			elif posture == "place":
				pose.lean_deg = place_lean_deg(place_height_m)
				var arm := deg_to_rad(PLACE_ARM_DEG)
				pose.upper_arm = Vector2(sin(arm), -cos(arm))
				pose.forearm = Vector2(sin(arm + 0.15), -cos(arm + 0.15))
	if offering: posture = ""
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

func drop_talk_takes(takes: Array) -> void:
	if is_instance_valid(_rig): _rig.drop_takes(takes)

func set_emotion(value: String) -> void:
	emotion = value
	if is_instance_valid(_rig):
		_rig.set_emotion(value)

func set_mouth_open(amount: float) -> void:
	if is_instance_valid(_rig):
		_rig.set_mouth_open(amount)

func set_mouth_bands(bands: Vector3) -> void:
	if is_instance_valid(_rig):
		_rig.set_mouth_bands(bands)

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

func update_standing_floor(floor_y: float) -> void:
	# A fingertip correction changes height without reallocating standing spots.
	if not is_finite(floor_y): return
	if is_finite(_standing_floor_y): global_position.y += floor_y - _standing_floor_y
	_standing_floor_y = floor_y
	_keep_feet_on_floor()
	if _floor_shadow: _floor_shadow.set_shader_parameter("floor_y", floor_y)

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
