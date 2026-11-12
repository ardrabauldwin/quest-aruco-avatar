extends "res://tests/suite.gd"
## The hand menu's opening gates against palm flips of the covered hand during CPR.

const Menu = preload("res://scripts/ui/hand_menu.gd")

func run() -> Array[String]:
	failures.clear()
	# Distance condition: stacked CPR hands block opening, a free other hand does not.
	check(Menu.palms_stacked(0.05, false), "palms 5 cm apart are the CPR grip")
	check(not Menu.palms_stacked(0.25, true), "palms 25 cm apart are not stacked, whatever was remembered")
	check(Menu.palms_stacked(INF, true), "a lost other hand keeps the stacked verdict while remembered")
	check(not Menu.palms_stacked(INF, false), "a lost other hand without memory does not block")
	# Time condition: the palm must face the wearer without a break for OPEN_HOLD_S.
	var held := 0.0
	for frame in 5: # A five-frame flip at 72 Hz.
		held = Menu.open_hold(held, true, 1.0 / 72.0)
	check(held < Menu.OPEN_HOLD_S, "a five-frame flip does not open the menu")
	held = Menu.open_hold(held, false, 1.0 / 72.0)
	check(held == 0.0, "a break restarts the hold")
	for frame in 40: # A deliberate turn, held a little over half a second.
		held = Menu.open_hold(held, true, 1.0 / 72.0)
	check(held >= Menu.OPEN_HOLD_S, "a held turn opens the menu")
	return failures
