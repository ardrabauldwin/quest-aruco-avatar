extends RefCounted
## Average a stable local-floor window once per app session. Keep the result in
## tracking-reference coordinates so recentering transforms the same plane.
const WINDOW_MS := 1000
const MIN_SAMPLES := 10
const MAX_SPREAD_M := 0.01
const MAX_SAMPLE_GAP_MS := 250
var ready := false
var _point := Vector3.ZERO
var _points: Array[Vector3] = []
var _started_ms := -1
var _last_ms := -1

func height_world(sample_y: float, tracking_to_world: Transform3D, now_ms: int = -1) -> float:
	if not tracking_to_world.is_finite() or absf(tracking_to_world.basis.determinant()) < 0.000001:
		_clear_window()
		return NAN
	if ready:
		return (tracking_to_world * _point).y
	if not is_finite(sample_y):
		_clear_window()
		return NAN
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if now == _last_ms:
		return NAN # Multiple callbacks in one millisecond are not new timed samples.
	if _last_ms >= 0 and (now < _last_ms or now - _last_ms > MAX_SAMPLE_GAP_MS):
		_clear_window()
	var world_point := tracking_to_world.origin
	world_point.y = sample_y
	var point := tracking_to_world.affine_inverse() * world_point
	var lowest := point.y
	var highest := point.y
	for previous in _points:
		lowest = minf(lowest, previous.y)
		highest = maxf(highest, previous.y)
	if highest - lowest > MAX_SPREAD_M:
		_clear_window() # Start a new window rather than average an unstable jump.
	if _points.is_empty():
		_started_ms = now
	_points.append(point)
	_last_ms = now
	if now - _started_ms < WINDOW_MS or _points.size() < MIN_SAMPLES:
		return NAN
	_point = Vector3.ZERO
	for previous in _points:
		_point += previous
	_point /= _points.size()
	ready = true
	_points.clear()
	return (tracking_to_world * _point).y

func _clear_window() -> void:
	_points.clear()
	_started_ms = -1
	_last_ms = -1
