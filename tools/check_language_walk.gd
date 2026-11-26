extends SceneTree
## Walks the training in one language through all four combinations of Situation (A / B) and
## ventilation (with / without) and lists, step by step, the instruction the trainee gets:
## whether it has a text in that language (and not the English one) and a recorded voice
## clip (20 Nov 2026, user: "check whether German works in all combinations"):
##   godot --headless --path . --xr-mode off --script tools/check_language_walk.gd -- --lang de
## Prints one line per step and "WALK_RESULT ok" or "WALK_RESULT problems=<n>".

var _lang := "de"
var _manager: NaretAudioManager
var _problems := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--lang" and index + 1 < args.size(): _lang = args[index + 1]
	_manager = NaretAudioManager.new()
	root.add_child(_manager)
	_run.call_deferred()

func _note(scenario: NaretScenario, combination: String, where: String) -> void:
	var key := NaretTrainingCoach.current_key(scenario)
	var text := NaretTrainingCoach.instruction(key, _lang)
	var english := NaretTrainingCoach.instruction(key, "en")
	var has_text := not text.is_empty() and (_lang == "en" or text != english)
	var clip: bool = _manager._coach_clips.get(_lang + ":instructor:" + text) is AudioStream
	# After the call the dispatcher gives the CPR steps in her own words and voice.
	var dispatcher_key := "dispatcher_" + key
	var dispatcher_text := NaretTrainingCoach.instruction(dispatcher_key, _lang)
	var dispatcher := ""
	if not dispatcher_text.is_empty() and dispatcher_text != NaretTrainingCoach.instruction(dispatcher_key, "en"):
		var dispatcher_clip: bool = _manager._coach_clips.get(_lang + ":dispatcher:" + dispatcher_text) is AudioStream
		dispatcher = "  dispatcher voice=%s" % ("yes" if dispatcher_clip else "NO")
		if not dispatcher_clip: _problems += 1
	if not has_text or not clip: _problems += 1
	print("WALK %s | %-22s | %-18s | text=%s voice=%s%s | %s" % [combination, where, key, "yes" if has_text else "NO", "yes" if clip else "NO", dispatcher, text.left(60)])

func _run() -> void:
	await process_frame
	for situation in ["A", "B"]:
		for breaths in ["yes", "no"]:
			var combination := "%s/%s" % [situation, "breaths" if breaths == "yes" else "no-breaths"]
			var scenario := NaretScenario.new()
			root.add_child(scenario)
			scenario.alone = situation == "A"
			scenario.start()
			# As main._apply_setup_to_scenario does after start.
			scenario.compression_only = breaths == "no"
			scenario.set_meta("situation", situation)
			scenario.aed_available = false
			_note(scenario, combination, "start (safety)")
			scenario.submit_action("begin_check")
			_note(scenario, combination, "response")
			scenario.submit_action("check_responsiveness")
			_note(scenario, combination, "call")
			scenario.submit_action("call_emergency")
			_note(scenario, combination, "breathing")
			scenario.submit_action("check_breathing")
			_note(scenario, combination, "first compressions")
			var press := {"source": "hand_tracking", "measurement_verified": false}
			for i in 30: scenario.submit_action("compression", press)
			_note(scenario, combination, "after 30")
			if breaths == "yes":
				scenario.submit_action("ventilation")
				_note(scenario, combination, "after breath 1")
				scenario.submit_action("ventilation")
			_note(scenario, combination, "next cycle")
			if situation == "B":
				scenario.submit_action("request_aed")
				scenario.aed_available = true
				_note(scenario, combination, "AED arrived")
				scenario.submit_action("attach_aed")
				_note(scenario, combination, "AED attached")
				for action in ["clear_patient", "analyze_rhythm", "clear_patient", "shock", "resume_cpr"]:
					if scenario.state != NaretScenario.State.AED: break
					if scenario.get_available_actions().has(action): scenario.submit_action(action)
				_note(scenario, combination, "after the AED")
				for i in 5: scenario.submit_action("compression", press)
				_note(scenario, combination, "CPR after the AED")
			scenario.submit_action("handover")
			_note(scenario, combination, "handover")
			scenario.queue_free()
	# The AED's own voice and the texts shown with it.
	for key in ["aed_apply", "aed_clear", "aed_resume", "aed_resume_only", "aed_request", "aed_pads_how"]:
		var path := "res://assets/audio/coaching/%s/%s.wav" % [_lang, key]
		var there := ResourceLoader.exists(path)
		if not there: _problems += 1
		print("WALK AED clip %-18s %s" % [key, "yes" if there else "NO"])
	print("WALK_RESULT ", "ok" if _problems == 0 else "problems=%d" % _problems, " language=", _lang)
	quit()
