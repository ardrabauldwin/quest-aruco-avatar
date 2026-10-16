class_name NaretHeadTiltGesture
extends RefCounted
## Animation-only prototype. Thresholds are provisional, not fitted to recordings.
## Two DIFFERENT tracked hands must hold their roles, then move together.
## No score, airway confirmation, or scenario observation is produced here.
const FOREHEAD_RADIUS_M := 0.06
const CHIN_RADIUS_M := 0.045
const HOLD_S := 0.35
const MOVE_WINDOW_S := 2.0
const MOTION_CONFIRM_S := 0.12
const LOST_GRACE_S := 0.25
var active := false
var state := "waiting"
var _forehead_hand := -1
var _hold := 0.0
var _move_time := 0.0
var _confirm := 0.0
var _lost := 0.0
var _forehead_start := Vector3.ZERO
var _chin_start := Vector3.ZERO

func reset() -> void:
	active = false
	state = "waiting"
	_forehead_hand = -1
	_hold = 0.0
	_move_time = 0.0
	_confirm = 0.0
	_lost = 0.0

func observe(hands: Array, forehead: Vector3, chin: Vector3, up: Vector3, toward_head: Vector3, delta: float) -> bool:
	# Caller supplies fresh tracked palm/index positions, or {} for an invalid hand.
	var dt := clampf(delta, 0.0, 0.05)
	var role := _forehead_hand
	if role < 0:
		for index in 2:
			if _matches(hands, index, forehead, chin, 1.0):
				role = index
				break
	var radius_factor := 1.4 if active else 1.0
	if role < 0 or not _matches(hands, role, forehead, chin, radius_factor):
		_lost += dt
		# A short dropout can hold an existing animation, never start a new one.
		if not active or _lost >= LOST_GRACE_S:
			reset()
		return active
	_lost = 0.0
	_forehead_hand = role
	var fore: Vector3 = hands[role].palm - forehead
	var lift: Vector3 = hands[1 - role].finger - chin
	if active:
		return true
	if state == "waiting":
		state = "positioning"
		_forehead_start = fore
		_chin_start = lift
	if state == "positioning":
		# Moving more than 1 cm resets the initial hold; a passing reach cannot arm.
		if fore.distance_to(_forehead_start) > 0.01 or lift.distance_to(_chin_start) > 0.01:
			_hold = 0.0
			_forehead_start = fore
			_chin_start = lift
		_hold += dt
		if _hold >= HOLD_S:
			state = "armed"
			_forehead_start = fore
			_chin_start = lift
		return false
	_move_time += dt
	if _move_time > MOVE_WINDOW_S:
		reset()
		return false
	var forehead_motion := fore - _forehead_start
	var chin_motion := lift - _chin_start
	# Forehead moves toward the crown or down; the other hand lifts the chin.
	# Reject excessive sideways movement instead of accepting any two-hand reach.
	var sideways := up.cross(toward_head).normalized()
	var coordinated := (forehead_motion.dot(toward_head) >= 0.008 or forehead_motion.dot(-up) >= 0.006) \
		and chin_motion.dot(up) >= 0.012 \
		and absf(forehead_motion.dot(sideways)) < 0.025 and absf(chin_motion.dot(sideways)) < 0.025
	_confirm = _confirm + dt if coordinated else 0.0
	if _confirm >= MOTION_CONFIRM_S:
		active = true
		state = "gesture_detected"
	return active

func _matches(hands: Array, role: int, forehead: Vector3, chin: Vector3, factor: float) -> bool:
	return hands.size() == 2 and not hands[role].is_empty() and not hands[1 - role].is_empty() \
		and hands[role].palm.distance_to(forehead) <= FOREHEAD_RADIUS_M * factor \
		and hands[1 - role].finger.distance_to(chin) <= CHIN_RADIUS_M * factor
