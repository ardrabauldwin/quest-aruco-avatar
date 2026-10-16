extends "res://tests/suite.gd"
const Motion = preload("res://addons/naret_upstream/avatar/cpr_motion_session.gd")

func stroke(session: RefCounted, amplitude := 0.035) -> void:
	for i in range(41):
		var height := -amplitude * (1.0 - cos(TAU * float(i) / 40.0)) * 0.5
		session.update(1.0 / 72.0, true, height)

func run() -> Array[String]:
	failures.clear()
	var motion := Motion.new()
	motion.automatic_breathing_pause = false
	motion.metronome_enabled = false
	for i in range(32):
		stroke(motion)
	check(motion.total_count == 32, "32 hand excursions count across the scenario-owned cycle boundary")
	check(motion.phase == "compressions", "no standalone breathing timer overrides NaReT")
	var count: int = motion.total_count
	motion.update(0.016, true, 0.0)
	motion.update(0.016, true, -0.04)
	motion.update(0.016, false, 0.0)
	motion.update(0.016, true, 0.0)
	check(motion.total_count == count, "tracking dropout cannot complete a press")
	stroke(motion)
	check(motion.total_count == count + 1, "fresh stroke works after dropout")
	var jitter := Motion.new()
	for i in range(10):
		stroke(jitter, 0.003)
	check(jitter.total_count == 0, "resting hand jitter creates no compressions")
	return failures
