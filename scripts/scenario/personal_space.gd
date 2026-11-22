class_name NaretPersonalSpace
extends RefCounted
## A standing helper (Anna, instructor, Marek) who has nothing to do makes room for the
## trainee: one small step straight back when the trainee comes very close, and back to
## the own place once the trainee has gone (17 Nov 2026, after the team's sensor-log
## branch, where idle bystanders move 1 m away to a new spot; here they keep their place
## in the row: "add it, but don't move 1 m").

## Closer than this (head to helper, on the floor plane) and the helper steps back.
const TRIGGER_M := 0.6
## How far back.
const STEP_M := 0.4
## Farther than this from the own place and the helper returns to it.
const RETURN_M := 1.0

## What to do with one helper. home: the helper's own place; trainee: the trainee's
## head, both on the floor plane (x, z); stepped: whether the helper stands back now.
## Returns {"stepped": bool, "target": Vector2 or null (stay)}.
static func decide(home: Vector2, trainee: Vector2, stepped: bool) -> Dictionary:
	var gap := home.distance_to(trainee)
	if stepped:
		if gap > RETURN_M:
			return {"stepped": false, "target": home}
		return {"stepped": true, "target": null}
	if gap < TRIGGER_M:
		var away := home - trainee
		if away.length() < 0.01:
			return {"stepped": false, "target": null}
		return {"stepped": true, "target": home + away.normalized() * STEP_M}
	return {"stepped": false, "target": null}
