extends "res://tests/suite.gd"
const Helper = preload("res://scripts/scenario/aed_helper_director.gd")
const Interpreter = preload("res://scripts/ai/speech_pipeline.gd")
const Requests = preload("res://scripts/scenario/spoken_observation.gd")

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var scenario := NaretScenario.new()
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var anna: NaretBystander = load("res://scenes/bystander.tscn").instantiate()
	var marek: NaretBystander = load("res://scenes/bystander_male.tscn").instantiate()
	var model: Node3D = load("res://assets/models/aed.glb").instantiate()
	var device := NaretAED.new()
	var director := Helper.new()
	# The device's place is a transform under a spatial parent, as in the main scene.
	var world := Node3D.new()
	tree.root.add_child(world)
	world.add_child(model)
	for node in [scenario, patient, anna, marek, device, director]: tree.root.add_child(node)
	device.configure(model, patient)
	device.manual_pad_placement_required = true
	director.configure(scenario, anna, marek, patient, device)
	director.hand_over = true # The offer to the trainee stays covered; the default follows below.
	director.return_after_compressions = 0 # These walks are timed; the default follows below too.
	var clear_space := [false]
	director.delivery_ready = func(): return clear_space[0]
	scenario.start()
	check(not scenario.aed_available, "helper hides AED until actually delivered")
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
		check(scenario.submit_action(action), "normal training step " + action)
	check(scenario.submit_action("request_aed"), "Marek can be requested without waiting for a CPR cycle")
	check(director.fetching and marek.visible and not director.away, "Marek is still seen while he says he is going")
	director.advance(1.9)
	check(director.phase == "walk_out" and marek.visible, "he walks off instead of vanishing")
	director.advance(5.0)
	check(director.away and not marek.visible, "only Marek leaves; Anna remains")
	director.advance(16.0)
	check(not scenario.aed_available and director.fetching, "delivery waits when a separate legal helper/device spot is unavailable")
	clear_space[0] = true
	director.advance(0.01)
	check(model.get_parent() is BoneAttachment3D and marek._rig.has_clip("kneel") and marek._rig.has_clip("reach"), "AED is carried by actual hand attachment and set-down clips exist")
	check(device._held and director.presenting and not scenario.aed_available and marek.visible, "carrying precedes device availability")
	director.advance(10.0)
	check(director.phase == "wait" and not device.offered, "he arrives beside the trainee with the device")
	director.advance(0.1)
	check(director.phase == "offer" and device.offered and not scenario.aed_available, "he holds the device out and asks the trainee to take it")
	device.rest_height = func(): return 0.0
	var hand := device.model.global_position + Vector3(0, 0.04, 0)
	check(not device.touch("right", hand, hand, false, hand, false), "an open hand at the device does not take it")
	check(device.touch("right", hand, hand, false, hand, true) and director.phase == "handed", "a closed hand takes it from Marek")
	check(not scenario.aed_available and model.get_parent() == world, "in the trainee's hand it is not yet available")
	var carried := Vector3(0.4, 0.6, -0.3)
	device.touch("right", carried, carried, false, carried, true)
	check(device.model.global_position.distance_to(carried + device._carry_offset) < 0.001, "the device follows the carrying hand")
	device._carry_seen_ms -= 1000
	device.touch("right", carried, carried, false, carried, false)
	check(director.delivered and not device._held and scenario.aed_available, "letting go places it and makes it available")
	var rest := device.model.global_position
	check(absf(rest.y) < 0.001 and Vector2(rest.x, rest.z).distance_to(Vector2(carried.x, carried.z) + Vector2(device._carry_offset.x, device._carry_offset.z)) < 0.001, "it rests under where the trainee let go, on the patient's surface")
	director.advance(10.0)
	check(director.phase == "" and not director.fetching, "errand ends with Marek back at his spot")
	check(scenario.compressions == 0, "helper animation never invents compressions")
	device._attach()
	check(not device._attached and device._placed.is_empty(), "XR blocks animated automatic pad placement")
	device._power_on()
	var pads: Array = device._pads.values()
	pads[0].global_transform = device._pad_target("PadRight")
	device._drop(pads[0])
	check(not device.pads_ready(), "one manually placed pad cannot connect AED")
	pads[1].global_transform = device._pad_target("PadLeft")
	device._drop(pads[1])
	check(device.pads_ready(), "two user-placed pads and power are required")
	var announcement_order: Array[String] = []
	device.spoke.connect(func(key: String, _language: String): announcement_order.append(key))
	device.requested.connect(func(action: String):
		announcement_order.append(action)
		scenario.submit_action(action))
	for i in 17: scenario.submit_action("compression")
	device.sync(scenario, "en")
	check(scenario.aed_attached and scenario.state == NaretScenario.State.AED, "two pads enter guarded AED flow")
	device.sync(scenario, "en")
	check(scenario.aed_stage == NaretScenario.AEDStage.ATTACHED, "no automatic clearance declaration")
	check(scenario.submit_action("clear_patient"), "explicit clearance allows analysis")
	check(not scenario.submit_action("patient_contact"), "contact invalidates clearance")
	check(scenario.aed_stage == NaretScenario.AEDStage.ATTACHED, "contact resets clearance before shock")
	scenario.submit_action("clear_patient")
	scenario.submit_action("analyze_rhythm")
	scenario.submit_action("clear_patient")
	check(scenario.submit_action("shock") and scenario.state == NaretScenario.State.CPR, "shock resumes CPR immediately")
	check(scenario.cycle_compressions == 0 and scenario.compressions == 17, "AED resets current set but preserves earlier session total")
	check("zero" in NaretTrainingCoach.current_instruction(scenario, "en"), "instructor explicitly explains fresh counting after shock")
	scenario.submit_action("compression")
	check(scenario.cycle_compressions == 1 and scenario.compressions == 18, "first resumed press is set one and session total eighteen")
	scenario.aed_training_pattern = [false]
	scenario.analysis_due = true
	scenario.submit_action("reassess")
	scenario.submit_action("clear_patient")
	scenario.submit_action("analyze_rhythm")
	# The previous prompt has finished. (English AED lines are recorded clips since
	# 14 Nov 2026; while one plays, the next is queued behind it, not dropped.)
	device._voice.stop()
	device._queued_voice = ""
	announcement_order.clear()
	device.sync(scenario, "en")
	check(announcement_order.has("aed_no_shock") and announcement_order.has("resume_cpr") and announcement_order.find("aed_no_shock") < announcement_order.find("resume_cpr"), "no-shock announcement emitted before outcome is consumed")
	check(announcement_order.count("aed_no_shock") == 1, "no-shock announcement is not duplicated by pre/post sync")
	check(scenario.state == NaretScenario.State.CPR, "no-shock decision also resumes CPR automatically")
	check(scenario.cycle_compressions == 0 and scenario.compressions == 18, "no-shock return resets set and keeps total too")
	check("zero" in NaretTrainingCoach.current_instruction(scenario, "en"), "same fresh-set guidance after no shock")
	scenario.compression_only = true
	check("compression-only" in NaretTrainingCoach.current_instruction(scenario, "en"), "continuous mode does not instruct a thirty-to-two restart")
	device.reset()
	check(not device.powered and not device.pads_ready() and not model.visible, "reset removes stored power, pads and visibility")
	# The errand ends while the trainee is pressing: he waits for the pause, then offers.
	var request := ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "request_aed"]
	var press := func(): scenario.submit_action("compression", {"source": "test"})
	scenario.compression_only = false
	scenario.start()
	scenario.compression_only = false
	for action in request: scenario.submit_action(action)
	for seconds in [1.9, 5.0, 8.2, 10.0]: director.advance(seconds)
	press.call()
	director.advance(0.1)
	check(director.phase == "wait" and not device.offered and device._held, "he waits with the device while the trainee presses")
	press.call()
	director.advance(1.0)
	check(director.phase == "wait" and not device.offered, "a second after a stroke the set is not over")
	director.advance(1.0)
	check(director.phase == "offer" and device.offered, "he holds it out once the pressing stops")
	press.call()
	director.advance(0.1)
	check(director.phase == "wait" and not device.offered, "pressing again sends him back to waiting")
	director.advance(2.0)
	check(director.phase == "offer" and device.offered, "he offers again at the next pause")
	director.advance(7.0)
	check(director.phase == "offer", "he holds it out for 8 s")
	director.advance(1.1)
	check(director.phase == "walk_in" and not device.offered, "an offer nobody takes ends with him setting it down")
	director.advance(10.0)
	director.advance(2.0)
	check(director.delivered and scenario.aed_available and not device._held, "he sets it down beside the patient himself")
	director.advance(2.0)
	director.advance(10.0)
	# Pressing without any pause: he gives up waiting.
	device.reset()
	scenario.start()
	scenario.compression_only = false
	for action in request: scenario.submit_action(action)
	for seconds in [1.9, 5.0, 8.2, 10.0]: director.advance(seconds)
	for i in 41:
		press.call()
		director.advance(1.0)
	check(director.phase == "walk_in" and not device.offered, "after 40 s without a pause he sets it down himself")
	director.advance(10.0)
	director.advance(2.0)
	director.advance(2.0)
	director.advance(10.0)
	# Compression-only CPR has no pause to wait for.
	device.reset()
	scenario.start()
	scenario.compression_only = true
	for action in request: scenario.submit_action(action)
	for seconds in [1.9, 5.0, 8.0]: director.advance(seconds)
	press.call()
	director.advance(0.2)
	check(director.phase == "walk_in" and not device.offered, "compression-only: he sets it down without waiting")
	device.reset()
	# Default: no hand-over, he sets the device down himself although the hands are free.
	director.hand_over = false
	device.reset()
	scenario.start()
	scenario.compression_only = false
	for action in request: scenario.submit_action(action)
	for seconds in [1.9, 5.0, 8.2]: director.advance(seconds)
	check(director.phase == "walk_in" and not device.offered, "by default Marek takes it to its place himself")
	for seconds in [10.0, 2.0]: director.advance(seconds)
	check(director.delivered and scenario.aed_available and not device._held, "and puts it down there")
	for seconds in [2.0, 10.0]: director.advance(seconds)
	device.reset()
	# Default return: not before the first set is nearly done.
	director.return_after_compressions = 22
	device.reset()
	scenario.start()
	scenario.compression_only = false
	for action in request: scenario.submit_action(action)
	for seconds in [1.9, 5.0, 30.0]: director.advance(seconds)
	check(director.away and not director.presenting, "asked at the call, Marek stays away while nobody has pressed")
	for i in 22: scenario.submit_action("compression", {"source": "test"})
	director.advance(0.1)
	check(not director.away and director.presenting, "he walks in when the first set is nearly done (22 of 30)")
	for seconds in [10.0, 2.0, 2.0, 10.0]: director.advance(seconds)
	director.return_after_compressions = 0
	device.reset()
	# One sentence for both helpers.
	check(Requests.mentions_aed_fetch("Anna, please call 112 and Mark, bring the AED") and Requests.mentions_emergency_call("Anna, please call 112 and Mark, bring the AED"), "both helpers are heard in one sentence")
	check(Requests.mentions_aed_fetch("Marek, hol bitte den Defibrillator") and Requests.mentions_aed_fetch("Marek, przynieś defibrylator"), "the fetch is heard in German and Polish")
	check(not Requests.mentions_aed_fetch("Do not bring the AED") and not Requests.mentions_aed_fetch("Anna, please call 112"), "a negation or a call alone sends nobody for the AED")
	var for_anna: String = Requests.without_aed_clause("Anna, please call 112 and Mark, bring the AED")
	check("112" in for_anna and not "AED" in for_anna, "the call is left for Anna (got '%s')" % for_anna)
	# Walking round people and things.
	marek.global_position = Vector3.ZERO
	var far: Array[Vector3] = [Vector3(0, 0, 2)]
	marek.obstacles = func(): return [{"point": Vector2(0.05, 1.0), "radius": 0.3}]
	var round: Array[Vector3] = marek._around_obstacles(Vector3.ZERO, far)
	check(round.size() == 2 and round[0].x < -0.55 and absf(round[0].z - 1.0) < 0.05, "a person in the path is passed on the nearer side, 30 cm clear")
	marek.obstacles = func(): return [{"point": Vector2(0.1, 0.4), "radius": 0.3}]
	check(marek._around_obstacles(Vector3.ZERO, far).size() == 2, "a person one step from his start is still gone round")
	marek.obstacles = func(): return [{"point": Vector2(0.0, 2.3), "radius": 0.3}, {"point": Vector2(1.5, 1.0), "radius": 0.3}]
	check(marek._around_obstacles(Vector3.ZERO, far).size() == 1, "what he walks up to, or what stands aside, adds no detour")
	# Where he stands to set the device down is never on the patient, whatever the
	# play boundary would prefer.
	marek.obstacles = func(): return [{"point": Vector2(patient.global_position.x, patient.global_position.z), "radius": 0.28}]
	director.keep_in_room = func(_point: Vector3): return patient.global_position # a boundary that pulls everything onto the patient
	var stand: Vector3 = director._set_down_stand()
	check(Vector2(stand.x - patient.global_position.x, stand.z - patient.global_position.z).length() >= 0.28 + NaretBystander.BODY_CLEAR_M, "the boundary cannot put his standing place on the patient (%.2f m away)" % Vector2(stand.x - patient.global_position.x, stand.z - patient.global_position.z).length())
	# He leaves out past the stool and comes back the same way, whatever the boundary.
	var leave: Vector3 = director._leave_point()
	var out_dir: Vector3 = director._outward()
	var step := Vector3(leave.x - stand.x, 0.0, leave.z - stand.z)
	check(step.length() > 0.9 and step.normalized().dot(out_dir) > 0.99, "he leaves straight out past where he sets the device down, on the line from the patient through the stool")
	director.keep_in_room = func(point: Vector3): return point
	marek.obstacles = Callable()
	# Bodies are solid: someone exactly in his way, whom the plan did not know about.
	marek.global_position = Vector3.ZERO
	marek.obstacles = Callable()
	marek.walk_to(Vector3(0, 0, 2))
	var in_the_way := Vector2(0.0, 1.0)
	marek.obstacles = func(): return [{"point": in_the_way, "radius": 0.3}]
	var nearest := INF
	for i in 400:
		if not marek.is_walking(): break
		marek._walk(0.02)
		nearest = minf(nearest, Vector2(marek.global_position.x, marek.global_position.z).distance_to(in_the_way))
	check(nearest >= 0.3 + NaretBystander.BODY_CLEAR_M - 0.01, "he never walks through a body in his way (nearest %.2f m)" % nearest)
	check(not marek.is_walking() and marek.global_position.distance_to(Vector3(0, marek.global_position.y, 2)) < 0.06, "and still arrives, round it")
	marek.obstacles = Callable()
	for words in ["Marek, please bring the AED.", "Marek, bring bitte den AED.", "Marek, przynieś AED."]:
		check(Requests.aed_action_for(words) == "request_aed", "explicit helper request " + words)
	check(Requests.aed_action_for("I will check whether everyone is clear") == "", "intention is not clearance")
	check(Requests.aed_action_for("Do not bring the AED") == "", "negation is not a request")
	var meaning := {"action": "request_aed", "kind": "request", "result": "none", "evidence": "fetch the defibrillator"}
	check(Interpreter.accepted_action(meaning, "Could Marek fetch the defibrillator?") == "request_aed", "LLM can route varied wording to Marek request")
	for utterance in ["Could Marek fetch the defibrillator?", "Marek, kannst du bitte den Defibrillator holen?", "Marek, czy możesz przynieść defibrylator?"]:
		var raw := JSON.stringify({"action":"request_aed", "kind":"request", "result":"none", "evidence":utterance})
		check(Interpreter.accepted_action(Interpreter.parse(raw, utterance), utterance) == "request_aed", "varied request protocol " + utterance)
	for utterance in ["Nobody is touching him now", "Alle sind zurückgetreten", "Wszyscy się odsunęli"]:
		var raw := JSON.stringify({"action":"clear_patient", "kind":"request", "result":"none", "evidence":utterance})
		check(Interpreter.accepted_action(Interpreter.parse(raw, utterance), utterance) == "clear_patient", "varied clearance protocol " + utterance)
	for kind in ["question", "intention", "uncertain"]:
		var unclear := {"action":"clear_patient", "kind":kind, "result":"none", "evidence":"clear"}
		check(Interpreter.accepted_action(unclear, "I will check they are clear") == "", "non-confirmation cannot clear patient " + kind)
	meaning.action = "shock"
	check(Interpreter.accepted_action(meaning, "Shock") == "", "speech cannot deliver a shock")
	for lang in ["en", "de", "pl"]:
		for key in ["aed_apply", "aed_clear", "aed_analyse", "aed_shock_clear", "aed_countdown", "aed_resume"]:
			check(not NaretTrainingCoach.instruction(key, lang).is_empty(), "interactive AED guidance " + lang + " " + key)
	for node in [director, device, world, anna, marek, patient, scenario]: node.free()
	return failures
