class_name NaretHeadTiltGesture
extends RefCounted
## Head tilt, chin lift: one hand at the forehead and the other at the chin together.
## Drives the avatar's head-tilt animation and sets the airway flag of the breathing step.
##
## 12 Nov 2026: loosened to presence only. The earlier version needed a still hold and
## then a coordinated motion (forehead back, chin up) and never fired in any headset
## session that reached the breathing step (0 of 10). Hands at the patient's face are
## often half hidden from the headset, so the rule is now: both landmarks covered, by
## either hand in either role, for HOLD_S in total, with a short grace for tracking loss.
## No angle, no lift height, no technique score.
const FOREHEAD_RADIUS_M := 0.08
const CHIN_RADIUS_M := 0.07
const HOLD_S := 0.5
const LOST_GRACE_S := 0.25
var active := false
var state := "waiting"
var _forehead_hand := -1
var _hold := 0.0
var _lost := 0.0

func reset() -> void:
	active = false
	state = "waiting"
	_forehead_hand = -1
	_hold = 0.0
	_lost = 0.0

func observe(hands: Array, forehead: Vector3, chin: Vector3, _up: Vector3, _toward_head: Vector3, delta: float) -> bool:
	# Caller supplies fresh tracked palm/index positions, or {} for an invalid hand.
	var dt := clampf(delta, 0.0, 0.05)
	var role := _forehead_hand
	if role < 0 or not _matches(hands, role, forehead, chin, 1.4 if active else 1.0):
		role = -1
		for index in 2:
			if _matches(hands, index, forehead, chin, 1.4 if active else 1.0):
				role = index
				break
	if role < 0:
		_lost += dt
		# A short dropout keeps the hold and an existing animation; a longer one resets.
		if _lost >= LOST_GRACE_S:
			reset()
		return active
	_lost = 0.0
	_forehead_hand = role
	if active:
		return true
	state = "positioning"
	_hold += dt
	if _hold >= HOLD_S:
		active = true
		state = "gesture_detected"
	return active

func _matches(hands: Array, role: int, forehead: Vector3, chin: Vector3, factor: float) -> bool:
	if hands.size() != 2 or hands[role].is_empty() or hands[1 - role].is_empty():
		return false
	var other: Dictionary = hands[1 - role]
	var chin_near: bool = other.finger.distance_to(chin) <= CHIN_RADIUS_M * factor \
		or other.palm.distance_to(chin) <= CHIN_RADIUS_M * factor
	return hands[role].palm.distance_to(forehead) <= FOREHEAD_RADIUS_M * factor and chin_near
