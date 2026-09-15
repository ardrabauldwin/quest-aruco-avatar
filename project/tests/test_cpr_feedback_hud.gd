extends SceneTree
## Coach-message mapping and gauge maths of the practice HUD, plus a headless build of the node.
const Hud = preload("res://cpr_feedback_hud.gd")
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	# Depth beats pace; good is green.
	var shallow: Dictionary = Hud.coach_message("shallow", "Good timing", true)
	check(shallow["text"] == "Press deeper" and shallow["colour"] == Hud.COLOR_BAD, "Shallow press says Press deeper in red")
	var shallow_fast: Dictionary = Hud.coach_message("shallow", "Press faster", true)
	check(shallow_fast["text"] == "Press deeper", "Depth correction outranks pace correction")
	var deep: Dictionary = Hud.coach_message("deep", "Good timing", true)
	check(deep["text"] == "Too deep, ease off" and deep["colour"] == Hud.COLOR_WARN, "Deep press warns to ease off")
	var slow: Dictionary = Hud.coach_message("good", "Press faster", true)
	check(slow["text"] == "Good depth, press faster", "Good depth with slow pace asks for faster")
	var fast: Dictionary = Hud.coach_message("good", "Press slower", true)
	check(fast["text"] == "Good depth, press slower", "Good depth with fast pace asks for slower")
	for pace in ["Good timing", "Measuring pace", "Follow the beep"]:
		var good: Dictionary = Hud.coach_message("good", pace, true)
		check(good["text"] == "Good press" and good["colour"] == Hud.COLOR_GOOD, "Good depth and acceptable pace is Good press (%s)" % pace)
	var lost: Dictionary = Hud.coach_message("good", "Good timing", false)
	check(lost["text"] == "Keep your hands in view", "Tracking loss shows a hand cue")
	# The node builds headless and tolerates no zone (hidden, no crash).
	var hud = Hud.new()
	root.add_child(hud)
	hud._process(0.016)
	check(not hud.visible, "HUD without a zone stays hidden")
	check(hud._depth.has("marker"), "Depth gauge built")
	check(hud._dial.has("needle") and hud._dial.has("value"), "Speed dial built")
	# Speed needs two measured intervals; then it is the plain mean.
	check(Hud.measured_bpm([]) == 0.0 and Hud.measured_bpm([0.5]) == 0.0, "Rate unavailable below two intervals")
	check(absf(Hud.measured_bpm([0.5, 0.5]) - 120.0) < 0.01, "Two 0.5 s intervals read 120 per minute")
	hud._set_dial(110.0, true)
	check(hud._dial["needle"].visible and hud._dial["value"].modulate == Hud.COLOR_GOOD and "110" in hud._dial["value"].text, "110 per minute shows a green needle")
	hud._set_dial(90.0, true)
	check(hud._dial["value"].modulate == Hud.COLOR_BAD, "90 per minute reads red")
	hud._set_dial(0.0, false)
	check(not hud._dial["needle"].visible and hud._dial["value"].text == "--", "Unavailable hides the needle")
	hud._set_depth(5.5, true)
	check(hud._depth["marker"].visible and hud._depth["value"].modulate == Hud.COLOR_GOOD and "5.5" in hud._depth["value"].text, "5.5 cm reads green")
	hud._set_depth(3.0, true)
	check(hud._depth["value"].modulate == Hud.COLOR_BAD, "3.0 cm reads red")
	hud._set_depth(6.8, true)
	check(hud._depth["value"].modulate == Hud.COLOR_WARN, "6.8 cm reads amber (too deep)")
	hud._set_depth(3.0, false)
	check(not hud._depth["marker"].visible and hud._depth["value"].text == "--", "Unavailable hides the marker")
	check(Hud.depth_colour(4.9) == Hud.COLOR_BAD and Hud.depth_colour(5.0) == Hud.COLOR_GOOD and Hud.depth_colour(6.0) == Hud.COLOR_GOOD and Hud.depth_colour(6.1) == Hud.COLOR_WARN, "Depth colour thresholds at 5 and 6 cm")
	hud.queue_free()
	print("CPR feedback HUD tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
