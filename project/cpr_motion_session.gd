extends RefCounted
## Sensor-free practice state. Excursion is hand travel, not measured chest depth.
signal beat_requested

var target_bpm := 110.0
var breathing_duration_s := 5.0
var minimum_travel_m := 0.050  # Estimated hand excursion, not measured chest depth.
var slow_stroke_interval_s := 0.60  # 100 BPM; feedback only.
var fast_stroke_interval_s := 0.50  # 120 BPM; feedback only.
var return_tolerance_m := 0.010
## A press whose recoil stops short of the old top still counts once the hand clearly starts
## the next press, provided it recovered at least this fraction of the excursion and this
## many metres. The recoil peak then becomes the new top, so a resting height that drifts
## lower over a cycle (leaning in, an overshot first press) cannot silently stop the count.
var recoil_fraction := 0.5
var recoil_minimum_m := 0.015
## A real press keeps the hand more than 4 mm below the top for ~0.4 s at 110 BPM. A stroke
## that spends less than this below the top is a one-frame tracking spike and is discarded.
var min_press_time_s := 0.04
## Dips shallower than this are hand wobble, not an attempted compression: on the headset
## (2026-09-15 log) 0.6-1.5 cm dips at 0.1 s spacing were being counted between real presses.
var min_count_excursion_m := 0.02
## A gap longer than this is a pause, not a pace: the rolling pace window is dropped (dial back
## to "--") and the gap is never averaged in. 2026-09-15 log: a 1.85 s gap after press 3 alone
## read "32 per minute". Short tracking dropouts do not clear the window.
var stale_pace_s := 1.5
var active := false
var phase := "compressions"
var count := 0
var total_count := 0
var breathing_remaining_s := 0.0
var travel_m := 0.0
var last_stroke_travel_m := 0.0
var last_stroke_quality := "good"  # "good", "shallow", or "deep"
var tracking_available := false
var _baseline_ready := false
var _top := 0.0
var _bottom := 0.0
var _recoil_peak := 0.0
var _descending := false
var _stroke_time := 0.0
var _time_below_s := 0.0
var feedback := "Follow the beep"
var _have_previous_stroke := false
var _since_stroke := 99.0
var _beat_remaining := 0.0
var _bpm_samples := []  # Rolling window of last 4 stroke intervals
var last_interval_s := 0.0  # Interval the last counted press added; 0 when it added none.
var _last_beat_time := 0.0

func reset() -> void:
	active = false
	phase = "compressions"
	count = 0
	total_count = 0
	breathing_remaining_s = 0.0
	last_stroke_travel_m = 0.0
	last_stroke_quality = "good"
	last_interval_s = 0.0
	_since_stroke = 99.0
	_beat_remaining = 0.0
	_bpm_samples.clear()
	_last_beat_time = 0.0
	feedback = "Follow the beep"
	invalidate_tracking()

func start() -> void:
	reset()
	active = true

func invalidate_tracking() -> void:
	tracking_available = false
	_baseline_ready = false
	_descending = false
	_stroke_time = 0.0
	_time_below_s = 0.0
	_have_previous_stroke = false
	travel_m = 0.0

func update(delta: float, valid: bool, height_m: float, paused := false) -> void:
	if paused:
		invalidate_tracking()
		return
	delta = maxf(delta, 0.0)
	_since_stroke += delta
	if _since_stroke > stale_pace_s and not _bpm_samples.is_empty():
		_bpm_samples.clear()
	if phase == "breathing":
		invalidate_tracking()
		breathing_remaining_s = maxf(0.0, breathing_remaining_s - delta)
		if breathing_remaining_s <= 0.0:
			phase = "compressions"
			count = 0
			_beat_remaining = 0.0
		return
	# Beat timing is independent of hand movements and continues through hand occlusion.
	_beat_remaining -= delta
	if _beat_remaining <= 0.0:
		beat_requested.emit()
		var interval := 60.0 / clampf(target_bpm, 100.0, 120.0)
		_beat_remaining = interval + fmod(_beat_remaining, interval)
	# Never bridge an occlusion or a long render stall into a counted stroke.
	if not valid or not is_finite(height_m) or delta > 0.25:
		invalidate_tracking()
		return
	tracking_available = true
	# Pace is feedback only. Keep both completed counts and the current stroke.
	if _have_previous_stroke and _since_stroke > slow_stroke_interval_s:
		feedback = "Press faster"
	if not _baseline_ready:
		_top = height_m
		_bottom = height_m
		_recoil_peak = height_m
		_baseline_ready = true
		return
	if not _descending:
		_top = maxf(_top, height_m)
		if _top - height_m > 0.004:
			_descending = true
			_bottom = height_m
			_recoil_peak = height_m
			_stroke_time = 0.0
			_time_below_s = delta
	else:
		_stroke_time += delta
		if _top - height_m > 0.004:
			_time_below_s += delta
		if height_m < _bottom:
			_bottom = height_m
			_recoil_peak = height_m
		elif height_m > _recoil_peak:
			_recoil_peak = height_m
	travel_m = maxf(0.0, _top - height_m)
	if not _descending:
		return
	if _stroke_time > slow_stroke_interval_s:
		feedback = "Press faster"
	if _top - _bottom > 0.12:
		invalidate_tracking()
		return
	var pressed_long_enough := _time_below_s >= min_press_time_s
	# Completion A: a full return near the top, not merely a change of velocity at the bottom.
	# Without enough time below the top it was a tracking spike: discard it, count nothing.
	if height_m >= _top - return_tolerance_m and height_m - _bottom >= 0.006:
		if pressed_long_enough and _top - _bottom >= min_count_excursion_m:
			_count_stroke(_top - _bottom)
		if _baseline_ready:
			_top = height_m
			_bottom = height_m
			_recoil_peak = height_m
			_descending = false
			travel_m = 0.0
		return
	# Completion B: the hand recoiled most of the way, then clearly started the next press
	# from a lower resting height. Count the finished press; its recoil peak is the new top and
	# this frame is already the start of the next descent.
	var recovered := _recoil_peak - _bottom
	if recovered >= maxf(recoil_minimum_m, recoil_fraction * (_top - _bottom)) and _recoil_peak - height_m > 0.004:
		if pressed_long_enough and _top - _bottom >= min_count_excursion_m:
			_count_stroke(_top - _bottom)
		if _baseline_ready:
			_top = _recoil_peak
			_bottom = height_m
			_recoil_peak = height_m
			_descending = true
			_stroke_time = 0.0
			_time_below_s = delta
			travel_m = maxf(0.0, _top - height_m)

## Count one completed press of the given excursion; quality and pace are assessed separately.
## Entering the breathing phase invalidates tracking (callers must not restore stroke state then).
func _count_stroke(excursion: float) -> void:
	last_stroke_travel_m = excursion

	# Classify depth quality: shallow < 5cm, good >= 5cm
	if excursion < 0.050:
		last_stroke_quality = "shallow"
	elif excursion > 0.060:
		last_stroke_quality = "deep"
	else:
		last_stroke_quality = "good"

	# BPM tracking: add interval to rolling window (last 4 strokes)
	# The first completion establishes timing; it is not an interval.
	# Classify the latest interval before resetting the elapsed timer.
	feedback = "Measuring pace"
	last_interval_s = 0.0
	if _have_previous_stroke:
		if _since_stroke > slow_stroke_interval_s + 0.000001:
			feedback = "Press faster"
		elif _since_stroke < fast_stroke_interval_s - 0.000001:
			feedback = "Press slower"
		else:
			feedback = "Good timing"
		if _since_stroke <= stale_pace_s:
			last_interval_s = _since_stroke
			_bpm_samples.append(_since_stroke)
		if _bpm_samples.size() > 4:
			_bpm_samples.pop_front()

	# Activate and count (no depth gate).
	if not active:
		active = true
		count = 1
		total_count = 1
	else:
		count += 1
		total_count += 1
	_since_stroke = 0.0
	_have_previous_stroke = true

	if count >= 30:
		phase = "breathing"
		breathing_remaining_s = breathing_duration_s
		invalidate_tracking()
