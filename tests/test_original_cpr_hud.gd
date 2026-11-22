extends "res://tests/suite.gd"
const Hud = preload("res://addons/naret_upstream/avatar/cpr_feedback_hud.gd")
func run() -> Array[String]:
	failures.clear()
	check(Hud.measured_bpm([]) == 0.0, "No pace before intervals")
	check(Hud.measured_bpm([0.5]) == 0.0, "Original dial requires two intervals")
	check(is_equal_approx(Hud.measured_bpm([0.5, 0.5]), 120.0), "Original interval pace")
	# 17 Nov 2026: depth is shown neutrally, not judged red/green.
	check(Hud.depth_text(4.9, "en") == "≈ 4.9 cm", "Neutral depth number")
	check(Hud.depth_text(5.5, "de") == "≈ 5,5 cm" and Hud.depth_text(5.5, "pl") == "≈ 5,5 cm", "Decimal comma in German and Polish")
	check(not "depth_colour" in (Hud as GDScript).get_script_method_list().map(func(m): return m.name), "No red/green depth judgement")
	# 17 Nov 2026: pace hints only, no depth hints, in the trainee's language.
	check(Hud.coach_message("Press slower", true, "en").text == "Push slower", "Pace hint while pressing")
	check(Hud.coach_message("Press faster", true, "en").text == "Push faster", "Faster hint")
	check(Hud.coach_message("", true, "en").text == "Good rate", "Good rate in the band")
	check(Hud.coach_message("", false, "en").text == "Keep hands in view", "Hands not seen")
	check(Hud.coach_message("Press faster", true, "de").text == "Schneller drücken", "German hint")
	check(Hud.coach_message("Press faster", true, "pl").text == "Uciskaj szybciej", "Polish hint")
	for lang in ["en", "de", "pl"]:
		for key in Hud.TEXT.en:
			check(Hud.TEXT[lang].has(key), "%s has the HUD text %s" % [lang, key])
	check(Hud.text("place", "en") == "HANDS ON BREASTBONE" and Hud.text("breaths_hint", "en") == "30 compressions done: now 2 breaths", "English wording as asked")
	return failures
