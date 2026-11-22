class_name NaretHeadScan
extends RefCounted
## Safety gate (team to-do, issue #1, 2. Sicherheit prüfen): "head movement to the left and
## to the right (surroundings scanned)". The view direction at the start of the step is the
## reference; the head has to turn at least TURN_RAD to each side of it, in any order.

## 35 -> 20 degrees (19 Nov 2026, headset: the left/right check missed natural head turns).
const TURN_RAD := deg_to_rad(20.0)

var left := false
var right := false
var _reference := NAN

func reset() -> void:
	left = false
	right = false
	_reference = NAN

func done() -> bool:
	return left and right

## forward: the headset's view direction (world). Returns true when this call completed the scan.
func update(forward: Vector3) -> bool:
	var flat := Vector2(forward.x, forward.z)
	if flat.length_squared() < 0.0001: return false
	var yaw := atan2(-flat.x, -flat.y) # 0 = looking along -Z; positive = turned left
	if is_nan(_reference):
		_reference = yaw
		return false
	var was := done()
	var turn := wrapf(yaw - _reference, -PI, PI)
	if turn > TURN_RAD: left = true
	if turn < -TURN_RAD: right = true
	return done() and not was
