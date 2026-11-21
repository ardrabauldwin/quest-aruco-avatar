extends RefCounted
## Physical evidence for the breathing check (12 Nov 2026): the trainee's head brought
## down to the patient's face, which is what look, listen and feel physically is. The
## headset pose is the one thing the Quest always tracks, so this gate never drops out.
## "He is not breathing normally" is accepted only with this evidence.
##
## One box around the mouth landmark, in mannequin-local metres (-Z toward the head, +Y
## up). The trainee kneels beside the patient and leans in from the side, so the box is
## wide sideways. Kneeling upright (60 to 80 cm up) and hovering over the chest (more
## than 20 cm toward the feet) stay outside on purpose: that is the posture of a trainee
## claiming the check without doing it. Head direction is not checked.
## Loaded by preload (no class_name): the headless test runner has no global class cache.

const HALF_X_M := 0.30
const TOWARD_CHEST_M := 0.20   # +Z, toward the feet
const TOWARD_CROWN_M := 0.15   # -Z, past the face
const ABOVE_MIN_M := 0.05
const ABOVE_MAX_M := 0.40
## Time at the face that counts, in total, so lifting the head for a moment is not a reset.
const HOLD_S := 3.0
## The report must follow within this time. 30 s, not 15 (headset 13 Nov 2026: the head
## was at the face at 13:12:04, the report arrived at 13:12:29, 25 s later, and was refused).
const EVIDENCE_S := 30.0
## ERC 2025: look, listen and feel for no more than 10 s. Hint only, never a refusal.
const LONG_S := 10.0

var active := false
var checked := false
var long_hinted := false
var _clock := 0.0
var _last_check := -1.0e9
var _at_face := 0.0

static func inside(offset: Vector3) -> bool:
	## `offset` is the headset position relative to the mouth, mannequin-local.
	return absf(offset.x) <= HALF_X_M and offset.z <= TOWARD_CHEST_M and offset.z >= -TOWARD_CROWN_M \
		and offset.y >= ABOVE_MIN_M and offset.y <= ABOVE_MAX_M

func reset() -> void:
	checked = false
	long_hinted = false
	_clock = 0.0
	_last_check = -1.0e9
	_at_face = 0.0

func observe(offset: Variant, delta: float) -> bool:
	## `offset`: headset position relative to the mouth, or null without a pose.
	## Returns true in the frame the hold first completes.
	var dt := clampf(delta, 0.0, 0.05)
	_clock += dt
	if not active or not (offset is Vector3) or not inside(offset):
		return false
	var before := _at_face
	_at_face += dt
	if _at_face >= HOLD_S:
		_last_check = _clock
		if not checked:
			checked = true
			return true
		return before < HOLD_S
	return false

func too_long() -> bool:
	## True once, when the head has been at the face for more than LONG_S in total.
	if long_hinted or _at_face <= LONG_S:
		return false
	long_hinted = true
	return true

func evidence_recent() -> bool:
	return checked and _clock - _last_check <= EVIDENCE_S

func seconds_at_face() -> float:
	return _at_face
