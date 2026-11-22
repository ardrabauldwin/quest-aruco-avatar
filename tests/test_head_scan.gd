extends "res://tests/suite.gd"
## Safety gate (issue #1): the head turns left and right before "the area is safe".

func _dir(deg: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(deg))

func run() -> Array[String]:
	failures.clear()
	var scan := NaretHeadScan.new()
	scan.update(_dir(0))
	scan.update(_dir(20))
	scan.update(_dir(-20))
	check(not scan.done(), "small head movements do not count as looking around")
	check(not scan.update(_dir(50)) and scan.left and not scan.right, "a turn to one side is half the scan")
	check(scan.update(_dir(-45)), "both sides: the scan is done")
	scan.reset()
	scan.update(_dir(170))
	scan.update(_dir(-150))
	check(scan.left and not scan.right, "turns across the back are measured from the start direction")
	scan.update(_dir(120))
	check(scan.done(), "and the other side completes it")
	return failures
