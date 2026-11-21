extends "res://tests/suite.gd"
## Reported compression depth is the counting palm's travel within the stroke times the
## factor fitted against the QCPR manikin (9 Nov 2026), not the counter's travel from a
## saved rest, which counted the descent from a hover as depth (10–12 cm reported).

func run() -> Array[String]:
	failures.clear()
	var zone = load("res://addons/naret_upstream/avatar/cpr_hand_zone.tscn").instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(zone)
	zone.set_process(false)
	zone._placed_counter = load("res://scripts/tracking/two_hand_press_counter.gd").new()
	zone._stroke_top = 0.060
	zone._stroke_bottom = 0.005 # 5.5 cm of palm travel within the stroke
	zone._on_placed_press(0.105) # the counter saw 10.5 cm from a hover
	check(is_equal_approx(zone.motion_session.last_stroke_travel_m, 0.055 * zone.TOP_PALM_DEPTH_FACTOR), "depth is the stroke's palm travel times the fitted factor, not the hover descent")
	check(zone.motion_session.last_stroke_quality == "shallow", "2.5 cm is graded shallow")
	check(not is_finite(zone._stroke_top) and not is_finite(zone._stroke_bottom), "the stroke extremes reset for the next press")
	zone._stroke_top = 0.085
	zone._stroke_bottom = -0.05 # 13.5 cm of palm travel: a full-depth compression
	zone._on_placed_press(0.135)
	check(is_equal_approx(zone.motion_session.last_stroke_travel_m, 0.135 * zone.TOP_PALM_DEPTH_FACTOR), "a 13.5 cm palm travel is about a 5.4 cm compression")
	check(zone.motion_session.last_stroke_quality == "good", "5.4 cm is graded good")
	zone._on_placed_press(0.05)
	check(is_equal_approx(zone.motion_session.last_stroke_travel_m, 0.05 * zone.TOP_PALM_DEPTH_FACTOR), "without stroke extremes the counter's travel is scaled")
	tree.root.remove_child(zone)
	zone.free()
	return failures
