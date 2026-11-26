extends "res://tests/suite.gd"
## Plays scenario 1 of docs/DREHBUCH.md at fast-forward and checks that Anna and
## Marek say the right lines at the right moments, and that the AED only becomes
## usable after Marek brought it.
## 26 Nov 2026: the live app uses aed_helper_director; the scene lines this base script
## used to say were removed, so only its non-speech behaviour is checked here.

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var scenario := NaretScenario.new()
	tree.root.add_child(scenario)
	scenario.set_process(false)
	var director := NaretBystanderDirector.new()
	tree.root.add_child(director)
	director.set_process(false)
	director.configure(scenario, null, null, null, null)
	var said: Array[String] = []
	director.line_spoken.connect(func(key: String, _speaker: String): said.append(key))
	check(not director.line_text("marek_go_aed", "pl").is_empty(), "every line exists in both languages")

	scenario.start()
	check(said.has("anna_arrive"), "1.1 Anna calls for help when the scene starts")
	check(not scenario.aed_available, "the AED is not on scene before anyone fetched it")
	director.advance(9.0)

	scenario.submit_action("begin_check")
	scenario.submit_action("check_responsiveness")
	director.advance(3.0)
	director.advance(16.0)
	scenario.submit_action("call_emergency")
	director.advance(NaretBystanderDirector.AGONAL_AFTER_S + 0.5)
	director.advance(2.0)
	director.advance(NaretBystanderDirector.BREATH_CHECK_S)
	scenario.submit_action("check_breathing")

	# 26 Nov 2026: no praise and no rate corrections during compressions any more.
	for i in 20:
		scenario.submit_action("compression", {"rate_bpm": 110.0, "source": "test"})
	check(not said.has("anna_good"), "1.7 Anna does not comment on good compressions")
	for i in 4:
		scenario.submit_action("compression", {"rate_bpm": 85.0, "source": "test"})
	check(not said.has("marek_faster"), "1.8 nobody asks for a faster rate")
	director.advance(15.0)

	scenario.submit_action("request_aed")
	check(said.has("marek_go_aed"), "1.6 Marek leaves for the AED")
	check(not scenario.submit_action("attach_aed") and scenario.last_error == "error.aed_missing", "the AED cannot be applied before it arrives")
	director.advance(NaretBystanderDirector.FETCH_S + 1.0)
	check(scenario.aed_available, "the AED is usable once it was brought")
	check(scenario.submit_action("attach_aed"), "applying the brought AED")

	scenario.submit_action("clear_patient")
	director.on_intent("keep_clear")
	check(scenario.aed_stage == NaretScenario.AEDStage.READY_TO_ANALYZE, "1.14 keeps the clearance")
	check(preload("res://scripts/scenario/spoken_observation.gd").infer_action("Abstand! Nicht berühren!") == "keep_clear", "'Abstand, nicht berühren' is understood")
	check(preload("res://scripts/scenario/spoken_observation.gd").infer_action("Proszę się odsunąć!") == "keep_clear", "the Polish call to stand back is understood")

	scenario.submit_action("analyze_rhythm")
	scenario.submit_action("clear_patient")
	scenario.submit_action("shock")
	director.advance(0.1) # no AED in this test: quiet at once, the line follows
	director.advance(0.5)
	director.advance(6.0)
	scenario.submit_action("compression", {"rate_bpm": 110.0, "source": "test"})
	scenario.advance_simulation(NaretScenario.AED_REASSESS_SECONDS)
	director.advance(0.1)
	scenario.submit_action("reassess")

	# A second run: without the spoken warning Anna touches Jan and voids the clearance.
	scenario.start()
	said.clear()
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "request_aed"]:
		scenario.submit_action(action)
	director.advance(NaretBystanderDirector.FETCH_S + 1.0)
	scenario.submit_action("attach_aed")
	scenario.submit_action("clear_patient")
	director.advance(NaretBystanderDirector.INTRUDE_S + 0.5)
	director.advance(2.0)
	check(scenario.aed_stage == NaretScenario.AEDStage.ATTACHED and scenario.last_error == "error.contact_during_analysis", "1.13 Anna's touch voids the clearance when nobody warns her")

	director.free()
	scenario.free()
	return failures
