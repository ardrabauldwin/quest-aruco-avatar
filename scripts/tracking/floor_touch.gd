class_name NaretFloorTouch
extends Node
## Measures the real floor with hand tracking: the trainee rests an index
## fingertip on the floor and holds it still. The room scan and the headset's
## floor level can be several centimetres off; a fingertip on the floor is not.

signal measured(floor_y: float)
signal failed

## The fingertip must rest this long without leaving a STILL_M ball.
const HOLD_S := 1.5
const STILL_M := 0.01
## A hand on a knee or on the wrist menu is not on the floor.
const BELOW_HEAD_M := 0.5
const TIMEOUT_S := 30.0

var active := false
var _origin: XROrigin3D
var _head: Node3D
var _elapsed := 0.0
var _samples: Array = [[], []]

func start(origin: XROrigin3D, head: Node3D) -> void:
	_origin = origin
	_head = head
	_elapsed = 0.0
	_samples = [[], []]
	active = true

func _process(delta: float) -> void:
	if not active or _origin == null or _head == null:
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_S:
		active = false
		failed.emit()
		return
	for index in 2:
		var hand := NaretXRInteraction.hand_tracker(index)
		var tip: Variant = NaretXRInteraction.tracked_joint(hand, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP) if hand else null
		if tip == null:
			_samples[index].clear()
			continue
		var position: Vector3 = _origin.global_transform * (tip as Transform3D).origin
		var radius := hand.get_hand_joint_radius(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
		var floor_y := feed(_samples[index], position, radius, _elapsed, _head.global_position.y)
		if is_finite(floor_y):
			active = false
			print("NARET_FLOOR_TOUCH hand=%d tip=%s radius=%.4f floor_y=%.3f" % [index, position, radius, floor_y])
			measured.emit(floor_y)
			return

static func feed(samples: Array, position: Vector3, radius: float, now_s: float, head_y: float) -> float:
	## Pure so the acceptance rule is testable without a headset: NAN until the
	## fingertip has rested HOLD_S, then the floor height under it. The tip joint
	## sits on the finger's axis, one joint radius above the surface it touches.
	if head_y - position.y < BELOW_HEAD_M:
		samples.clear()
		return NAN
	samples.append({"t": now_s, "p": position})
	# The hold restarts after the newest sample that lies outside the still ball.
	for i in range(samples.size() - 1, -1, -1):
		if (samples[i].p as Vector3).distance_to(position) > STILL_M:
			for _drop in i + 1:
				samples.pop_front()
			break
	if now_s - float(samples[0].t) < HOLD_S:
		return NAN
	var sum := 0.0
	for sample: Dictionary in samples:
		sum += (sample.p as Vector3).y
	return sum / samples.size() - radius
