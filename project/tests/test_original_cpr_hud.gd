extends "res://tests/suite.gd"
const Hud = preload("res://addons/naret_upstream/avatar/cpr_feedback_hud.gd")
func run() -> Array[String]:
	failures.clear()
	check(Hud.measured_bpm([]) == 0.0, "No pace before intervals")
	check(Hud.measured_bpm([0.5]) == 0.0, "Original dial requires two intervals")
	check(is_equal_approx(Hud.measured_bpm([0.5, 0.5]), 120.0), "Original interval pace")
	check(Hud.depth_colour(4.9) == Hud.COLOR_BAD, "Shallow display")
	check(Hud.depth_colour(5.0) == Hud.COLOR_GOOD, "Original depth boundary")
	check(Hud.depth_colour(6.1) == Hud.COLOR_WARN, "Deep display")
	check(Hud.coach_message("shallow", "Press slower", true).text == "Press deeper", "Depth coaching takes priority")
	return failures
