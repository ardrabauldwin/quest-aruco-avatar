class_name OneEuroFilter
extends RefCounted
## One Euro Filter -- Casiez, Roussel & Vogel, CHI 2012.  https://gery.casiez.net/1euro/
##
## An ADAPTIVE low-pass filter for noisy tracking signals. It solves the usual
## "smooth vs. laggy" trade-off automatically:
##   - signal slow / still  -> heavy smoothing  -> jitter removed
##   - signal moving fast    -> light smoothing  -> no lag, follows the motion
##
## Two knobs:
##   min_cutoff (Hz) : lower  -> smoother when still (more jitter removed), slightly more lag
##   beta            : higher -> reacts faster to quick motion (less lag when moving)
##
## Tuning recipe: set beta = 0, lower min_cutoff until the still jitter is gone; then raise beta
## until fast motion no longer feels laggy. Good starts: min_cutoff ~1.0, beta ~0.5.
##
## Scalar use:
##   var f = OneEuroFilter.new(1.0, 0.5)
##   var y = f.filter(x, delta)
## Vector3 / Quaternion helpers are the inner classes OneEuroFilter.Vec3 and OneEuroFilter.Rotation.

var min_cutoff: float
var beta: float
var d_cutoff: float

var _x_prev := 0.0
var _dx_prev := 0.0
var _started := false

func _init(p_min_cutoff := 1.0, p_beta := 0.0, p_d_cutoff := 1.0) -> void:
	min_cutoff = p_min_cutoff
	beta = p_beta
	d_cutoff = p_d_cutoff

# Smoothing factor from a cutoff frequency and the time step (TAU = 2*PI).
static func _smoothing_alpha(cutoff: float, dt: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / dt)

## Feed a new sample `x`, measured `dt` seconds after the previous one. Returns the filtered value.
func filter(x: float, dt: float) -> float:
	if dt <= 0.0:
		return x
	if not _started:
		_x_prev = x
		_dx_prev = 0.0
		_started = true
		return x
	# 1) estimate the derivative and low-pass it
	var dx := (x - _x_prev) / dt
	var a_d := _smoothing_alpha(d_cutoff, dt)
	var dx_hat := a_d * dx + (1.0 - a_d) * _dx_prev
	# 2) raise the cutoff with speed (fast motion -> less smoothing -> less lag)
	var cutoff := min_cutoff + beta * absf(dx_hat)
	# 3) low-pass the signal with that adaptive cutoff
	var a := _smoothing_alpha(cutoff, dt)
	var x_hat := a * x + (1.0 - a) * _x_prev
	_x_prev = x_hat
	_dx_prev = dx_hat
	return x_hat

func reset() -> void:
	_started = false


## Filters a Vector3 -- three independent One Euro filters (use for position).
class Vec3:
	extends RefCounted
	var _fx: OneEuroFilter
	var _fy: OneEuroFilter
	var _fz: OneEuroFilter
	func _init(min_cutoff := 1.0, beta := 0.0, d_cutoff := 1.0) -> void:
		_fx = OneEuroFilter.new(min_cutoff, beta, d_cutoff)
		_fy = OneEuroFilter.new(min_cutoff, beta, d_cutoff)
		_fz = OneEuroFilter.new(min_cutoff, beta, d_cutoff)
	func filter(v: Vector3, dt: float) -> Vector3:
		return Vector3(_fx.filter(v.x, dt), _fy.filter(v.y, dt), _fz.filter(v.z, dt))
	func reset() -> void:
		_fx.reset(); _fy.reset(); _fz.reset()


## Filters a rotation (Quaternion) via adaptive slerp: the blend factor grows with angular speed,
## so slow rotations are smoothed hard and fast ones follow tightly (use for orientation).
class Rotation:
	extends RefCounted
	var min_cutoff: float
	var beta: float
	var _prev := Quaternion.IDENTITY
	var _started := false
	func _init(p_min_cutoff := 1.0, p_beta := 0.0) -> void:
		min_cutoff = p_min_cutoff
		beta = p_beta
	func filter(q: Quaternion, dt: float) -> Quaternion:
		if dt <= 0.0:
			return q
		if not _started:
			_prev = q
			_started = true
			return q
		# take the shortest arc (q and -q are the same rotation)
		if _prev.dot(q) < 0.0:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)
		var speed := _prev.angle_to(q) / dt          # rad/s
		var cutoff := min_cutoff + beta * speed
		var tau := 1.0 / (TAU * cutoff)
		var a := 1.0 / (1.0 + tau / dt)
		_prev = _prev.slerp(q, a).normalized()
		return _prev
	func reset() -> void:
		_started = false
