extends RefCounted
## Loaded by preload (no class_name): the headless test runner has no global class cache.
## Physical evidence for the response check (12 Nov 2026): a tracked palm at one of the
## patient's shoulders. "He is not responding" is accepted only with this evidence, so a
## spoken claim alone can never close the step. Zones are boxes around the sternum of the
## calibrated mannequin, not around the drawn avatar: the trainee reaches for the real
## shoulder, and the tolerance absorbs the avatar's alignment error.
##
## Deliberately not checked: grip, fingers, which hand, and whether the shoulder moved.
## Hand tracking against the mannequin surface is too noisy for that; a motion rule would
## reject honest trainees. Movement is only reported as a hint ("shake him firmly").
##
## Coordinates are mannequin-local metres with the sternum at the origin: +X to the
## one side, +Y up, -Z toward the head (NaretMannequin: the forehead lies at z = -0.36).

## Zone centre of each shoulder relative to the compression point (adult Resusci Anne:
## shoulder joint about 18 cm beside the midline and 13 cm toward the head, its top a
## little below the chest apex).
const CENTRE_X_M := 0.18
const CENTRE_Z_M := -0.13
const CENTRE_Y_M := -0.02
## Half extents: 10 to 26 cm beside the midline (off the chest and the neck, onto the
## upper arm at most), 5 to 21 cm above the sternum point (below the ear).
const HALF_X_M := 0.08
const HALF_Z_M := 0.08
## Fingers slide under a gripped shoulder; the palm joint sits a few centimetres above it.
const BELOW_M := 0.06
const ABOVE_M := 0.10
## A palm inside a zone for this long in total counts. Tracking may drop for GRACE_S
## without losing the count; being away for longer than AWAY_RESET_S starts over.
const HOLD_S := 0.8
const GRACE_S := 0.25
const AWAY_RESET_S := 1.0
## The report must follow within this time, else the instructor asks for the shoulders again.
## 45 s, not 15 (headset 13 Nov 2026): 10 s after a touch without a report the instructor
## asks "does he respond?"; the trainee's "yes, he is not responding" then arrived after
## the 15 s were over and was refused, and the question was repeated.
const EVIDENCE_S := 45.0
## Palm travel inside the zone that counts as shaking (hint only, never a gate).
const SHAKE_TRAVEL_M := 0.06

var active := false
var touched := false
var _clock := 0.0
var _last_touch := -1.0e9
var _inside := [0.0, 0.0]
var _away := [0.0, 0.0]
var _travel := [0.0, 0.0]
var _last_pos: Array = [null, null]
var _touched_side := -1

static func zone_centre(side: int) -> Vector3:
	## Side 0 is the patient's right (negative X), side 1 the left.
	return Vector3(CENTRE_X_M if side == 1 else -CENTRE_X_M, CENTRE_Y_M, CENTRE_Z_M)

static func zone_of(local: Vector3) -> int:
	## 0 or 1 for a point inside a shoulder box, -1 outside both.
	for side in 2:
		var d := local - zone_centre(side)
		if absf(d.x) <= HALF_X_M and absf(d.z) <= HALF_Z_M and d.y >= -BELOW_M and d.y <= ABOVE_M:
			return side
	return -1

func reset() -> void:
	touched = false
	_clock = 0.0
	_last_touch = -1.0e9
	_inside = [0.0, 0.0]
	_away = [0.0, 0.0]
	_travel = [0.0, 0.0]
	_last_pos = [null, null]
	_touched_side = -1

func observe(palms: Array, delta: float) -> bool:
	## `palms`: one entry per hand, a mannequin-local Vector3 or null while untracked.
	## Returns true in the frame a hand first completes the hold.
	var dt := clampf(delta, 0.0, 0.05)
	_clock += dt
	if not active:
		return false
	var completed := false
	for hand in mini(palms.size(), 2):
		var palm: Variant = palms[hand]
		var side := zone_of(palm) if palm is Vector3 else -1
		if side >= 0:
			_away[hand] = 0.0
			if _last_pos[hand] is Vector3:
				_travel[hand] += (palm as Vector3).distance_to(_last_pos[hand])
			_last_pos[hand] = palm
			var before: float = _inside[hand]
			_inside[hand] = before + dt
			if _inside[hand] >= HOLD_S:
				_last_touch = _clock
				_touched_side = side
				if not touched:
					touched = true
					completed = true
				elif before < HOLD_S:
					completed = true
		else:
			_away[hand] += dt
			if _away[hand] > GRACE_S:
				_last_pos[hand] = null
			if _away[hand] > AWAY_RESET_S:
				_inside[hand] = 0.0
				_travel[hand] = 0.0
	return completed

func evidence_recent() -> bool:
	## True while a completed shoulder hold is younger than EVIDENCE_S.
	return touched and _clock - _last_touch <= EVIDENCE_S

func shaken() -> bool:
	## Whether the hand that completed the hold also moved while there (hint only).
	return touched and (_travel[0] >= SHAKE_TRAVEL_M or _travel[1] >= SHAKE_TRAVEL_M)

func touched_side() -> int:
	return _touched_side
