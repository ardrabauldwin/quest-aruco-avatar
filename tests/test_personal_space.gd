extends "res://tests/suite.gd"
## Idle helpers make room for the trainee: one 0.4 m step back within 0.6 m, back home past 1 m.

func run() -> Array[String]:
	failures.clear()
	var home := Vector2(0.0, 0.0)
	var far := NaretPersonalSpace.decide(home, Vector2(0.9, 0.0), false)
	check(far.target == null and not far.stepped, "nobody moves while the trainee is 0.9 m away")
	var near := NaretPersonalSpace.decide(home, Vector2(0.5, 0.0), false)
	check(near.stepped and near.target is Vector2 and (near.target as Vector2).is_equal_approx(Vector2(-0.4, 0.0)), "within 0.6 m: 0.4 m straight away from the trainee (%s)" % str(near.target))
	var stay := NaretPersonalSpace.decide(home, Vector2(0.8, 0.0), true)
	check(stay.stepped and stay.target == null, "stays back while the trainee is still within 1 m of the own place")
	var back := NaretPersonalSpace.decide(home, Vector2(1.2, 0.0), true)
	check(not back.stepped and back.target is Vector2 and (back.target as Vector2).is_equal_approx(home), "returns to the own place once the trainee is past 1 m")
	check(NaretPersonalSpace.STEP_M < 1.0, "a small step, not Dennis's 1 m move to a new spot")
	return failures
