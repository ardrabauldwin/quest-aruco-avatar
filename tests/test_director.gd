extends "res://tests/suite.gd"
## Plays scenario 1 of docs/DREHBUCH.md at fast-forward and checks that Anna and
## Marek say the right lines at the right moments, and that the AED only becomes
## usable after Marek brought it.

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
	check(director.line_text("marek_call", "pl").contains("112"), "every line exists in both languages")

	scenario.start()
	check(said.has("anna_arrive"), "1.1 Anna calls for help when the scene starts")
	check(not scenario.aed_available, "the AED is not on scene before anyone fetched it")
	director.advance(9.0)

	scenario.submit_action("begin_check")
	scenario.submit_action("check_responsiveness")
	director.advance(3.0)
	check(said.has("marek_offer"), "1.3 Marek offers help once Jan does not respond")
	director.advance(16.0)
	check(said.has("marek_prompt_call"), "1.4 Marek offers to call 112 when nobody asks him")
	scenario.submit_action("call_emergency")
	check(said.has("marek_call"), "1.4 Marek calls 112 on speaker (ERC 2025: before the breathing check)")
	director.advance(NaretBystanderDirector.AGONAL_AFTER_S + 0.5)
	check(said.has("anna_agonal"), "1.5 Jan gasps once and Anna takes it for breathing")
	director.advance(2.0)
	check(said.has("marek_dispatch"), "1.5 the dispatcher asks whether he breathes normally")
	director.advance(NaretBystanderDirector.BREATH_CHECK_S)
	check(said.has("anna_breathing"), "1.5 Anna presses when the breathing check drags on")
	scenario.submit_action("check_breathing")

	# 26 Nov 2026: no praise and no rate corrections during compressions any more.
	for i in 20:
		scenario.submit_action("compression", {"rate_bpm": 110.0, "source": "test"})
	check(not said.has("anna_good"), "1.7 Anna does not comment on good compressions")
	for i in 4:
		scenario.submit_action("compression", {"rate_bpm": 85.0, "source": "test"})
	check(not said.has("marek_faster"), "1.8 nobody asks for a faster rate")
	director.advance(15.0)
	check(said.has("anna_pause"), "1.11 Anna protests a pause longer than 10 s")
	check(said.has("marek_prompt_aed"), "1.6 Marek offers to fetch an AED nobody asked for")

	scenario.submit_action("request_aed")
	check(said.has("marek_go_aed"), "1.6 Marek leaves for the AED")
	check(not scenario.submit_action("attach_aed") and scenario.last_error == "error.aed_missing", "the AED cannot be applied before it arrives")
	director.advance(NaretBystanderDirector.FETCH_S + 1.0)
	check(scenario.aed_available, "the AED is usable once it was brought")
	check(scenario.submit_action("attach_aed"), "applying the brought AED")

	scenario.submit_action("clear_patient")
	check(said.has("anna_touch"), "1.13 Anna steps in during the analysis")
	director.on_intent("keep_clear")
	check(said.has("anna_sorry") and scenario.aed_stage == NaretScenario.AEDStage.READY_TO_ANALYZE, "1.14 a spoken 'Abstand' sends Anna back and keeps the clearance")
	check(preload("res://scripts/scenario/spoken_observation.gd").infer_action("Abstand! Nicht berühren!") == "keep_clear", "'Abstand, nicht berühren' is understood")
	check(preload("res://scripts/scenario/spoken_observation.gd").infer_action("Proszę się odsunąć!") == "keep_clear", "the Polish call to stand back is understood")

	scenario.submit_action("analyze_rhythm")
	scenario.submit_action("clear_patient")
	scenario.submit_action("shock")
	director.advance(0.1) # no AED in this test: quiet at once, the line follows
	director.advance(0.5)
	check(said.has("anna_shock"), "1.15 Anna is startled by the shock (after the AED's announcement)")
	director.advance(6.0)
	check(said.has("marek_resume"), "1.15 Marek urges to resume when nobody compresses after the shock")
	scenario.submit_action("compression", {"rate_bpm": 110.0, "source": "test"})
	scenario.advance_simulation(NaretScenario.AED_REASSESS_SECONDS)
	director.advance(0.1)
	check(said.has("marek_swap"), "1.16 Marek offers to swap when the two minutes are up, before the AED interrupts")
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
	check(said.has("anna_sorry"), "1.13 Anna apologises after touching Jan")

	director.free()
	scenario.free()
	return failures
