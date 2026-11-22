class_name NaretCprDetector
extends RefCounted
## Compression detector without hard distance thresholds, independent of body size.
##
## Several height signals along the chest normal (relative to the sternum) are
## band-passed around the CPR rhythm and each divided by its own running amplitude:
## body-tracked wrists and forearms, both tracked palms, the head. A hand that is
## occluded or jumps only weakens one channel. One stroke per oscillation of the
## combined signal (hysteresis). A run of strokes only counts once the rhythm is
## confirmed (autocorrelation at 60-180/min, hands on the chest); it then counts
## from its start. Depth is the raw up-down travel of the wrists in metres.
##
## Validated on recorded takes (tools/replay_detector.gd, takes in build/takes):
## 50 of 50 and 32 of 32 strokes in two CPR takes (the old palm detector found 0
## and 20), none in three takes without CPR. The first stroke counts about 4 s after
## the hands start pressing; the strokes before it are counted retroactively.

const CHANNELS := {"wrists": 1.0, "forearms": 1.0, "palm_l": 0.5, "palm_r": 0.5, "head": 0.5}
const CENTER_HZ := 1.8
const Q := 0.7
const HYSTERESIS := 0.35 # in units of the channel's own running amplitude
const MIN_INTERVAL_S := 0.3 # faster than 200/min is noise
const MAX_INTERVAL_S := 1.5 # a longer gap ends the run (pause, ventilation)
const CONFIRM_P := 0.4
const WINDOW_S := 3.0
const QUIET_M := 0.002 # a channel moving less than this carries no rhythm
## Frames arrive unevenly (8-30 ms apart on the Quest 3). Filters, the amplitude
## memory and the rhythm search all count in samples, so the inputs are first
## resampled onto a fixed grid; a gap longer than MAX_GAP_S is not bridged.
const RATE_HZ := 60.0
const MAX_GAP_S := 0.5
## Which hand lies on top (for channel weighting): the upper palm rests about a hand's
## thickness (2-3 cm) above the lower one along the chest normal. The palm height
## difference is smoothed over TOP_TAU_S (one stroke moves both hands alike) and
## switches sides only past TOP_HYSTERESIS_M. Without both palms for TOP_STALE_S the
## answer is dropped.
const TOP_TAU_S := 1.0
const TOP_HYSTERESIS_M := 0.01
const TOP_STALE_S := 2.0

class Biquad:
	## RBJ band-pass (constant 0 dB peak gain), Direct Form I.
	var b0 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var primed := false

	func design(f0: float, q: float, fs: float) -> void:
		var w := TAU * f0 / fs
		var alpha := sin(w) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w) / a0
		a2 = (1.0 - alpha) / a0

	func step(x: float) -> float:
		if not primed:
			x1 = x
			x2 = x
			primed = true
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y

var count := 0
## Confidence that rhythmic compressions are happening (0..1).
var probability := 0.0
var rate_bpm := 0.0
var last_depth_m := 0.0
## "left", "right" or "" (unknown): the hand on top, from both tracked palms.
var top_hand := ""
## Smoothed palm height difference left - right in metres (positive: left higher).
var top_diff_m := 0.0
var _top_t := -1.0
var _fs := RATE_HZ
var _prev_t := -1.0
var _prev := {}
var _prev_depth: Variant = null
var _next_t := 0.0
var _filters := {}
var _rms := {}
var _history := PackedFloat32Array()
var _tick := 0
var _down := false
var _last_stroke_t := -10.0
var _low := INF
var _high := -INF
var _run: Array[Dictionary] = []
var _confirmed := false
var _streak := 0

func _init() -> void:
	reset()

func reset() -> void:
	count = 0
	probability = 0.0
	rate_bpm = 0.0
	top_hand = ""
	top_diff_m = 0.0
	_top_t = -1.0
	_history.clear()
	_down = false
	_last_stroke_t = -10.0
	_run.clear()
	_confirmed = false
	_streak = 0
	_low = INF
	_high = -INF
	_prev_t = -1.0
	_prev = {}
	_prev_depth = null
	for channel in CHANNELS:
		var stages := [Biquad.new(), Biquad.new()]
		for stage in stages:
			stage.design(CENTER_HZ, Q, _fs)
		_filters[channel] = stages
		_rms[channel] = 0.0

func step(t: float, _dt: float, channels: Dictionary, on_chest: bool, depth_signal: Variant = null) -> Array[Dictionary]:
	## channels: name -> height in metres (missing = not tracked). Returns the strokes
	## counted in this frame ({t, depth_m, rate_bpm, p}); several when a run is confirmed.
	## The frame is resampled onto the RATE_HZ grid (linear between this frame and the
	## last), so _dt is not needed; it stays in the signature for the callers.
	var counted: Array[Dictionary] = []
	_update_top_hand(t, channels)
	if _prev_t < 0.0 or t - _prev_t > MAX_GAP_S:
		_prev_t = t
		_prev = channels
		_prev_depth = depth_signal
		_next_t = t
	if t < _prev_t:
		return counted
	while _next_t <= t:
		var w := 0.0 if t <= _prev_t else (_next_t - _prev_t) / (t - _prev_t)
		var mixed := {}
		for channel in channels:
			mixed[channel] = lerpf(float(_prev[channel]), float(channels[channel]), w) if _prev.has(channel) else float(channels[channel])
		var depth: Variant = depth_signal
		if depth_signal != null and _prev_depth != null:
			depth = lerpf(float(_prev_depth), float(depth_signal), w)
		counted.append_array(_sample(_next_t, mixed, on_chest, depth))
		_next_t += 1.0 / RATE_HZ
	_prev_t = t
	_prev = channels
	_prev_depth = depth_signal
	return counted

func _sample(t: float, channels: Dictionary, on_chest: bool, depth_signal: Variant) -> Array[Dictionary]:
	## One step on the fixed grid.
	var z := 0.0
	var weights := 0.0
	for channel in CHANNELS:
		if not channels.has(channel):
			continue
		var stages: Array = _filters[channel]
		var y: float = stages[1].step(stages[0].step(float(channels[channel])))
		_rms[channel] = sqrt(0.98 * _rms[channel] * _rms[channel] + 0.02 * y * y)
		if _rms[channel] > QUIET_M:
			z += CHANNELS[channel] * y / _rms[channel]
			weights += CHANNELS[channel]
	z = z / weights if weights > 0.0 else 0.0
	_history.append(z)
	var keep := int(WINDOW_S * _fs)
	if _history.size() > keep:
		_history = _history.slice(_history.size() - keep)
	_tick += 1
	if _tick % 6 == 0:
		probability = 0.53 * probability + 0.47 * (_rhythm() if on_chest else 0.0)
	if depth_signal != null:
		_low = minf(_low, float(depth_signal))
		_high = maxf(_high, float(depth_signal))
	var counted: Array[Dictionary] = []
	if not _down and z < -HYSTERESIS:
		_down = true
	elif _down and z > HYSTERESIS:
		_down = false
		var interval := t - _last_stroke_t
		if interval > MAX_INTERVAL_S:
			_run.clear()
			_confirmed = false
			_streak = 0
		if on_chest and interval >= MIN_INTERVAL_S:
			var stroke := {"t": t, "depth_m": _high - _low if _high >= _low else 0.0,
				"rate_bpm": 60.0 / interval if interval < MAX_INTERVAL_S else 0.0, "p": probability}
			_streak = _streak + 1 if probability >= CONFIRM_P else 0
			if _confirmed:
				counted.append(stroke)
			else:
				_run.append(stroke)
				if _streak >= 2:
					_confirmed = true
					counted.append_array(_run)
					_run.clear()
		_last_stroke_t = t
		_low = INF
		_high = -INF
	for stroke in counted:
		count += 1
		last_depth_m = stroke.depth_m
		if stroke.rate_bpm > 0.0:
			rate_bpm = stroke.rate_bpm
	return counted

static func measure(sternum: Transform3D, palms: Array, wrists: Array, forearms: Array, head_height: float) -> Dictionary:
	## Inputs for step(): heights along the chest normal relative to the sternum.
	## palms: [left, right] tracked palm positions or null; wrists/forearms: body-tracked
	## [left, right] or empty without body tracking. All in one space (world or tracking).
	var up := sternum.basis.y.normalized()
	var height := func(p: Vector3) -> float: return (p - sternum.origin).dot(up)
	var channels := {"head": head_height}
	if wrists.size() == 2 and wrists[0] != null and wrists[1] != null:
		channels["wrists"] = (height.call(wrists[0]) + height.call(wrists[1])) / 2.0
	if forearms.size() == 2 and forearms[0] != null and forearms[1] != null:
		channels["forearms"] = (height.call(forearms[0]) + height.call(forearms[1])) / 2.0
	for i in 2:
		if palms[i] != null:
			channels["palm_l" if i == 0 else "palm_r"] = height.call(palms[i])
	# Hands on the chest: a palm or a wrist within 15 cm sideways, -10..30 cm above.
	var on_chest := false
	for p in palms + wrists:
		if p != null:
			var offset: Vector3 = p - sternum.origin
			var above := offset.dot(up)
			on_chest = on_chest or ((offset - up * above).length() < 0.15 and above > -0.10 and above < 0.30)
	return {"channels": channels, "on_chest": on_chest, "depth": channels.get("wrists")}

func _update_top_hand(t: float, channels: Dictionary) -> void:
	if not (channels.has("palm_l") and channels.has("palm_r")):
		if _top_t >= 0.0 and t - _top_t > TOP_STALE_S:
			top_hand = ""
			_top_t = -1.0
		return
	var diff := float(channels["palm_l"]) - float(channels["palm_r"])
	if _top_t < 0.0 or t - _top_t > TOP_STALE_S:
		top_diff_m = diff
	elif t > _top_t:
		top_diff_m = lerpf(top_diff_m, diff, 1.0 - exp(-(t - _top_t) / TOP_TAU_S))
	_top_t = t
	if top_diff_m > TOP_HYSTERESIS_M:
		top_hand = "left"
	elif top_diff_m < -TOP_HYSTERESIS_M:
		top_hand = "right"

func confirmed() -> bool:
	## True while a run is confirmed: every further stroke counts right away.
	return _confirmed

func _rhythm() -> float:
	## Highest normalised autocorrelation for periods of 0.33-1 s (60-180/min).
	if _history.size() < int(2.0 * _fs):
		return 0.0
	var mean := 0.0
	for v in _history:
		mean += v
	mean /= _history.size()
	var x := PackedFloat32Array()
	x.resize(_history.size())
	var energy := 1e-9
	for i in _history.size():
		x[i] = _history[i] - mean
		energy += x[i] * x[i]
	var best := 0.0
	for lag in range(int(_fs / 3.0), int(_fs)):
		var sum := 0.0
		for i in range(lag, x.size()):
			sum += x[i] * x[i - lag]
		best = maxf(best, sum / energy)
	return maxf(0.0, best)
