class_name NaretHeadTiltGesture
extends RefCounted
## Animation-only prototype. Thresholds are provisional, not fitted to recordings.
## Detection: two DIFFERENT tracked hands must hold their roles, then move together.
## Steering needs only the chin: with a bag-valve mask that is the only contact.
## No score, airway confirmation, or scenario observation is produced here.
const FOREHEAD_RADIUS_M := 0.06
# Small and set slightly into the model's chin: a fingertip has to touch it.
const CHIN_RADIUS_M := 0.03
# The fingertips that count on the chin: the ones under it in a chin lift.
const CHIN_FINGERS := ["index", "middle"]
const ACTIVE_RADIUS_FACTOR := 1.4
const HOLD_S := 0.1
# Moving more than this restarts a hold; a passing reach cannot arm.
const STILL_M := 0.01
## A steering finger lets go once it is this far out of the head's tilt plane
## (along the ear line); inside it, it may leave the chin zone.
const STEER_PLANE_M := 0.03
const MOVE_WINDOW_S := 2.0
const MOTION_CONFIRM_S := 0.12
const LOST_GRACE_S := 0.25
var active := false
var state := "waiting"
# Whether each zone's own hand condition holds this frame; only debug overlays read these.
var forehead_met := false
var chin_met := false
## The hand and finger ("index" or "middle") that steer the head, or -1 and "".
## A fingertip held still in the chin zone for HOLD_S takes the head; from then on
## the head follows `steer_point` about the ear line (NaretRagdoll.steer_head).
var steer_hand := -1
var steer_finger := ""
var steer_point := Vector3.ZERO
var _steer_candidate := ""
var _steer_hold := 0.0
var _steer_start := Vector3.ZERO
var _steer_lost := 0.0
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

func release_steer() -> void:
	steer_hand = -1
	steer_finger = ""
	_steer_candidate = ""
	_steer_hold = 0.0
	_steer_lost = 0.0

func observe(hands: Array, forehead: Vector3, chin: Vector3, up: Vector3, toward_head: Vector3, delta: float) -> bool:
	# Caller supplies fresh tracked points per hand: "palm", "index" and "middle"
	# (fingertips), each left out while untracked; {} for an untracked hand.
	var dt := clampf(delta, 0.0, 0.05)
	# The ear line runs across the head, normal to the plane the head tilts in.
	var sideways := up.cross(toward_head).normalized()
	_update_steer(hands, chin, sideways, dt)
	var role := _forehead_hand
	if role < 0:
		for index in 2:
			if _matches(hands, index, forehead, chin, 1.0):
				role = index
				break
	var radius_factor := ACTIVE_RADIUS_FACTOR if active else 1.0
	_update_gates(hands, forehead, chin, radius_factor)
	if role < 0 or not _matches(hands, role, forehead, chin, radius_factor):
		_lost += dt
		# A short dropout can hold an existing animation, never start a new one.
		if not active or _lost >= LOST_GRACE_S:
			reset()
		return active
	_lost = 0.0
	_forehead_hand = role
	var fore: Vector3 = hands[role].palm - forehead
	var lift: Vector3 = _chin_tip(hands[1 - role], chin) - chin
	if active:
		return true
	if state == "waiting":
		state = "positioning"
		_forehead_start = fore
		_chin_start = lift
	if state == "positioning":
		if fore.distance_to(_forehead_start) > STILL_M or lift.distance_to(_chin_start) > STILL_M:
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
	# Forehead moves toward the crown or down; the other hand lifts the chin, less
	# than the chin zone's radius. Reject excessive sideways movement instead of
	# accepting any two-hand reach.
	var coordinated := (forehead_motion.dot(toward_head) >= 0.008 or forehead_motion.dot(-up) >= 0.006) \
		and chin_motion.dot(up) >= 0.008 \
		and absf(forehead_motion.dot(sideways)) < 0.025 and absf(chin_motion.dot(sideways)) < 0.025
	_confirm = _confirm + dt if coordinated else 0.0
	if _confirm >= MOTION_CONFIRM_S:
		active = true
		state = "gesture_detected"
	return active

func _update_gates(hands: Array, forehead: Vector3, chin: Vector3, factor: float) -> void:
	forehead_met = false
	chin_met = steer_hand >= 0
	for hand: Dictionary in hands:
		forehead_met = forehead_met or (hand.has("palm") and hand.palm.distance_to(forehead) <= FOREHEAD_RADIUS_M * factor)
		chin_met = chin_met or _chin_tip(hand, chin).distance_to(chin) <= CHIN_RADIUS_M * factor

func _update_steer(hands: Array, chin: Vector3, sideways: Vector3, dt: float) -> void:
	if steer_hand >= 0:
		var hand: Dictionary = hands[steer_hand] if steer_hand < hands.size() else {}
		if not hand.has(steer_finger):
			# A short dropout keeps the head where it is; a longer one lets go.
			_steer_lost += dt
			if _steer_lost >= LOST_GRACE_S:
				release_steer()
			return
		_steer_lost = 0.0
		if absf((hand[steer_finger] - chin).dot(sideways)) > STEER_PLANE_M:
			release_steer()
			return
		steer_point = hand[steer_finger]
		return
	# Not steering: the fingertip nearest the chin, inside the zone, has to hold still.
	var candidate := ""
	var point := Vector3.ZERO
	var nearest := CHIN_RADIUS_M
	for index in hands.size():
		for finger: String in CHIN_FINGERS:
			if hands[index].has(finger) and hands[index][finger].distance_to(chin) <= nearest:
				nearest = hands[index][finger].distance_to(chin)
				candidate = "%d:%s" % [index, finger]
				point = hands[index][finger]
	if candidate.is_empty():
		_steer_candidate = ""
		_steer_hold = 0.0
		return
	if candidate != _steer_candidate or point.distance_to(_steer_start) > STILL_M:
		_steer_candidate = candidate
		_steer_start = point
		_steer_hold = 0.0
	_steer_hold += dt
	if _steer_hold >= HOLD_S:
		steer_hand = int(candidate.get_slice(":", 0))
		steer_finger = candidate.get_slice(":", 1)
		steer_point = point

func _chin_tip(hand: Dictionary, chin: Vector3) -> Vector3:
	## The hand's chin fingertip nearest the chin, or INF when none is tracked.
	var tip := Vector3.INF
	for finger: String in CHIN_FINGERS:
		if hand.has(finger) and hand[finger].distance_to(chin) < tip.distance_to(chin):
			tip = hand[finger]
	return tip

func _matches(hands: Array, role: int, forehead: Vector3, chin: Vector3, factor: float) -> bool:
	return hands.size() == 2 and hands[role].has("palm") \
		and hands[role].palm.distance_to(forehead) <= FOREHEAD_RADIUS_M * factor \
		and _chin_tip(hands[1 - role], chin).distance_to(chin) <= CHIN_RADIUS_M * factor
