class_name NaretChestTouch
extends Node
## Measures the real mannequin's chest height with hand tracking, so no marker
## has to lie on the compression point. The trainee lays one hand flat, palm
## down and without pressure, on the compression point and holds it still.
## Every joint resting on the surface gives an estimate (joint height minus
## joint radius); the median over joints and time ignores single jumping joints.

signal measured(surface_y: float)
signal failed

const HOLD_S := 2.0
const STILL_M := 0.01
## Joints of a flat hand that touch the chest; their spread rejects a bent hand.
const MIN_JOINTS := 6
const SPREAD_M := 0.025 # 1.5 -> 2.5 cm (2026-10-29): a flat hand on a curved chest is not a plane
## Palm normal must point this steeply down, the palm this close to the sternum.
const PALM_DOWN := 0.7
const NEAR_STERNUM_M := 0.2
const TIMEOUT_S := 30.0
const JOINTS := [XRHandTracker.HAND_JOINT_PALM,
	XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
	XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP]

var active := false
var _origin: XROrigin3D
var _sternum: Callable
var _elapsed := 0.0
var _samples: Array = [[], []]
## Once-per-second diagnostic while measuring (headset review 2026-10-29: a silent
## 30 s wait gave no clue why a hand on the chest was not accepted).
var _log_s := 0.0

func start(origin: XROrigin3D, sternum_position: Callable) -> void:
	## `sternum_position` returns the virtual sternum in world space; only a hand
	## near it counts, so a hand resting anywhere else never measures the chest.
	_origin = origin
	_sternum = sternum_position
	_elapsed = 0.0
	_samples = [[], []]
	_log_s = 0.0
	active = true
	print("NARET_CHEST_TOUCH start sternum=%s" % str(sternum_position.call()))

func _process(delta: float) -> void:
	if not active or _origin == null:
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_S:
		active = false
		print("NARET_CHEST_TOUCH timeout")
		failed.emit()
		return
	var sternum: Vector3 = _sternum.call()
	_log_s += delta
	var report := _log_s >= 1.0
	if report:
		_log_s = 0.0
	var reasons := []
	for index in 2:
		var hand := NaretXRInteraction.hand_tracker(index)
		var palm: Variant = NaretXRInteraction.tracked_joint(hand, XRHandTracker.HAND_JOINT_PALM, true) if hand else null
		if palm == null:
			_samples[index].clear()
			reasons.append("h%d:no_palm" % index)
			continue
		var palm_world: Transform3D = _origin.global_transform * (palm as Transform3D)
		# +Z is the palm surface on Godot's OpenXR hands (see hand_menu.gd).
		var flat := Vector2(palm_world.origin.x - sternum.x, palm_world.origin.z - sternum.z)
		var down := palm_world.basis.z.normalized().y
		if down > -PALM_DOWN or flat.length() > NEAR_STERNUM_M:
			_samples[index].clear()
			reasons.append("h%d:palm_down=%.2f dist=%.2f" % [index, down, flat.length()])
			continue
		var estimates := PackedFloat32Array()
		for joint: int in JOINTS:
			var pose: Variant = NaretXRInteraction.tracked_joint(hand, joint)
			if pose != null:
				estimates.append((_origin.global_transform * (pose as Transform3D).origin).y - hand.get_hand_joint_radius(joint))
		var low := INF
		var high := -INF
		for value in estimates:
			low = minf(low, value)
			high = maxf(high, value)
		reasons.append("h%d:joints=%d spread_cm=%.1f held_s=%.1f y=%.2f" % [index, estimates.size(), (high - low) * 100.0 if estimates.size() > 0 else 0.0, (_elapsed - float(_samples[index][0].t)) if not _samples[index].is_empty() else 0.0, palm_world.origin.y])
		var surface_y := feed(_samples[index], estimates, palm_world.origin, _elapsed)
		if report:
			print("NARET_CHEST_TOUCH t=%.0f %s" % [_elapsed, " | ".join(reasons)])
			report = false
		if is_finite(surface_y):
			active = false
			print("NARET_CHEST_TOUCH hand=%d joints=%d surface_y=%.3f" % [index, estimates.size(), surface_y])
			measured.emit(surface_y)
			return

static func median(values: PackedFloat32Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	return sorted[middle] if sorted.size() % 2 == 1 else (sorted[middle - 1] + sorted[middle]) * 0.5

static func feed(samples: Array, estimates: PackedFloat32Array, palm: Vector3, now_s: float) -> float:
	## Pure so the acceptance rule is testable without a headset: NAN until a flat
	## hand has rested HOLD_S, then the median surface height under it.
	if estimates.size() < MIN_JOINTS:
		samples.clear()
		return NAN
	var low := estimates[0]
	var high := estimates[0]
	for value in estimates:
		low = minf(low, value)
		high = maxf(high, value)
	if high - low > SPREAD_M:
		samples.clear()
		return NAN
	samples.append({"t": now_s, "p": palm, "y": median(estimates)})
	# The hold restarts after the newest sample that lies outside the still ball.
	for i in range(samples.size() - 1, -1, -1):
		if (samples[i].p as Vector3).distance_to(palm) > STILL_M:
			for _drop in i + 1:
				samples.pop_front()
			break
	if now_s - float(samples[0].t) < HOLD_S:
		return NAN
	var heights := PackedFloat32Array()
	for sample: Dictionary in samples:
		heights.append(sample.y)
	return median(heights)
