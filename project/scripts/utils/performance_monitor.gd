class_name NaretPerformanceMonitor
extends Node

signal updated(metrics: Dictionary)
var samples: Array[Dictionary] = []
var _elapsed := 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 1.0: return
	_elapsed = 0.0
	var metrics := {
		"fps": Engine.get_frames_per_second(),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"platform": OS.get_name(), "xr": get_viewport().use_xr,
	}
	samples.append(metrics)
	if samples.size() > 300: samples.pop_front()
	updated.emit(metrics)

func get_summary() -> Dictionary:
	if samples.is_empty(): return {}
	var fps_sum := 0.0
	var min_fps := 10000
	var peak_draw_calls := 0
	for sample in samples:
		fps_sum += sample.fps
		min_fps = mini(min_fps, sample.fps)
		peak_draw_calls = maxi(peak_draw_calls, sample.draw_calls)
	return {"sample_count": samples.size(), "mean_fps": fps_sum / samples.size(),
		"min_fps": min_fps, "peak_draw_calls": peak_draw_calls,
		"platform": OS.get_name(), "xr": get_viewport().use_xr}
