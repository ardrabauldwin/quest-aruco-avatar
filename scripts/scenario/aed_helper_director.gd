extends "res://scripts/scenario/single_witness_director.gd"
## Anna remains the witness; Marek has an independent spot and delivers the AED.
## No automatic pad attachment and no invented helper strokes.
##
## The errand, as it plays (13 Nov 2026, after headset review):
##   announce    he says he is going and is still seen saying it
##   walk_out    a few steps away from the patient, then out of the scene
##   away        HELPER_FETCH_S
##   walk_offer  back with the device, to a spot beside the trainee
##   wait        he stands there with it until the trainee's hands leave the chest
##   offer       he holds it out and asks the trainee to take it; the trainee grabs it
##               (NaretAED.touch), carries it and lets go where it should lie
##   handed      he waits until the trainee has put it down, then walks back
## He never holds it out to someone whose hands are on the chest. His errand ends about
## 20 s after the request, which is in the middle of the trainee's compressions; a
## held-out device then asks the trainee to stop pressing and reach for it. So he waits
## beside the trainee until the set is over (no stroke for HANDS_BUSY_S: the pause for
## the two breaths), and only then holds it out. Pressing again sends him back to
## waiting. He puts it down himself if the offer is not taken within OFFER_WAIT_S, if
## the waiting exceeds WAIT_MAX_S, or at once in compression-only CPR, which has no pause:
##   walk_in     to a spot beside the device's place
##   bend        he bends as far as the device's place is low (NaretBystander "place")
##   rise        the device is lowered out of his hand onto its place
##   walk_home   back to where he stood
## Before, he vanished in the frame his sentence began, stayed away 45 s, reappeared
## 1.6 m from the patient holding the device, and the device then jumped to its place
## and fell with a bounce: that was the "throw".

## Real public AEDs are about a minute away; 45 s of an empty scene was too long for
## the exercise, so the errand is shortened further.
const HELPER_FETCH_S := 15.0
## He is asked at the call for help now (13 Nov 2026), so 15 s would bring him back
## during the breathing check, before a single compression. He comes back when the
## first set is nearly done: he starts walking in at this stroke and the device is on
## the stool about when the 30th is given, in the pause where the breaths would be.
## The AED is used at once; the first breaths follow the next 30 compressions.
var return_after_compressions := 22
## If nobody presses at all he still comes, this long after HELPER_FETCH_S.
const RETURN_ANYWAY_S := 90.0
const ANNOUNCE_S := 1.8
## Steps he is seen walking before and after the errand; main keeps them in the room.
const EXIT_M := 1.0
## Hand-over: he stops this far from the trainee's head, toward the patient's head end.
## His offer pose brings the hand 0.40 m forward, so the device ends up 0.3 m away.
const OFFER_M := 0.70
## How long he holds it out to free hands. Taking a held-out object needs 2-3 s; 8 s
## also covers a trainee who is looking at the patient when he arrives. Longer (it was
## 20 s) only keeps the device out of use: every second without it is a second later
## for the shock.
const OFFER_WAIT_S := 8.0
## Strokes come every 0.5-0.6 s; this long after the last one the set counts as over.
## Breaths do not count as busy: the pause for them is the moment of the hand-over.
const HANDS_BUSY_S := 1.5
## Longest he stands waiting for a pause: two sets of 30 at 100-120/min with their
## breaths. After that the device goes down beside the patient rather than stay unused.
const WAIT_MAX_S := 40.0
## A place this little above his floor is the floor itself: he kneels (no stool there).
const FLOOR_M := 0.15
const BEND_S := 1.1
const RISE_S := 0.9
const WALK_MARGIN_S := 2.0

## Off since the stool exists (13 Nov 2026, "Marek takes it and places it"): he brings
## the device and sets it on the stool himself, whatever the trainee is doing. On, he
## first offers it to the trainee as described above.
var hand_over := false
var delivery_ready: Callable = func(): return false
## (Vector3) -> Vector3: the nearest point he may walk to (main: inside the play area).
var keep_in_room: Callable = func(point: Vector3): return point
## The errand is running: from the request until the device is on the ground.
var fetching := false
## He is out of the scene; main hides him only then.
var away := false
var delivered := false
## The device is in his or the trainee's hand, not yet at rest.
var presenting := false
var phase := ""
signal device_delivered
var _phase_until := INF
var _return_at := INF
var _spot_home := Transform3D.IDENTITY
var _has_spot_home := false
var _goal := Vector3.ZERO
var _walk_from := Vector3.ZERO
var _walk_limit := INF
var _hands_t := -INF
var _give_up_at := INF

func configure(p_scenario: NaretScenario, p_anna: NaretBystander, p_marek: NaretBystander, p_patient: Node3D, p_aed: NaretAED) -> void:
	super.configure(p_scenario, p_anna, p_marek, p_patient, p_aed)
	if aed:
		aed.taken.connect(_on_device_taken)
		aed.placed.connect(_on_device_placed)

func _on_state_changed(state: int) -> void:
	super._on_state_changed(state)
	if state in [NaretScenario.State.IDLE, NaretScenario.State.INTRO]:
		_end_errand(true)
		delivered = false
	if state == NaretScenario.State.RECOVERY:
		if presenting and aed: aed.reset()
		_end_errand(false)

func _end_errand(send_home: bool) -> void:
	fetching = false
	away = false
	presenting = false
	phase = ""
	_phase_until = INF
	_return_at = INF
	if marek == null: return
	marek.halt()
	marek.facing_locked = false
	if send_home and _has_spot_home:
		marek.global_transform = _spot_home
	_has_spot_home = false

func _hands_busy() -> bool:
	return _t - _hands_t < HANDS_BUSY_S

func _on_event(event: Dictionary) -> void:
	# A stroke the scenario did not count still means the hands are on the chest.
	if event.get("action") == "compression" and (event.get("details", {}) as Dictionary).get("source", "") != "bystander":
		_hands_t = _t
	if not event.get("accepted", false): return
	if event.get("action") == "request_aed" and not fetching and not delivered:
		fetching = true
		_return_at = _t + HELPER_FETCH_S
		_say("marek_go_aed", 0.0)
		if marek:
			_spot_home = marek.global_transform
			_has_spot_home = true
			marek.attention = "trainee"
		_enter("announce", ANNOUNCE_S)

func _enter(next: String, seconds: float) -> void:
	phase = next
	_phase_until = _t + seconds

func _walk(target: Vector3, next: String) -> void:
	_goal = target
	marek.facing_locked = false
	marek.walk_to(target)
	_enter(next, marek.global_position.distance_to(target) / NaretBystander.WALK_SPEED + WALK_MARGIN_S)
	# The straight-line time above is when he is expected. If he is still on his way
	# then (round the patient, people, the stool), he gets the time his real path needs
	# before he is simply PUT at the goal: put there mid-detour, he went through
	# whatever stood between.
	_walk_from = marek.global_position
	_walk_limit = _t + marek.path_length_m() / NaretBystander.WALK_SPEED * 1.5 + WALK_MARGIN_S + 2.0
	print("NARET_HELPER walk %s from=(%.2f, %.2f) to=(%.2f, %.2f)" % [next, _walk_from.x, _walk_from.z, target.x, target.z])

func _walk_done() -> bool:
	## Arrived, or the walk's time is up (headless tests have no frames to walk in).
	if marek.is_walking() and _t < _phase_until: return false
	# Really moving (not a test without frames) and within the time his path needs: wait.
	var moved := marek.global_position.distance_to(_walk_from) > 0.02
	if marek.is_walking() and _t < _walk_limit and moved: return false
	# Out of time while really walking: he stays where the bodies in his way stopped him.
	# He is no longer put at the goal, which could be through or inside one of them.
	# (Only a test without frames, where nobody moves at all, still places him there.)
	if marek.is_walking() and moved: marek.halt()
	else: marek.halt(_goal)
	return true

func _face(point: Vector3) -> void:
	var to_point := point - marek.global_position
	to_point.y = 0.0
	if to_point.length() > 0.05:
		# Characters model +Z forward; looking_at aims -Z.
		marek.global_basis = Basis.looking_at(-to_point.normalized(), Vector3.UP)
	marek.facing_locked = true

func _head_end() -> Vector3:
	var direction := -patient.global_basis.z if patient else Vector3.FORWARD
	if patient and patient.has_method("get_body_transform"):
		direction = -(patient.call("get_body_transform") as Transform3D).basis.z
	direction.y = 0.0
	return direction.normalized() if direction.length() > 0.1 else Vector3.FORWARD

func _leave_point() -> Vector3:
	## Out past the stool, on the line from the patient through the device's place, and
	## back the same way: he leaves where he will come back with the device (14 Nov 2026,
	## headset: "why does he walk in another direction"). He used to leave straight away
	## from the patient from his own place, a point then pulled back inside the play
	## area: in a small play area, from its corner, a short step sideways, and he came
	## back from somewhere else. A point he walks to in order to leave the scene is not
	## held inside the play area; the play area decides where people stand.
	var stand := _set_down_stand()
	var outward := _outward()
	var point := stand + outward * EXIT_M
	return Vector3(point.x, _spot_home.origin.y if _has_spot_home else marek.global_position.y, point.z)

func _outward() -> Vector3:
	## From the patient through the device's place on the stool.
	var home := aed.home_position()
	var outward := home - (patient.global_position if patient else home + _head_end())
	outward.y = 0.0
	return outward.normalized() if outward.length() > 0.05 else _head_end()

func _in_room_if_free(wanted: Vector3) -> Vector3:
	## The point pulled inside the play area, unless that puts it on a person or on the
	## patient: then the point as it was. A drawn helper outside the boundary harms
	## nobody; one standing in the patient does.
	var inside: Vector3 = keep_in_room.call(wanted)
	return inside if _spot_free(inside) else wanted

func _offer_point() -> Vector3:
	## Beside the trainee toward the patient's head end, never on the patient.
	var eye: Vector3 = trainee.call()
	var point := eye + _head_end() * OFFER_M
	if patient: point = _clear_of_patient(point)
	point = _in_room_if_free(point)
	return Vector3(point.x, marek.global_position.y, point.z)

func _place_height() -> float:
	return aed.home_position().y - marek.standing_floor_y()

func _set_down_stand() -> Vector3:
	## On the far side of the device's place from the patient (the stool stands between
	## him and the patient), as far back as his hand reaches forward when he bends.
	var home := aed.home_position()
	var outward := _outward()
	var reach := NaretBystander.place_reach_m(_place_height())
	# Not where somebody already stands: if the straight-out spot is taken, the nearest
	# free one round the stool (turned 40, 80 or 120 degrees to either side).
	#
	# 14 Nov 2026: the chosen spot was then pulled inside the play area without looking
	# again. With the patient near the boundary and the stool just outside it (headset
	# log: stool at z 1.43, boundary at 1.03, patient at 0.83), that put him 17 cm from
	# the patient's chest: he walked into the patient to set the device down. A spot is
	# now only taken if it is free where he will actually stand, and the boundary gives
	# way before the patient does.
	#
	# Later the same day: the play area no longer picks the side either. Preferring a
	# spot inside it sent him round to another side of a stool that stands outside it,
	# so he came back from a direction he had not left in. The stool is never moved for
	# the boundary; where he stands at it follows the stool.
	var turns: Array[float] = [0.0, 40.0, -40.0, 80.0, -80.0, 120.0, -120.0, 160.0, -160.0]
	var best := home + outward * reach
	for turn_deg in turns:
		var candidate := home + outward.rotated(Vector3.UP, deg_to_rad(turn_deg)) * reach
		if _spot_free(candidate):
			best = candidate
			break
	return Vector3(best.x, marek.global_position.y, best.z)

func _spot_free(point: Vector3) -> bool:
	## No other person, the trainee or the patient within a body's width of the spot.
	## The stool itself does not count: he stands at it.
	if marek == null or not marek.obstacles.is_valid(): return true
	var here := Vector2(point.x, point.z)
	for block: Dictionary in marek.obstacles.call():
		if is_equal_approx(float(block.radius), 0.40): continue # the stool
		if here.distance_to(block.point) < float(block.radius) + NaretBystander.BODY_CLEAR_M + 0.05: return false
	return true

func _on_device_taken() -> void:
	if phase != "offer": return
	# His hand is empty: he lets it sink and watches the trainee place the device.
	marek.set_posture("")
	marek.attention = "trainee"
	_enter("handed", INF)

func _on_device_placed() -> void:
	if phase != "handed": return
	_finish_delivery()
	_go_home()

func _finish_delivery() -> void:
	presenting = false
	fetching = false
	delivered = true
	scenario.aed_available = true
	device_delivered.emit()

func _go_home() -> void:
	marek.set_posture("")
	marek.attention = "auto"
	_walk(_spot_home.origin if _has_spot_home else marek.global_position, "walk_home")

func advance(delta: float) -> void:
	super.advance(delta)
	if phase.is_empty() or marek == null or aed == null: return
	match phase:
		"announce":
			if _t < _phase_until: return
			marek.attention = "auto"
			_walk(_leave_point(), "walk_out")
		"walk_out":
			if not _walk_done(): return
			away = true
			marek.visible = false
			_enter("away", 0.0)
		"away":
			if _t < _return_at: return
			if scenario.state not in [NaretScenario.State.CALL_HELP, NaretScenario.State.CPR]: return
			var pressed_enough: bool = scenario.cycles > 0 or scenario.cycle_compressions >= return_after_compressions or scenario.compressions >= return_after_compressions
			if not pressed_enough and _t < _return_at + RETURN_ANYWAY_S: return
			# Main allocates the device's fallback place against current geometry.
			if not delivery_ready.is_valid() or not delivery_ready.call(): return
			away = false
			presenting = true
			marek.visible = true
			aed.pick_up(marek)
			if not hand_over or (_hands_busy() and scenario.compression_only): _walk(_set_down_stand(), "walk_in")
			else: _walk(_offer_point(), "walk_offer")
		"walk_offer":
			if not _walk_done(): return
			_face(trainee.call())
			marek.attention = "trainee"
			_give_up_at = _t + WAIT_MAX_S
			_enter("wait", INF)
		"wait":
			_face(trainee.call())
			if _hands_busy():
				if _t < _give_up_at: return
				# No pause came: he puts it down himself.
				_walk(_set_down_stand(), "walk_in")
				return
			marek.set_posture("offer")
			aed.offer(marek)
			_say("marek_take_aed", 0.0)
			_enter("offer", OFFER_WAIT_S)
		"offer":
			_face(trainee.call())
			if _hands_busy():
				# The trainee is pressing again: he takes it back and waits for the next pause.
				aed.withdraw_offer()
				marek.set_posture("")
				_enter("wait", INF)
				return
			if _t < _phase_until: return
			# Nobody took it: he puts it down himself.
			aed.withdraw_offer()
			marek.set_posture("")
			_walk(_set_down_stand(), "walk_in")
		"walk_in":
			if not _walk_done(): return
			_face(aed.home_position())
			marek.attention = "patient"
			marek.place_height_m = _place_height()
			marek.set_posture("place" if marek.place_height_m > FLOOR_M else "kneel")
			_enter("bend", BEND_S)
		"bend":
			if _t < _phase_until: return
			aed.put_down()
			_say("marek_take_aed", 0.0)
			_finish_delivery()
			_enter("rise", RISE_S)
		"rise":
			if _t < _phase_until: return
			_go_home()
		"walk_home":
			if not _walk_done(): return
			if _has_spot_home: marek.global_basis = _spot_home.basis
			marek.facing_locked = false
			phase = ""
