extends Node3D
@export_file("*.cfg") var marker_layout_file := ""
## Scene composition. AI supplies dialogue/guidance; guarded observations control progression.

@onready var mannequin: NaretMannequin = $SpatialAnchor/Mannequin
@onready var anchor: NaretSpatialAnchor = $SpatialAnchor
@onready var origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var desktop_camera: Camera3D = $DesktopCamera
var scenario: NaretScenario
var ccbm: Node
var observation_interpreter: Node
var ekg: NaretEKG
var api: NaretUniAPIClient
var audio_manager: NaretAudioManager
var llm: NaretLLMOrchestrator
var xr: NaretOpenXRSetup
var tracker: NaretArucoTracker
var interaction: NaretXRInteraction
var performance: NaretPerformanceMonitor
var score := NaretScoreTracker.new()
var logger := NaretSessionLogger.new()
var dashboard: NaretDashboard
var xr_info: NaretXRInfo
var hand_menu: NaretHandMenu
var aed: NaretAED
var director: NaretBystanderDirector
var room: NaretRoomLayout
var floor_touch: NaretFloorTouch
var chest_touch: NaretChestTouch
## Automatic floor height and its source, before the fingertip offset.
var _floor_source := ""
var _floor_source_y := NAN
var _stable_floor := preload("res://scripts/tracking/stable_floor_reference.gd").new()
var qcpr: NaretQcprManager
var qcpr_debug_panel: NaretQcprDebugPanel
var _info_viewport: SubViewport
## The bedside panel only appears while a modal (calibration, briefing) is on it.
var _info_surface: MeshInstance3D
var _aed_announced := false
var _ui_layer: CanvasLayer
var _bystanders_placed_at := Vector3(INF, INF, INF)
var _bystanders_placed_anchors := -1
var _spot_timer := 0.0
var _pending_training_action := ""
## User-selected visible defaults. This mode does not infer walls or furniture.
@export var default_character_placement := false
var _default_character_spots: Dictionary = {}
const SpeakerPlacement = preload("res://scripts/tracking/speaker_placement.gd")
var _speaker_envelope := preload("res://scripts/tracking/speaker_body_envelope.gd").new()
var _speaker_issue := ""
var _speaker_view: Dictionary = {}
var _speaker_plan_signature := 0
var _speaker_assigned: Dictionary = {}
const SpeakerPoseSnapshot = preload("res://scripts/tracking/speaker_pose_snapshot.gd")

const CONTROLLER_NUDGE_MPS := 0.04
const CONTROLLER_YAW_DPS := 10.0
const CONTROLLER_DEAD_ZONE := 0.20
var _language := "de"
## Own language first, as in the learning platform: the procedure is learned
## without foreign-language load before the neighbour language is added.
var _mode := "own"
var _rotation := 0.68
var _elevation := 0.87
var _distance := 3.3
var _dragging := false
var _last_compression_ms := 0
var _ui_timer := 0.0
var _modal: Control
var _api_latencies: Array[Dictionary] = []
var _last_tracking_status := "desktop_preview"
var _last_service_status := "offline"
var _speech_confirmation := preload("res://scripts/ai/speech_pipeline.gd").Confirmation.new()
var _fsm := NaretCprStateMachine.new()
const FSM_ACTIONS := ["start", "reset", "begin_check", "check_responsiveness", "call_emergency", "check_breathing", "compression", "ventilation", "compression_only", "handover", "reassure"]
var _last_heard_report := ""
## Steps still to take from one utterance that named several ("The scene is safe. He is not
## responding."): the next one is handed to the planner when the previous was accepted.
var _pending_sequence: Array[String] = []
var _smoke_mode := false


func _ready() -> void:
	var speaker_guard := preload("res://scripts/tracking/speaker_placement_guard.gd").new()
	speaker_guard.name = "SpeakerPlacementGuard"
	speaker_guard.validate = _validate_speakers
	add_child(speaker_guard)
	_smoke_mode = "--smoke-test" in OS.get_cmdline_user_args()
	_build_room()
	xr = NaretOpenXRSetup.new()
	add_child(xr)
	scenario = NaretScenario.new()
	scenario.cpr_witness_only = false
	scenario.observation_driven = true
	add_child(scenario)
	ccbm = preload("res://scripts/scenario/ccbm_bridge.gd").new()
	ccbm.configure(scenario)
	add_child(ccbm)
	ccbm.decision.connect(_on_action)
	ccbm.status_changed.connect(_on_ccbm_status)
	ccbm.tracking_updated.connect(func(posterior: Dictionary):
		print("NARET_CCBM_TRACK action=", posterior.get("action", ""), " probability=", posterior.get("probability", 0), " observations=", posterior.get("observation_count", 0)))
	ekg = NaretEKG.new()
	add_child(ekg)
	ekg.set_rhythm(NaretEKG.Rhythm.VF)
	ekg.beat.connect(mannequin.heart.pulse)
	aed = NaretAED.new()
	add_child(aed)
	aed.configure($AED, mannequin)
	aed.manual_pad_placement_required = xr.active
	aed.preview_visible = default_character_placement and not xr.active
	aed.ekg = ekg
	aed.requested.connect(func(action: String): _on_action(action, {"source": "aed_device"}))
	# QCPR manikin data: today over the laptop bridge (tools/qcpr_probe.py --udp), later a
	# native plugin. While the manikin delivers, its strokes and depth replace the
	# hand-tracked ones (9 Nov 2026: hand tracking counts and times strokes reliably but
	# cannot measure depth).
	qcpr = NaretQcprManager.new()
	qcpr.name = "Qcpr"
	add_child(qcpr)
	qcpr.scenario = scenario
	qcpr.compression_measured.connect(_on_qcpr_compression)
	qcpr.quality_feedback.connect(_on_qcpr_quality_feedback)
	qcpr.backend_changed.connect(func(backend_name: String, _sim: bool): print("NARET_QCPR backend=", backend_name))
	aed.external_speech_busy = func(): return audio_manager != null and (bool(audio_manager.get("_playing")) or bool(audio_manager.get("_preparing")) or not audio_manager.get("_pending").is_empty())
	aed.spoke.connect(func(key: String, lang: String):
		var text := director.line_text(key, lang) if director else key
		_toast(text)
		if not _smoke_mode and not ResourceLoader.exists("res://assets/audio/tts_%s/%s.wav" % [lang, key]):
			audio_manager.speak(text, lang, "", "aed")
		if key == "aed_pads" and not _smoke_mode:
			# The device has just said "attach the pads"; the instructor says how, after it.
			get_tree().create_timer(AED_PADS_HOW_AFTER_S).timeout.connect(func(): _pad_guidance("")))
	aed.pad_missed.connect(func(_pad_name: String): _pad_guidance("missed"))
	director = load("res://scripts/scenario/aed_helper_director.gd").new()
	add_child(director)
	director.configure(scenario, $Bystanders/Anna, $Bystanders/Marek, mannequin, aed)
	director.delivery_ready = _prepare_aed_delivery
	director.keep_in_room = _keep_in_play_area
	aed.rest_height = _aed_rest_y
	# Marek shares the instructor's model and clips; he gets the instructor's calm
	# listening/talking behaviour instead of the anxious loop, and his own look.
	# "attentive", not "calm": "calm" first plays the relief clip, which leans him 22 cm
	# backward, and the first talking take leans back 15 cm (measured 13 Nov 2026 after
	# the headset review "he leans backward"). He stands upright or leans forward only.
	$Bystanders/Marek.set_emotion("attentive")
	$Bystanders/Marek.drop_talk_takes(["talk"])
	for person in _speaker_people(): person.obstacles = _walk_obstacles.bind(person)
	aed.rest_at_home = true
	var beard := "res://assets/models/human_bystander_marek_skin.png"
	$Bystanders/Marek.set_look(MAREK_SHIRT, load(beard) as Texture2D if ResourceLoader.exists(beard) else null)
	# Picked out by what they wear (issue #1): Anna in the red jacket calls 112, Marek with
	# the blue backpack fetches the AED.
	$Bystanders/Anna.set_look(ANNA_JACKET)
	$Bystanders/Marek.add_backpack.call_deferred(MAREK_BACKPACK)
	# One short sentence when the AED is there, and the pads only after it is switched
	# on (see aed.spoke below). The former text explained power, both pads, the outlines
	# and the whole shock pattern in one 40 s speech that every CPR prompt cut off.
	# (Restored 26 Nov 2026: the AED helper director says only "I have brought the
	# defibrillator", so this is the one line that says to switch it on.)
	director.device_delivered.connect(func():
		var guidance := NaretTrainingCoach.instruction("aed_arrived", _language)
		_toast(guidance)
		if not _smoke_mode: audio_manager.speak(guidance, _language, "", "instructor"))
	# The instructor is a speaker, not a second rescuer in the scenario.
	$Instructor.patient = mannequin
	$Instructor.attention = "trainee"
	$Instructor.set_emotion("calm")
	director.language = bystander_language
	director.trainee = func(): return (xr_camera if xr.active else desktop_camera).global_position
	# He goes when his sentence is said: not yet while it waits or is being spoken.
	director.answer_waiting = func(): return audio_manager != null and (audio_manager.urgent_waiting() or audio_manager.answer_playing() or audio_manager.has_line(_marek_go_text))
	director.speak = func(key: String, text: String, lang: String, speaker: String):
		# Marek's "I'll get the AED" answers the trainee: it does not queue behind the
		# dispatcher's and the instructor's lines (20 Nov 2026: "it comes much later").
		# Asked after Anna in the same sentence, it takes its turn after her answer.
		if _smoke_mode: return
		if key == "marek_go_aed":
			_marek_go_text = text
			if _marek_answers_in_turn: audio_manager.speak(text, lang, key, speaker)
			else: audio_manager.speak_urgent(text, lang, key, speaker)
		else: audio_manager.speak(text, lang, key, speaker)
	scenario.event_recorded.connect(_on_event)
	if "cprwitness.fsm" in OS.get_user_data_dir(): # Only the side-by-side FSM app runs it.
		scenario.event_recorded.connect(_shadow_state_machine)
	_fsm.state_changed.connect(func(_from: int, _to: int, input: String):
		print("NARET_FSM state=", _fsm.state_name(), " input=", input)
		_toast("State: " + _fsm.state_name()))
	scenario.state_changed.connect(_on_state_changed)
	api = NaretUniAPIClient.new()
	add_child(api)
	api.status_changed.connect(_on_service_status)
	api.request_finished.connect(func(service: String, success: bool, latency: int):
		_api_latencies.append({"service": service, "success": success, "latency_ms": latency})
		if _api_latencies.size() > 100: _api_latencies.pop_front())
	audio_manager = NaretAudioManager.new()
	audio_manager.configure(api)
	add_child(audio_manager)
	audio_manager.transcript_ready.connect(_on_transcript)
	audio_manager.status_changed.connect(_on_service_status)
	if xr.active:
		# The Quest system menu takes input focus; never record or send audio meanwhile.
		xr.interface.connect("session_focussed", func(): audio_manager.set_input_focus(true))
		xr.interface.connect("session_visible", func(): audio_manager.set_input_focus(false))
		xr.interface.connect("session_stopping", func(): audio_manager.set_input_focus(false))
		# The marker camera streams only while the session is focused. Without focus (system
		# menu, headset taken off) rendering pauses and the frames queue up in Java memory
		# until the process dies (2026-11-03).
		xr.interface.connect("session_focussed", func(): if tracker and not _camera_parked: tracker.set_camera_streaming(true))
		# The floor is the headset's boundary (Stage) floor. When the runtime recentres or
		# re-establishes that space, read the floor again so the characters follow it.
		if xr.interface.has_signal("pose_recentered"):
			xr.interface.connect("pose_recentered", _on_floor_space_changed)
		_start_watchdog()
		xr.interface.connect("session_visible", func(): if tracker: tracker.set_camera_streaming(false))
		xr.interface.connect("session_stopping", func(): if tracker: tracker.set_camera_streaming(false))
		if xr.interface.has_method("get_session_state"):
			audio_manager.set_input_focus(int(xr.interface.call("get_session_state")) == OpenXRInterface.SESSION_STATE_FOCUSED)
	audio_manager.recording_changed.connect(func(active: bool):
		if interaction: interaction.set_audio_busy(active or bool(audio_manager.get("_playing")))
		if dashboard: dashboard.set_recording(active)
		if hand_menu: hand_menu.set_recording(active))
	audio_manager.listening_changed.connect(func(active: bool):
		if hand_menu: hand_menu.set_listening(active))
	audio_manager.utterance_started.connect(func(text: String, _lang: String, source: String, speaker: String):
		print("NARET_AUDIO_STARTED language=", _lang, " source=", source)
		$Bystanders/Anna.speaking = speaker in ["bystander", "anna"]
		$Instructor.speaking = speaker == "instructor"
		$Bystanders/Marek.speaking = speaker == "marek"
		# The breathing instruction comes from the dispatcher (26 Nov 2026: the instructor's
		# own version was removed, and this check only knew that one, so the follow-up
		# breathing question never started).
		if not text.is_empty() and text in [NaretTrainingCoach.instruction("breathing", _language), NaretTrainingCoach.instruction("dispatcher_breathing", _language)]: _breathing_told = true
		if text == NaretTrainingCoach.instruction("response", _language) and not _response_asked:
			_response_asked = true
			_response_asked_ms = Time.get_ticks_msec()
		if text == NaretTrainingCoach.instruction("call_alone", _language) and _call_asked_ms == 0:
			_call_asked_ms = Time.get_ticks_msec()
		if text == NaretTrainingCoach.instruction("safety", _language):
			_safety_asked = true
			_safety_asked_ms = Time.get_ticks_msec()
		_record_speech_status("voice_started_" + speaker)
		if speaker in ["bystander", "anna"]: _show_reply(text, source)
		# Every spoken line is listed in the dialogue on the palm, with who said it.
		_dialogue_line(speaker, text))
	audio_manager.playback_changed.connect(func(active: bool):
		if interaction: interaction.set_audio_busy(active or audio_manager.recording)
		if not active:
			_voice_end_ms = Time.get_ticks_msec()
			$Bystanders/Anna.speaking = false
			$Instructor.speaking = false
			$Bystanders/Marek.speaking = false)
	llm = NaretLLMOrchestrator.new()
	llm.single_witness = false
	llm.configure(api)
	add_child(llm)
	llm.reply_ready.connect(_on_reply)
	llm.status_changed.connect(_on_service_status)
	observation_interpreter = preload("res://scripts/ai/speech_pipeline.gd").new()
	observation_interpreter.configure(api)
	add_child(observation_interpreter)
	observation_interpreter.observation_ready.connect(_on_spoken_action)
	observation_interpreter.safety_statement.connect(func(): _safety_statement("cloud"))
	# Explicit witness questions are already routed to Anna in _on_transcript.
	# An unclear exercise report needs the instructor, not unrelated witness chat.
	observation_interpreter.conversation.connect(func(_text: String):
		# Questions, uncertainty and anything else that is no report go to the instructor
		# with the help context (18 Nov 2026): he helps with the missing action or asks a
		# short clarification question, instead of repeating the step text. At most every 6 s,
		# so background talk cannot keep him talking.
		if not _smoke_mode and Time.get_ticks_msec() - _help_asked_ms > 6000:
			_help_asked_ms = Time.get_ticks_msec()
			_queue_coach_question(_text)
			return
		# Help and witness questions were routed explicitly before classification.
		# Unclassified audio must not provoke generated clinical instructions.
		var step := NaretTrainingCoach.step(scenario)
		var guidance := NaretTrainingCoach.instruction(step, _language)
		# Steps without a line of their own (aed_countdown since 26 Nov 2026) stay silent.
		if guidance.is_empty(): return
		_toast(guidance)
		# The patient-side text panel is removed. Give audible feedback once per
		# step so an unrelated recognition cannot leave the learner in silence.
		# While the dispatcher leads she has just given it: no second voice saying it again.
		if not _smoke_mode and _unclassified_spoken_step != step and not _dispatcher_leads() and not _call_connecting():
			_unclassified_spoken_step = step
			audio_manager.speak(guidance, _language, "", "instructor"))
	observation_interpreter.clarification.connect(func(text: String):
		# A late "unclear" for a step that has moved on meanwhile is dropped: it asked the old
		# step's question over the new step's instruction (17 Nov 2026, Situation B: the
		# breathing instruction was lost after "Du mit der roten Jacke, ruf 112 an").
		if NaretTrainingCoach.step(scenario) != _transcript_step:
			print("NARET_CLARIFICATION dropped, step moved on to ", NaretTrainingCoach.step(scenario))
			return
		# A clear report with another finding ("he is breathing normally") is not a doubt: the
		# instructor answers it from the deviation guide instead of "no step confirmed".
		if not observation_interpreter.last_doubtful and not _last_heard_report.is_empty() and not _smoke_mode:
			_queue_coach_question(_last_heard_report)
			return
		# Unclear: with the cloud, the instructor asks a short clarification question in his own
		# words, with the help context (18 Nov 2026).
		if observation_interpreter.last_doubtful and not _smoke_mode and api.is_available(api.llm_model):
			_queue_coach_question(text)
			return
		if observation_interpreter.last_doubtful and not _smoke_mode:
			# Offline: say so, then ask the step's yes/no question.
			var heard := NaretLanguage.status("speech_not_understood", _language)
			_toast(heard)
			audio_manager.speak(heard, _language, "", _guide_speaker())
			if _ask_step_question():
				return
		if not api.local_ai_url.is_empty():
			text = NaretTrainingCoach.feedback(scenario, _last_heard_report, "unclear", _language)
		_toast(text)
		if not _smoke_mode:
			var clip := ""
			audio_manager.speak(text, bystander_language(), clip, _guide_speaker()))
	_build_ui()
	tracker = NaretArucoTracker.new()
	tracker.marker_layout_file = marker_layout_file
	# Without a camera the patient keeps its old spot; the preview is where its marker would sit.
	tracker.preview_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.2) if xr.active else Vector3.ZERO) * anchor.marker_to_mannequin.affine_inverse()
	if xr.active:
		anchor.viewer_head = xr_camera
		# A floor-based tracking space must be available before enabling floor lock.
		_refresh_floor_reference()
		tracker.apply_temporal_filter = false
	tracker.pose_updated.connect(_on_marker_pose)
	tracker.status_changed.connect(_on_tracking_status)
	tracker.set_view_camera(xr_camera if xr.active else desktop_camera)
	add_child(tracker)
	interaction = NaretXRInteraction.new()
	add_child(interaction)
	if xr.active: interaction.configure(mannequin, origin)
	interaction.aed = aed
	if xr.active:
		bvm = preload("res://scripts/mannequin/bvm_device.gd").new()
		mannequin.add_child(bvm)
		bvm.configure(mannequin)
		interaction.bvm = bvm
		bvm.breath_given.connect(func(): _on_action("ventilation", {"source": "hand_tracking", "measurement_verified": false}))
		bvm.squeeze_without_seal.connect(func(): _toast(NaretLanguage.text("coach.bvm_hold_mask", _language)))
		# No mask within 10 s of the offer, or no squeeze within 10 s of placing it: say what to do.
		bvm.grabbed.connect(func(): print("NARET_BVM grabbed"))
		bvm.placed.connect(func():
			get_tree().create_timer(10.0).timeout.connect(func():
				if bvm.is_placed() and bvm.breaths_recent() == 0 and NaretTrainingCoach.step(scenario) == "breaths" and not audio_manager.is_speaking():
					audio_manager.speak(NaretLanguage.text("coach.bvm_squeeze", _language), _language, "", _guide_speaker())))
	interaction.action_requested.connect(_on_xr_action)
	interaction.compression_measured.connect(_on_hand_compression)
	interaction.head_tilt_gesture_detected.connect(func():
		_toast("Head-tilt gesture detected — technique unverified"))
	# Face at the patient but no breathing report within 10 s: the step's yes/no question.
	interaction.face_checked.connect(func():
		# Only a look during the breathing step counts: the look at the face in the response
		# check (issue #1) asked this question before the breathing step had begun.
		if not (scenario and scenario.state == NaretScenario.State.CALL_HELP and scenario.emergency_called): return
		if not _breathing_polling:
			_breathing_polling = true
			_breathing_quiet_s = 0
			_poll_breathing_question())
	# The spoken "place your hands correctly ... on the yellow box" for a press beside the
	# box is gone (14 Nov 2026, "after placing and doing compressions the instructor says
	# place correctly, heels on yellow; remove it"). It came after the hands had been
	# placed right: one press measured beside the box, which the tracked hands' wobble
	# produces, was enough. The box itself still shows where the hands belong.
	# "Do not check longer than 10 seconds" after 10 s at the face was removed on 26 Nov 2026
	# (not needed); the signal face_check_long is no longer spoken.
	# Tape-measure check of hand tracking: pinch both hands on the two ends of a ruler.
	interaction.ruler_measured.connect(func(distance_m: float, left_tip_y: float, right_tip_y: float):
		var floor_y := _speaker_floor_y()
		print("NARET_RULER distance_cm=%.1f left_tip_above_floor_cm=%.1f right_tip_above_floor_cm=%.1f" % [distance_m * 100.0, (left_tip_y - floor_y) * 100.0, (right_tip_y - floor_y) * 100.0])
		_toast(NaretLanguage.ui("Messung: %.1f cm · Fingerspitzen %.0f / %.0f cm über dem Boden" % [distance_m * 100.0, (left_tip_y - floor_y) * 100.0, (right_tip_y - floor_y) * 100.0],
			"Pomiar: %.1f cm · opuszki %.0f / %.0f cm nad podłogą" % [distance_m * 100.0, (left_tip_y - floor_y) * 100.0, (right_tip_y - floor_y) * 100.0], _language)))
	interaction.placement_changed.connect(mannequin.set_hand_feedback)
	if xr.active:
		desktop_camera.current = false
		xr_camera.current = true
		# Use the real passthrough hands; tracking and CPR input remain active.
		# The coloured virtual hand meshes stay hidden unless the cuff's hands key
		# switches them on for testing.
		xr.install_hands(origin)
		xr.install_environment_depth(xr_camera)
		mannequin.set_overlay_opacity(anchor.patient_opacity)
		$Bystanders/Anna.visible = false # Wait for the real patient location.
		$Instructor.visible = false
		$Bystanders/Marek.visible = false
		$XROrigin3D/RightHand.button_pressed.connect(_on_alignment_button)
		_build_xr_ui()
		# Room scanning and saved-scene queries are disabled. Keep the floor and
		# patient tracking independent of room setup.
		if XRServer.has_signal("reference_frame_changed"):
			XRServer.reference_frame_changed.connect(_on_floor_space_changed)
		floor_touch = NaretFloorTouch.new()
		add_child(floor_touch)
		floor_touch.measured.connect(_on_floor_measured)
		floor_touch.failed.connect(func():
			hand_menu.set_floor_calibrating(false)
			_toast(NaretLanguage.ui("Boden nicht erkannt · erneut versuchen", "Nie wykryto podłogi · spróbuj ponownie", _language)))
		chest_touch = NaretChestTouch.new()
		add_child(chest_touch)
		chest_touch.measured.connect(_on_chest_measured)
		chest_touch.failed.connect(func():
			hand_menu.set_chest_calibrating(false)
			_toast(NaretLanguage.ui("Brust nicht erkannt · Hand flach auflegen", "Nie wykryto klatki · połóż płasko dłoń", _language)))
		# The physical room/floor remains visible through passthrough.
		$Room.visible = false
		# The speakers' shadows fall on that real floor instead. They follow the key
		# light's heading but come from steeply above, like diffuse ceiling light.
		var heading: Vector3 = -($KeyLight as Node3D).global_basis.z
		heading.y = 0.0
		var shadow_direction: Vector3 = heading.normalized() * cos(deg_to_rad(70.0)) + Vector3.DOWN * sin(deg_to_rad(70.0))
		for person: NaretBystander in [$Bystanders/Anna, $Instructor, $Bystanders/Marek]:
			person.cast_floor_shadow(shadow_direction)
		mannequin.cast_floor_shadow(shadow_direction)
	else:
		_update_camera()
	performance = NaretPerformanceMonitor.new()
	add_child(performance)
	performance.updated.connect(func(metrics: Dictionary):
		if dashboard: dashboard.set_performance(metrics))
	_set_language("de")
	_load_language_choice()
	_on_state_changed(scenario.state)
	# Voice activation is the default: a trainee doing compressions cannot hold a button.
	if not _smoke_mode: audio_manager.set_listening(true)
	_welcome()
	print("NARET_READY platform=%s xr=%s" % [OS.get_name(), xr.active])
	if _smoke_mode: _smoke_test.call_deferred()

func _refresh_marker_evidence() -> void:
	if anchor == null or tracker == null: return
	var hands_cover_chest := false
	if interaction != null and interaction._zone != null:
		hands_cover_chest = bool(interaction._zone.get("hand_over_chest"))
	anchor.full_marker_evidence = tracker.tracked and tracker.has_full_marker_evidence() and not hands_cover_chest

func _on_marker_pose(pose: Transform3D) -> void:
	_refresh_marker_evidence()
	anchor.update_pose(pose)
	# Marker diagnostics can keep streaming, but manual mode ignores poses after placement.
	# The out-of-memory crashes of 2026-11-03 came from frames queuing while nothing consumed
	# them; the stream stops without session focus and from the stall watchdog instead.

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)
	if not xr.active:
		dashboard = NaretDashboard.new()
		_ui_layer.add_child(dashboard)
		dashboard.ekg_view.ekg = ekg
		dashboard.action_requested.connect(_on_action)
		dashboard.language_requested.connect(_set_language)
		dashboard.mode_requested.connect(_set_mode)
		dashboard.transcript_submitted.connect(_on_transcript)
		dashboard.recording_requested.connect(_on_recording)
		dashboard.export_requested.connect(_export_session)

func _build_xr_ui() -> void:
	## Controls ride the hand. The patient-side surface is used only for results.
	hand_menu = NaretHandMenu.new()
	add_child(hand_menu)
	hand_menu.configure(origin, 0, interaction)
	hand_menu.ekg = ekg
	hand_menu.action_requested.connect(_on_action)
	hand_menu.language_requested.connect(_menu_language)
	hand_menu.mode_requested.connect(_menu_mode)
	hand_menu.setup_requested.connect(_menu_setup)
	hand_menu.recording_requested.connect(_on_recording)
	hand_menu.voice_sample_requested.connect(func():
		audio_manager.stop_speech()
		audio_manager.speak("", _language, "anna_arrive", "bystander"))
	hand_menu.export_requested.connect(_export_session)
	hand_menu.floor_calibration_requested.connect(_calibrate_floor)
	hand_menu.alignment_save_requested.connect(_save_alignment)
	hand_menu.reposition_requested.connect(_reposition_patient)
	hand_menu.reference_scan_toggled.connect(mannequin.set_reference_visible)
	hand_menu.hand_meshes_toggled.connect(xr.set_hands_visible)
	hand_menu.marker_gizmos_toggled.connect(_set_marker_gizmos)
	if xr.active:
		# Placement review 2026-10-29: show the raw detected marker poses from the start,
		# so a wrong patient position can be told apart from a wrong detection. The Debug
		# row's Gizmos key still switches them off.
		hand_menu.set_gizmos_on(true)
		_set_marker_gizmos.call_deferred(true)
	hand_menu.chest_calibration_requested.connect(_calibrate_chest)
	hand_menu.chest_fit_requested.connect(_set_chest_fit)
	hand_menu.set_chest_fit(anchor.chest_fit)
	hand_menu.sternum_landmark_apply_requested.connect(_apply_sternum_landmark)
	hand_menu.occlusion_requested.connect(_set_occlusion)
	hand_menu.fresh_start_requested.connect(_fresh_start)
	_add_sensor_logger()
	_set_occlusion(xr.occlusion)
	hand_menu.menu_shown_changed.connect(func(shown: bool): interaction.set_menu_hand(0 if shown else -1))
	_info_viewport = SubViewport.new()
	_info_viewport.size = Vector2i(900, 660)
	_info_viewport.transparent_bg = false
	_info_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_info_viewport.handle_input_locally = true
	add_child(_info_viewport)
	# No patient-side instructions, dialogue monitor or simulated ECG panel.
	# Keep an empty, hidden surface so the Results action can still open its modal.
	var surface := MeshInstance3D.new()
	surface.name = "XRResultsPanel"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.55)
	surface.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _info_viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ponytail: monitor stands past the patient's head, like a real bedside display.
	surface.position = Vector3(0.0, 0.82, -1.05)
	surface.rotation.x = 0.12
	anchor.add_child(surface)
	surface.visible = false
	_info_surface = surface
	interaction.register_ui_panel(surface, _info_viewport, quad.size)

func _reset_speaker_view() -> void:
	_default_character_spots.clear()
	_speaker_view.clear()
	_bystanders_placed_at = Vector3(INF, INF, INF)
	_spot_timer = 1.0

func _on_floor_space_changed() -> void:
	## Recentre or a re-established boundary: forget the retained floor point, read the
	## boundary floor again and let the characters and the AED spot follow it.
	_stable_floor.ready = false
	_floor_check_done = false
	if xr != null and xr.active:
		_refresh_floor_reference()
	_reset_speaker_view()

func _refresh_floor_reference() -> void:
	# Use one height source. Room scanning still supplies walls/obstacles, never
	# patient floor height. Later samples cannot jitter the accepted floor plane.
	var frame := origin.global_transform * XRServer.get_reference_frame()
	var height := _stable_floor.height_world(xr.floor_height_world(origin), frame)
	var source := "local_floor"
	if not is_finite(height):
		return
	_floor_source = source
	_floor_source_y = height
	anchor.floor_source_y = height
	if anchor.floor_touch_source == source:
		if absf(anchor.floor_touch_offset_m) > FLOOR_TOUCH_NEAR_M and not _floor_touch_verified:
			# A saved correction beyond the plausible window that this session did not
			# verify (9 Nov 2026: +64 cm from a fingertip on the manikin) is dropped.
			print("NARET_FLOOR_TOUCH dropped saved offset=%.3f" % anchor.floor_touch_offset_m)
			anchor.floor_touch_offset_m = 0.0
			anchor.floor_touch_source = ""
		else:
			height += anchor.floor_touch_offset_m
	if not anchor.floor_locked or not is_equal_approx(anchor.floor_y, height):
		anchor.floor_locked = true
		anchor.floor_y = height
		anchor.refresh()
		_bystanders_placed_at = Vector3(INF, INF, INF)
		print("NARET_FLOOR_SOURCE source=%s world_y=%.3f touch_offset=%.3f reference_y=%.3f play_area=%d" % [source, height, height - _floor_source_y, XRServer.get_reference_frame().origin.y, xr.interface.get_play_area_mode() if xr.interface else -1])

func _calibrate_floor() -> void:
	## Hand-menu key "Boden": the next fingertip resting on the floor corrects the
	## headset floor. The Quest boundary floor stays the default; this is the manual fix.
	if floor_touch == null:
		return
	floor_touch.start(origin, xr_camera)
	if hand_menu: hand_menu.set_floor_calibrating(true)
	_toast(NaretLanguage.ui("Zeigefinger auf den Boden legen und still halten", "Połóż palec wskazujący na podłodze i trzymaj nieruchomo", _language))

## A fingertip floor touch within this distance of the headset floor is always accepted.
const FLOOR_TOUCH_NEAR_M := 0.30
## Larger corrections (stale Space Setup: the stage floor was 0.9 m below the real floor
## on 2026-10-29) need the head at least this far above the touch, i.e. a fingertip
## really down on a floor, not on the manikin or a knee.
const FLOOR_TOUCH_FAR_M := 1.5
const FLOOR_TOUCH_HEAD_ABOVE_M := 1.2
var _floor_touch_verified := false

func _floor_touch_plausible(offset: float, floor_y: float) -> bool:
	## 9 Nov 2026: a fingertip resting 64 cm above the stage floor was accepted as the
	## floor and saved; Anna, Marek and the AED then stood 64 cm in the air.
	if absf(offset) <= FLOOR_TOUCH_NEAR_M:
		return true
	if absf(offset) > FLOOR_TOUCH_FAR_M:
		return false
	var head_above := xr_camera.global_position.y - floor_y if xr_camera else -INF
	return head_above >= FLOOR_TOUCH_HEAD_ABOVE_M

func _on_floor_measured(floor_y: float) -> void:
	# Stored against the automatic source, so recentring and the next session
	# keep the correction; a different source later ignores it.
	if hand_menu: hand_menu.set_floor_calibrating(false)
	var offset := floor_y - _floor_source_y
	if _floor_source.is_empty() or not is_finite(offset) or not _floor_touch_plausible(offset, floor_y):
		# No headset floor yet, or a touch that cannot be the floor.
		print("NARET_FLOOR_TOUCH rejected source=%s source_y=%.3f touch_y=%.3f offset=%.3f head_y=%.3f" % [_floor_source if not _floor_source.is_empty() else "none", _floor_source_y, floor_y, offset, xr_camera.global_position.y if xr_camera else NAN])
		_toast(NaretLanguage.ui("Fingerspitze nicht am Boden (%+.0f cm zum Headset-Boden) · erneut versuchen" % (offset * 100.0),
			"Palec nie na podłodze (%+.0f cm do podłogi zestawu) · spróbuj ponownie" % (offset * 100.0), _language))
		return
	_floor_touch_verified = true
	anchor.floor_touch_offset_m = offset
	anchor.floor_touch_source = _floor_source
	_refresh_floor_reference()
	var saved := anchor.save_calibration() == OK
	_toast(NaretLanguage.ui("Boden kalibriert: ", "Podłoga skalibrowana: ", _language) + "%+.1f cm" % (offset * 100.0) + ("" if saved else " (Save failed)"))

func _calibrate_chest() -> void:
	## Hand-menu key: a flat hand resting on the compression point sets the chest
	## height above the floor, so no marker has to lie on the chest.
	if chest_touch == null:
		return
	if not anchor.floor_locked:
		_toast(NaretLanguage.ui("Zuerst Boden kalibrieren", "Najpierw skalibruj podłogę", _language))
		return
	chest_touch.start(origin, func() -> Vector3: return mannequin.get_sternum_transform().origin)
	hand_menu.set_chest_calibrating(true)
	_toast(NaretLanguage.ui("Hand flach auf den Druckpunkt legen und still halten", "Połóż płasko dłoń na punkcie uciśnięć i trzymaj nieruchomo", _language))

func _on_chest_measured(surface_y: float) -> void:
	# Stored above the measured floor, not as a room height: it belongs to the
	# mannequin and survives recentring and other rooms.
	hand_menu.set_chest_calibrating(false)
	# Stored against the raw headset floor, so a fingertip floor correction made before
	# or after this never moves the hand-measured chest (2026-10-29). The range allows a
	# mannequin on a bed and a headset floor that is itself up to ~1 m off.
	var raw_floor := anchor.floor_source_y if is_finite(anchor.floor_source_y) else anchor.floor_y
	var height := surface_y - raw_floor
	var above_floor := surface_y - anchor.floor_y
	if not is_finite(height) or height < -0.5 or height > 2.0:
		_toast(NaretLanguage.ui("Brust nicht erkannt · Hand flach auflegen", "Nie wykryto klatki · połóż płasko dłoń", _language))
		return
	anchor.chest_height_m = height
	anchor.refresh()
	var saved := anchor.save_calibration() == OK
	print("NARET_CHEST height_raw=%.3f above_floor=%.3f fit=%s thickness=%.3f" % [height, above_floor, anchor.chest_fit, mannequin.thickness])
	_toast(NaretLanguage.ui("Brust: ", "Klatka: ", _language) + "%.1f" % (above_floor * 100.0) + NaretLanguage.ui(" cm über Boden", " cm nad podłogą", _language) + ("" if saved else " (Save failed)"))

func _set_chest_fit(fit: String) -> void:
	## Switches live between a flattened body and one lowered into the floor.
	anchor.chest_fit = fit
	anchor.refresh()
	anchor.save_calibration()
	hand_menu.set_chest_fit(fit)
	print("NARET_CHEST fit=%s height=%.3f thickness=%.3f" % [fit, anchor.chest_height_m, mannequin.thickness])

func _set_marker_gizmos(shown: bool) -> void:
	## Debug key: axis gizmos at the raw detected marker poses. Built only while on.
	var gizmos := get_node_or_null("MarkerGizmos")
	if not shown:
		if gizmos: gizmos.queue_free()
		return
	var provider: Node = tracker.get_provider() if tracker else null
	if provider == null:
		_toast("No marker camera: gizmos need the headset detector")
		print("NARET_GIZMO no_provider")
		return
	if gizmos == null:
		gizmos = load("res://scripts/tracking/marker_gizmos.gd").new()
		gizmos.name = "MarkerGizmos"
		add_child(gizmos)
		gizmos.bind(provider, tracker.get_layout_ids())
		tracker.pose_updated.connect(gizmos.show_fused)
		print("NARET_GIZMO bound provider_enabled=", provider.get("enabled"))

func _set_occlusion(mode: String) -> void:
	## Debug key: real-world occlusion off, for the room only, or for the patient too.
	xr.set_occlusion(mode)
	mannequin.set_occludable(xr.occlusion == "all")
	hand_menu.set_occlusion(xr.occlusion)

func _apply_sternum_landmark() -> void:
	## Hand-menu key for tuning: applies the Mannequin's sternum_landmark_offset
	## after it was edited in the editor's Remote inspector. Not saved: copy the
	## logged value into scenes/mannequin.tscn to keep it.
	var offset := mannequin.sternum_landmark_offset
	if not mannequin.apply_sternum_landmark_offset():
		_toast(NaretLanguage.ui("Ring-Offset unverändert", "Offset pierścienia bez zmian", _language))
		return
	anchor.body_changed()
	print("NARET_STERNUM_OFFSET ", offset)
	_toast(NaretLanguage.ui("Ring-Offset: ", "Offset pierścienia: ", _language) + "X %+.1f · Y %+.1f · Z %+.1f cm" % [offset.x * 100.0, offset.y * 100.0, offset.z * 100.0])

func _local_rect(xs: Array, zs: Array) -> Rect2:
	## World floor rect (XZ) around patient-local corners.
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for x: float in xs:
		for z: float in zs:
			var corner := mannequin.get_body_transform() * Vector3(x, 0.0, z)
			minimum = minimum.min(Vector2(corner.x, corner.z))
			maximum = maximum.max(Vector2(corner.x, corner.z))
	return Rect2(minimum, maximum - minimum)

func _place_bystanders() -> void:
	# Prefer located room geometry; otherwise use valid play-area bounds only.
	# Fixed patient-relative positions are never used when geometry is missing.
	if not xr.active:
		return
	if not anchor.locked:
		$Bystanders/Anna.visible = false
		if not _welcome_instructor: $Instructor.visible = false
		$Bystanders/Marek.visible = false
		return
	if default_character_placement:
		_place_default_characters()
	else:
		_place_speakers_strict()
	if situation == "A" and scenario.state != NaretScenario.State.IDLE:
		$Bystanders/Anna.visible = false
		$Bystanders/Marek.visible = false

## Circle a standing character needs: body half-width plus a little, not the arm reach
## the strict solver used (its large circles failed in small rooms, 9 Nov 2026).
const DEFAULT_SPOT_MARGIN_M := 0.05 # requested 9 Nov 2026: 5 cm from the boundary is enough
const DEFAULT_SPOT_PATIENT_M := 0.30
const DEFAULT_SPOT_SEPARATION_M := 0.60

func _fit_default_spots_to_boundary(centre: Vector3) -> void:
	## Pull the patient-relative default spots inside the headset boundary (play area).
	## Priority in a small room: inside the boundary, off the patient, apart from each
	## other. A roomy boundary, or none, leaves the free spots as they are.
	## The stool is never moved: it belongs beside the patient, where the trainee reaches
	## it. Until 13 Nov 2026 the AED's spot was pulled inside the boundary like a person;
	## with the manikin outside the boundary that put it, and then the stool, on the same
	## boundary edge as Anna (headset: "Anna is inside the stool").
	var bounds := _layout_bounds()
	var flat_centre := Vector2(centre.x, centre.z)
	# The stool counts as already standing there: people keep the same distance from it
	# as from each other, with the boundary's priorities when there is one.
	var placed: Array = []
	if _default_character_spots.has("AED"): placed.append(_stool_centre())
	for name in ["Anna", "Instructor", "Marek"]:
		if not _default_character_spots.has(name): continue
		var spot: Vector3 = _default_character_spots[name]
		# Off the stool first, the same with and without a boundary; the boundary fit
		# then keeps that distance while it pulls the spot inside.
		var fixed := _off_the_stool(Vector2(spot.x, spot.z))
		# Apart from those already placed, the same with and without a boundary. (Marek by
		# the stool can come out beside Anna or the instructor when the trainee stands at
		# the patient's feet; with a boundary the fit below would then send him to its edge.)
		fixed = _apart_from(fixed, placed)
		if bounds.size() >= 3:
			fixed = SpeakerPlacement.inside_outline(fixed, bounds, DEFAULT_SPOT_MARGIN_M, flat_centre,
				DEFAULT_SPOT_PATIENT_M, placed, DEFAULT_SPOT_SEPARATION_M)
		# Last, so nothing undoes it: nobody stands in the patient, even if that puts a
		# person outside a small boundary.
		fixed = _off_the_patient(fixed)
		placed.append(fixed)
		_default_character_spots[name] = Vector3(fixed.x, spot.y, fixed.y)

## The lying patient as a solid shape, in his own frame (head toward -Z): half his
## width, and how far he reaches from the chest toward the crown and toward the feet.
## DEFAULT_SPOT_PATIENT_M alone is a 30 cm circle round the chest: in a small play area
## Anna was put on his head or legs (headset 13 Nov 2026, "Anna is inside the avatar").
const PATIENT_HALF_WIDTH_M := 0.35
const PATIENT_TO_CROWN_M := 0.55
const PATIENT_TO_FEET_M := 1.25
const PERSON_RADIUS_M := 0.25

func _off_the_patient(point: Vector2) -> Vector2:
	var body := mannequin.get_body_transform().orthonormalized()
	var local := body.affine_inverse() * Vector3(point.x, body.origin.y, point.y)
	var half_x := PATIENT_HALF_WIDTH_M + PERSON_RADIUS_M
	var head_z := -(PATIENT_TO_CROWN_M + PERSON_RADIUS_M)
	var feet_z := PATIENT_TO_FEET_M + PERSON_RADIUS_M
	if absf(local.x) >= half_x or local.z <= head_z or local.z >= feet_z: return point
	# Out by the shortest way: to his side, or past his head or feet.
	var to_side := half_x - absf(local.x)
	var to_head := local.z - head_z
	var to_feet := feet_z - local.z
	if to_side <= to_head and to_side <= to_feet:
		local.x = half_x * (1.0 if local.x >= 0.0 else -1.0)
	elif to_head <= to_feet:
		local.z = head_z
	else:
		local.z = feet_z
	var world := body * local
	return Vector2(world.x, world.z)

## A standing person keeps this far from the stool's centre (its top is 34 x 66 cm):
## the same as between two people.
const STOOL_CLEAR_M := DEFAULT_SPOT_SEPARATION_M + 0.02

func _stool_centre() -> Vector2:
	var slot: Vector3 = _default_character_spots.AED
	var along := _toward_head()
	return Vector2(slot.x + along.x * AED_ON_STOOL_M, slot.z + along.z * AED_ON_STOOL_M)

func _apart_from(point: Vector2, others: Array) -> Vector2:
	## Straight away from whoever stands closer than people keep from each other.
	var moved := point
	for other: Vector2 in others:
		var away := moved - other
		if away.length() >= DEFAULT_SPOT_SEPARATION_M + 0.02: continue
		if away.length() < 0.05:
			var body := mannequin.get_body_transform().origin
			away = moved - Vector2(body.x, body.z)
		if away.length() < 0.05: away = Vector2.RIGHT
		moved = other + away.normalized() * (DEFAULT_SPOT_SEPARATION_M + 0.02)
	return moved

func _off_the_stool(point: Vector2) -> Vector2:
	if not _default_character_spots.has("AED"): return point
	var stool := _stool_centre()
	var away := point - stool
	if away.length() >= STOOL_CLEAR_M: return point
	# Straight away from the stool; from its very centre, away from the patient.
	if away.length() < 0.05:
		var body := mannequin.get_body_transform().origin
		away = stool - Vector2(body.x, body.z)
	return stool + away.normalized() * STOOL_CLEAR_M

func _layout_bounds() -> PackedVector2Array:
	## The headset boundary as a limit for where people stand and walk, or nothing when
	## the patient himself lies outside it: then the boundary is not the working area
	## (headset 13 Nov 2026: manikin 0.65 m outside; everyone was pressed onto the
	## boundary edge nearest to him), and the layout stays relative to the patient.
	var bounds := _play_area_outline_world()
	if bounds.size() < 3: return PackedVector2Array()
	var body := mannequin.get_body_transform().origin
	if not Geometry2D.is_point_in_polygon(Vector2(body.x, body.z), bounds):
		return PackedVector2Array()
	return bounds

func _place_default_characters() -> void:
	var centre := _patient_floor_centre()
	var new_layout := _default_character_spots.is_empty() or not _bystanders_placed_at.is_finite() or Vector2(centre.x,centre.z).distance_to(Vector2(_bystanders_placed_at.x,_bystanders_placed_at.z)) > 0.4
	if new_layout:
		var forward := Vector3(centre.x-xr_camera.global_position.x,0,centre.z-xr_camera.global_position.z)
		if forward.length_squared() < 0.001: forward = -xr_camera.global_basis.z.slide(Vector3.UP)
		if forward.length_squared() < 0.001: forward = Vector3.FORWARD
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)
		# Two front speakers and a separate helper behind their gap. The AED is
		# beside the patient, within reach, rather than behind the actors.
		# Closer than before (9 Nov 2026): 1.0 m in front of the patient instead of 1.2,
		# 0.6 m to each side instead of 0.8, Marek 0.6 m behind the gap instead of 0.9.
		var stage := centre + forward * 1.0
		# All three in one straight row across the patient, facing the trainee (14 Nov
		# 2026: "why don't you place Marek also in the same line, behind the stool").
		# Marek at the end on the stool's side, so his way to the stool is the shortest;
		# the instructor in the middle; Anna at the other end. Before, Marek stood beyond
		# the stool, beside or behind the trainee, where he was hardly seen.
		var aed_spot := _aed_default_spot()
		var stool_end := right if (aed_spot - stage).dot(right) >= 0.0 else -right
		_default_character_spots = {"Marek":stage + stool_end * ROW_GAP_M, "Instructor":stage,
			"Anna":stage - stool_end * ROW_GAP_M, "AED":aed_spot}
		_fit_default_spots_to_boundary(centre)
		_bystanders_placed_at = centre
	var floor_y := _speaker_floor_y()
	for person in _speaker_people():
		var point: Vector3 = _default_character_spots[str(person.name)]
		if new_layout:
			person.place_on_floor(_speaker_floor_pose(Vector3(point.x,floor_y,point.z),centre))
		elif not is_equal_approx(person._standing_floor_y,floor_y):
			person.update_standing_floor(floor_y)
		person.visible = not (person == $Bystanders/Marek and director and director.away)
	if new_layout and xr != null and xr.active:
		# Diagnosis line (10 Nov 2026): where the characters were put and relative to what.
		var bounds := _play_area_outline_world()
		var rect := "bounds=none"
		if bounds.size() >= 3:
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in bounds:
				lo = lo.min(p)
				hi = hi.max(p)
			rect = "bounds_x=%.2f..%.2f bounds_z=%.2f..%.2f points=%d" % [lo.x, hi.x, lo.y, hi.y, bounds.size()]
		var spots := ""
		for person in _speaker_people():
			spots += " %s=(%.2f, %.2f, %.2f)" % [person.name, person.global_position.x, person.global_position.y, person.global_position.z]
		print("NARET_SPOTS floor_used=%.3f live_headset_floor=%.3f sternum_y=%.3f head_y=%.3f %s%s" % [
			floor_y, xr.floor_height_world(origin), anchor.global_position.y, xr_camera.global_position.y, rect, spots])
	if aed:
		# On the headset the device appears only when Marek brings it; the default-spot
		# preview is for the desktop/simulator view.
		aed.preview_visible = not xr.active
		# Its height is the surface the patient lies on (see _aed_rest_y), not always the
		# floor. Once it is switched on it stays where the trainee is working with it.
		var rest_y := _aed_rest_y()
		var busy: bool = director != null and director.presenting
		if not aed._held and not aed._attached and not aed.powered and not busy and (new_layout or not is_equal_approx(aed.home_position().y,rest_y)):
			var point: Vector3 = _default_character_spots.AED
			aed.set_home_pose(Transform3D(_aed_facing(point),Vector3(point.x,rest_y,point.z)))
		_update_stool()
		# Visibility belongs to aed.sync() (preview or delivered). Forcing the model
		# visible here every second while sync hid it again made the device flicker
		# at its spot from the first scene on (9 Nov 2026).
	_speaker_issue = "default_positions"
	_record_speaker_placement("default_positions")

const MAREK_SHIRT := Color(0.14, 0.38, 0.85) # blue shirt (user, 18 Nov 2026); the instructor keeps olive
const ANNA_JACKET := Color(0.78, 0.12, 0.12)
const MAREK_BACKPACK := Color(0.05, 0.12, 0.38) # navy, so it shows on the blue shirt
## The device lies beside the patient's shoulder on the trainee's side, in the
## patient's own frame (head is -Z): within reach from the chest, clear of the arms.
## Before 13 Nov 2026 the spot was relative to where the viewer happened to stand when
## the characters were laid out, and always at floor height.
const AED_BESIDE_M := 0.50
const AED_TOWARD_HEAD_M := 0.50
## A patient lying higher than this above the floor is on a table or bed.
const RAISED_PATIENT_M := 0.15

## The stool (13 Nov 2026, headset review): nothing is put on the floor any more. A small
## stool stands beside the patient's head on the trainee's side. The AED lies on the end
## nearer the chest with its pads in front of it (device and pads: 26 x 44 cm, aed.glb),
## the bag-valve-mask across the end nearer the crown. Its top is level with the surface
## the patient lies on, and at least STOOL_MIN_HEIGHT_M above the floor.
const STOOL_ACROSS_M := 0.34
const STOOL_ALONG_M := 0.66
const STOOL_TOP_THICK_M := 0.03
const STOOL_MIN_HEIGHT_M := 0.32
## Along the stool from its centre (toward the feet is positive): the AED's origin,
## and the line the bag-valve-mask lies on.
const AED_ON_STOOL_M := 0.06
const BVM_ON_STOOL_AT_M := -0.16
## The lying bag-valve-mask's origin (mask rim centre) above the top.
const BVM_ON_STOOL_M := 0.005
var _stool: Node3D
var _stool_legs: Array[MeshInstance3D] = []

func _aed_rest_y() -> float:
	## Why the device (and the pads on it) used to be on the floor under a table: its
	## height was the headset floor, as for the standing characters, while the manikin
	## lay 0.5-1.0 m higher (headset logs 9 and 12 Nov: floor 0.00, sternum 0.47-1.05 m).
	## It now rests on the stool's top: the surface the patient lies on (the body frame's
	## origin is the patient's back), or a low stool's height if he lies on the floor.
	var floor_y := _speaker_floor_y()
	var surface := mannequin.get_body_transform().origin.y
	# 18 Nov 2026 (user): a patient on the floor gets the AED on the floor beside him, put
	# down, not on the stool. On a table or bed it stays on that surface.
	if surface - floor_y < 0.15:
		return floor_y + 0.01
	return surface + 0.01

func _aed_default_spot() -> Vector3:
	## The AED's place on the stool.
	var body := mannequin.get_body_transform().orthonormalized()
	var eye := body.affine_inverse() * (xr_camera if xr.active else desktop_camera).global_position
	var side := 1.0 if eye.x >= 0.0 else -1.0
	var point := body * Vector3(side * AED_BESIDE_M, 0.0, -AED_TOWARD_HEAD_M)
	point.y = _aed_rest_y()
	return point

## Solid shapes for what is not a character: the patient, the stool and the trainee.
## Characters walk their movers against these (NaretBystander._step_solid).
var _patient_solid: StaticBody3D
var _stool_solid: StaticBody3D
var _trainee_solid: StaticBody3D

func _solid_box(node_name: String, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.top_level = true
	body.collision_layer = NaretBystander.BODY_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body

func _update_solids() -> void:
	var tall := NaretBystander.BODY_TALL_M
	var floor_y := _speaker_floor_y()
	if mannequin and mannequin.is_visible_in_tree():
		if _patient_solid == null:
			_patient_solid = _solid_box("PatientSolid", Vector3(PATIENT_HALF_WIDTH_M * 2.0, tall, PATIENT_TO_CROWN_M + PATIENT_TO_FEET_M))
		var body := mannequin.get_body_transform().orthonormalized()
		var middle := body * Vector3(0.0, 0.0, (PATIENT_TO_FEET_M - PATIENT_TO_CROWN_M) * 0.5)
		var along := body.basis.z
		along.y = 0.0
		if along.length() > 0.1:
			_patient_solid.global_transform = Transform3D(Basis.looking_at(-along.normalized(), Vector3.UP), Vector3(middle.x, floor_y + tall * 0.5, middle.z))
	if _stool and _stool.visible:
		if _stool_solid == null:
			_stool_solid = _solid_box("StoolSolid", Vector3(STOOL_ACROSS_M, tall, STOOL_ALONG_M))
		_stool_solid.global_transform = Transform3D(_stool.global_basis.orthonormalized(), Vector3(_stool.global_position.x, floor_y + tall * 0.5, _stool.global_position.z))

func _update_trainee_solid() -> void:
	## Every frame: the trainee moves.
	if _trainee_solid == null:
		_trainee_solid = StaticBody3D.new()
		_trainee_solid.name = "TraineeSolid"
		_trainee_solid.top_level = true
		_trainee_solid.collision_layer = NaretBystander.BODY_LAYER
		_trainee_solid.collision_mask = 0
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.25
		capsule.height = NaretBystander.BODY_TALL_M
		shape.shape = capsule
		_trainee_solid.add_child(shape)
		add_child(_trainee_solid)
	var eye := (xr_camera if xr.active else desktop_camera).global_position
	_trainee_solid.global_position = Vector3(eye.x, _speaker_floor_y() + NaretBystander.BODY_TALL_M * 0.5, eye.z)

func _walk_obstacles(walker: Node3D) -> Array:
	## What a walking character goes round: the other people, the trainee and the stool
	## (with whatever lies on it). The patient has his own, longer detour.
	var found: Array = []
	for person in _speaker_people():
		if person != walker and person.visible:
			found.append({"point": Vector2(person.global_position.x, person.global_position.z), "radius": 0.30})
	var eye := (xr_camera if xr.active else desktop_camera).global_position
	found.append({"point": Vector2(eye.x, eye.z), "radius": 0.35})
	# Nobody walks through the AED or the bag and mask, wherever they lie (18 Nov 2026).
	if aed and aed.model and aed.model.is_visible_in_tree() and not aed._held:
		found.append({"point": Vector2(aed.model.global_position.x, aed.model.global_position.z), "radius": 0.15})
	var bag: Node3D = bvm.get("_model") if bvm else null
	if bag and bag.is_visible_in_tree():
		found.append({"point": Vector2(bag.global_position.x, bag.global_position.z), "radius": 0.15})
	if _stool and _stool.visible:
		found.append({"point": Vector2(_stool.global_position.x, _stool.global_position.z), "radius": 0.40})
	# The patient, as a row of circles from crown to feet: nobody walks across him either.
	if mannequin and mannequin.is_visible_in_tree():
		var body := mannequin.get_body_transform().orthonormalized()
		var along := -PATIENT_TO_CROWN_M + 0.25
		while along <= PATIENT_TO_FEET_M - 0.20:
			var at := body * Vector3(0.0, 0.0, along)
			found.append({"point": Vector2(at.x, at.z), "radius": 0.28, "patient": true})
			along += 0.35
	return found

## Between neighbours in the row of three: more than people keep apart (0.62 m).
const ROW_GAP_M := 0.85

func _toward_head() -> Vector3:
	var direction := -mannequin.get_body_transform().basis.z
	direction.y = 0.0
	return direction.normalized() if direction.length() > 0.1 else Vector3.FORWARD

func _update_stool() -> void:
	## Under the AED's place, whatever moved that place (layout, play-area fit, delivery).
	if aed == null or not _default_character_spots.has("AED"): return
	if _stool == null: _build_stool()
	var slot: Vector3 = _default_character_spots.AED
	var along := _toward_head()
	var top_y := _aed_rest_y()
	var centre := Vector3(slot.x, top_y, slot.z) + along * AED_ON_STOOL_M
	# Local -Z is toward the patient's head, as in the patient's own frame.
	_stool.global_transform = Transform3D(Basis.looking_at(along, Vector3.UP), centre)
	var height := maxf(top_y - _speaker_floor_y(), 0.05)
	for leg in _stool_legs:
		leg.scale.y = height - STOOL_TOP_THICK_M
		leg.position.y = -STOOL_TOP_THICK_M - (height - STOOL_TOP_THICK_M) * 0.5
	# 18 Nov 2026 (user): no stool, it is a road in the park. It stays the invisible frame
	# that places the AED and the bag on the ground beside the patient.
	_stool.visible = false
	_update_solids()
	if bvm:
		# Standing on its mask at the stool's far end, as it would be put down: rim flat on
		# the top, the bent bag up and toward the crown end, ready to be taken by the bag.
		# (It lay on its side across the stool, the mask on edge and the bag over the end.)
		var lying := Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3(0.0, BVM_ON_STOOL_M, BVM_ON_STOOL_AT_M))
		bvm.set_spot(mannequin.global_transform.affine_inverse() * (_stool.global_transform * lying), false)

func _build_stool() -> void:
	_stool = Node3D.new()
	_stool.name = "Stool"
	add_child(_stool)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.45, 0.28)
	wood.roughness = 0.8
	var top := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(STOOL_ACROSS_M, STOOL_TOP_THICK_M, STOOL_ALONG_M)
	top.mesh = board
	top.material_override = wood
	top.position.y = -STOOL_TOP_THICK_M * 0.5
	_stool.add_child(top)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.42, 0.30, 0.19)
	dark.roughness = 0.8
	for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var leg := MeshInstance3D.new()
		var post := CylinderMesh.new()
		post.top_radius = 0.016
		post.bottom_radius = 0.016
		post.height = 1.0
		leg.mesh = post
		leg.material_override = dark
		leg.position = Vector3(corner.x * (STOOL_ACROSS_M * 0.5 - 0.035), 0.0, corner.y * (STOOL_ALONG_M * 0.5 - 0.035))
		_stool.add_child(leg)
		_stool_legs.append(leg)

func _aed_facing(point: Vector3) -> Basis:
	## Flat and square on the stool: its lower edge, where the pads lie, toward the
	## patient's feet, which is toward the trainee at the chest. (Turned toward the chest
	## itself it lay at 45 degrees and the pads hung over the stool's edge.)
	return Basis.looking_at(_toward_head(), Vector3.UP)

func _keep_in_play_area(point: Vector3) -> Vector3:
	var bounds := _layout_bounds()
	if bounds.size() < 3: return point
	var centre := _patient_floor_centre()
	var fixed := SpeakerPlacement.inside_outline(Vector2(point.x, point.z), bounds, DEFAULT_SPOT_MARGIN_M, Vector2(centre.x, centre.z), 0.0)
	return Vector3(fixed.x, point.y, fixed.y)

func _patient_floor_centre() -> Vector3:
	var centre := mannequin.get_body_transform().origin
	if anchor.floor_locked:
		centre.y = _speaker_floor_y()
	return centre


func _speaker_geometry() -> Dictionary:
	if not anchor.locked: return {}
	var centre := _patient_floor_centre()
	var bounds := _play_area_outline_world()
	var outline := PackedVector2Array()
	var source := "play_area"
	if room != null and room.available:
		outline = room.outline_for(xr_camera.global_position, centre, room.floor_height_world())
		if outline.size() >= 3: source = "room_scan"
	if outline.size() < 3: outline = bounds
	if outline.size() < 3: return {}
	var current_eye := Vector2(xr_camera.global_position.x, xr_camera.global_position.z)
	# The characters must fit inside the outline; their viewer and patient
	# need not be inside it. An outside patient must not invalidate usable
	# floor space for both speakers. The solver still checks their full bodies.
	if _bystanders_placed_at.is_finite() and centre.distance_to(_bystanders_placed_at) > 0.4:
		_speaker_view.clear()
	var forward := Vector2(-xr_camera.global_basis.z.x, -xr_camera.global_basis.z.z)
	if forward.length_squared() < 0.001:
		if _speaker_view.is_empty(): return {}
		forward = _speaker_view.forward
	var blockers: Array = room.obstacle_footprints() if room != null else []
	blockers.append_array([_local_rect([-0.35, 0.35], [-1.05, 1.05]), _local_rect([-1.0, -0.3], [-0.75, 0.75])])
	return {"floor": outline, "blockers": blockers, "bounds": bounds, "source": source,
		"eye": _speaker_view.get("eye", current_eye),
		"forward": _speaker_view.get("forward", forward.normalized())}

## A play area for desktop replays of a headset session (the desktop has none).
var play_area_override := PackedVector2Array()

func _play_area_outline_world() -> PackedVector2Array:
	if play_area_override.size() >= 3: return play_area_override
	if xr == null or xr.interface == null or not xr.interface.is_initialized():
		return PackedVector2Array()
	# get_play_area already includes XRServer's reference transform. Apply the
	# XROrigin transform only; a second reference transform would shift the bounds.
	return SpeakerPlacement.play_area_outline(xr.interface.get_play_area(), origin.global_transform)

func _speakers_fit(geometry: Dictionary, radii: Vector2) -> bool:
	if geometry.is_empty(): return false
	var people: Array[Node3D] = [$Bystanders/Anna, $Instructor]
	var points: Array[Vector2] = []
	for i in people.size():
		var point := Vector2(people[i].global_position.x, people[i].global_position.z)
		if not SpeakerPlacement.valid(point, radii[i], geometry.floor, geometry.blockers, geometry.eye, geometry.forward): return false
		var bounds: PackedVector2Array = geometry.get("bounds", PackedVector2Array())
		if bounds.size() >= 3 and not SpeakerPlacement.valid(point, maxf(radii[i], NaretRoomLayout.WALL_CLEARANCE), bounds, [], geometry.eye, geometry.forward): return false
		points.append(point)
	return points[0].distance_to(points[1]) > radii.x + radii.y

func _hide_speakers(reason: String) -> void:
	_speaker_assigned.clear()
	_speaker_plan_signature = 0
	$Bystanders/Anna.visible = false
	if not _welcome_instructor: $Instructor.visible = false
	$Bystanders/Marek.visible = false
	if reason == _speaker_issue: return
	_speaker_issue = reason
	print("NARET_SPEAKER_PLACEMENT ", reason)
	_record_speaker_placement(reason)
	var messages := {
		"scan_or_floor_missing": {
			"en": "Play-area bounds are unavailable; character placement is paused.",
			"de": "Spielbereichsgrenzen sind nicht verfügbar; die Platzierung der Personen pausiert.",
			"pl": "Granice obszaru gry są niedostępne; ustawianie postaci jest wstrzymane."},
		"no_front_pair": {
			"en": "Not enough clear space for both characters inside the play area.",
			"de": "Nicht genug freie Fläche für beide Personen im Spielbereich.",
			"pl": "Za mało miejsca dla obu postaci w obszarze gry."}}
	if messages.has(reason): _toast(str(messages[reason].get(_language, messages[reason].en)))


func _speaker_people() -> Array[NaretBystander]:
	return [$Bystanders/Anna, $Instructor, $Bystanders/Marek]

func _actor_spot_valid(point: Vector2, radius: float, geometry: Dictionary, occupied: Array) -> bool:
	if not SpeakerPlacement.valid(point, radius, geometry.floor, geometry.blockers, geometry.eye, geometry.forward, geometry.get("bounds", PackedVector2Array())): return false
	for other in occupied:
		if point.distance_to(other.point) <= radius + other.radius: return false
	return true

func _place_speakers_strict() -> void:
	var geometry := _speaker_geometry()
	if geometry.is_empty():
		_speaker_view.clear()
		_hide_speakers("scan_or_floor_missing")
		return
	# Reserve identities and positions until the supplied geometry changes.
	# Current animation size must never trigger a new actor assignment.
	var signature := hash([geometry.floor, geometry.blockers, geometry.get("bounds", PackedVector2Array()), geometry.eye, geometry.forward])
	if signature == _speaker_plan_signature and not _speaker_assigned.is_empty():
		for person in _speaker_people():
			if _speaker_assigned.has(person) and not is_equal_approx(person._standing_floor_y, _speaker_floor_y()):
				person.update_standing_floor(_speaker_floor_y())
				_speaker_assigned[person].capture(person)
			person.visible = _speaker_assigned.has(person) and not (person == $Bystanders/Marek and director and director.away)
		_note_speaker_source(geometry)
		return
	_speaker_assigned.clear()
	var centre := _patient_floor_centre()
	var candidates := NaretRoomLayout._candidates(geometry.floor, Vector2(centre.x, centre.z))
	candidates.sort_custom(func(a: Vector2, b: Vector2): return a.distance_to(Vector2(centre.x, centre.z)) < b.distance_to(Vector2(centre.x, centre.z)))
	var occupied: Array = []
	if aed and (scenario and scenario.aed_available):
		occupied.append({"point": Vector2(aed.home_position().x, aed.home_position().z), "radius": aed.floor_radius()})
	var people := _speaker_people()
	var options: Array = []
	var radii: Array = []
	for person in people:
		var radius := _speaker_envelope.radius(person)
		radii.append(radius)
		var points: Array[Vector2] = []
		var current := Vector2(person.global_position.x, person.global_position.z)
		if person.visible and _actor_spot_valid(current, radius, geometry, occupied): points.append(current)
		var actor_candidates: Array[Vector2] = []
		actor_candidates.assign(candidates)
		actor_candidates.append_array(SpeakerPlacement.boundary_candidates(geometry.floor, geometry.blockers, radius))
		for candidate: Vector2 in actor_candidates:
			if _actor_spot_valid(candidate, radius, geometry, occupied) and not points.has(candidate): points.append(candidate)
		options.append(points)
	var chosen := SpeakerPlacement.independent_spots(options, radii)
	for i in people.size():
		var person: NaretBystander = people[i]
		var found := chosen.has(i)
		if found:
			var point: Vector2 = chosen[i]
			person.place_on_floor(_speaker_floor_pose(Vector3(point.x, _speaker_floor_y(), point.y), centre))
			var snapshot = SpeakerPoseSnapshot.new()
			snapshot.capture(person)
			_speaker_assigned[person] = snapshot
		person.visible = found and not (person == $Bystanders/Marek and director and director.away)
	_speaker_plan_signature = signature
	# A helper who cannot fit never hides the other two people.
	_speaker_view = {"eye": geometry.eye, "forward": geometry.forward}
	_bystanders_placed_at = centre
	_note_speaker_source(geometry)

var _aed_delivery_pose := Transform3D.IDENTITY

func _prepare_aed_delivery() -> bool:
	if xr.active and default_character_placement:
		if not anchor.locked: return false
		_place_default_characters()
		# The stool has stood there since the layout; the device goes onto it. (The side
		# used to be chosen again here, which would now make the stool jump.)
		var spot: Vector3 = _default_character_spots.get("AED", _aed_default_spot())
		spot.y = _aed_rest_y()
		_default_character_spots["AED"] = spot
		_aed_delivery_pose = Transform3D(_aed_facing(spot), spot)
		aed.set_home_pose(_aed_delivery_pose)
		_update_stool()
		print("NARET_AED delivery_spot=(%.2f, %.2f, %.2f) floor_y=%.3f patient_surface_y=%.3f" % [spot.x, spot.y, spot.z, _speaker_floor_y(), mannequin.get_body_transform().origin.y])
		return true
	if xr.active:
		_place_speakers_strict()
		var geometry := _speaker_geometry()
		if geometry.is_empty(): return false
		var occupied: Array = []
		for person in _speaker_people():
			var point := Vector2(person.global_position.x, person.global_position.z)
			var radius := _speaker_envelope.radius(person)
			if person == $Bystanders/Marek and not _actor_spot_valid(point, radius, geometry, occupied): return false
			if person.visible or person == $Bystanders/Marek: occupied.append({"point": point, "radius": radius})
		var centre := _patient_floor_centre()
		var candidates := NaretRoomLayout._candidates(geometry.floor, Vector2(centre.x, centre.z))
		candidates.sort_custom(func(a: Vector2, b: Vector2): return a.distance_to(Vector2(centre.x, centre.z)) < b.distance_to(Vector2(centre.x, centre.z)))
		var found := false
		for point: Vector2 in candidates:
			if _actor_spot_valid(point, aed.floor_radius(), geometry, occupied):
				_aed_delivery_pose = Transform3D(Basis.IDENTITY, Vector3(point.x, _speaker_floor_y(), point.y))
				found = true
				break
		if not found: return false
	else:
		_aed_delivery_pose = $AED.global_transform
	aed.set_home_pose(_aed_delivery_pose)
	return true

func _note_speaker_source(geometry: Dictionary) -> void:
	var source := str(geometry.get("source", "room_scan"))
	if _speaker_issue == source:
		_record_speaker_placement(source)
		return
	_speaker_issue = source
	print("NARET_SPEAKER_PLACEMENT source=", source)
	_record_speaker_placement(source)


func _record_speaker_placement(reason: String) -> void:
	# Persist the current session's reason: one-time Android log lines can roll
	# out of the buffer during training. No transcript or service secrets.
	if _smoke_mode or xr == null or not xr.active: return
	var bounds := _play_area_outline_world()
	var eye := Vector2(xr_camera.global_position.x, xr_camera.global_position.z)
	var centre := _patient_floor_centre()
	var status := {"unix_ms": int(Time.get_unix_time_from_system()*1000),
		"reason": reason, "bounds_points": bounds.size(), "anchor_locked": anchor.locked,
		"eye": str(eye), "patient": str(Vector2(centre.x,centre.z)),
		"eye_inside": Geometry2D.is_point_in_polygon(eye,bounds) if bounds.size()>=3 else false,
		"patient_inside": Geometry2D.is_point_in_polygon(Vector2(centre.x,centre.z),bounds) if bounds.size()>=3 else false,
		"visible_characters": int($Bystanders/Anna.visible)+int($Instructor.visible)+int($Bystanders/Marek.visible),
		"anna_position": str($Bystanders/Anna.global_position),
		"instructor_position": str($Instructor.global_position), "marek_position": str($Bystanders/Marek.global_position)}
	var geometry := _speaker_geometry()
	if not geometry.is_empty() and not default_character_placement:
		status["forward"] = [geometry.forward.x, geometry.forward.y]
		status["placement_eye"] = [geometry.eye.x, geometry.eye.y]
		status["floor_polygon"] = []
		for point: Vector2 in geometry.floor: status.floor_polygon.append([point.x, point.y])
		status["blockers"] = []
		for rect: Rect2 in geometry.blockers: status.blockers.append([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
		status["characters"] = []
		var candidates := NaretRoomLayout._candidates(geometry.floor, Vector2(centre.x, centre.z))
		for person in _speaker_people():
			var radius := _speaker_envelope.radius(person)
			var rejection := {"nonfinite":0, "outside":0, "wall":0, "behind":0, "obstacle":0, "bounds":0, "passing":0}
			var diagnostic_candidates: Array[Vector2] = []
			diagnostic_candidates.assign(candidates)
			diagnostic_candidates.append_array(SpeakerPlacement.boundary_candidates(geometry.floor, geometry.blockers, radius))
			for candidate: Vector2 in diagnostic_candidates:
				if not is_finite(radius): rejection.nonfinite += 1
				elif not Geometry2D.is_point_in_polygon(candidate, geometry.floor): rejection.outside += 1
				elif NaretRoomLayout._distance_to_outline(geometry.floor, candidate) <= radius: rejection.wall += 1
				elif geometry.forward.dot(candidate - geometry.eye) <= radius: rejection.behind += 1
				else:
					var blocked := false
					for rect: Rect2 in geometry.blockers:
						if NaretRoomLayout._distance_to_rect(rect, candidate) <= radius: blocked = true
					if blocked: rejection.obstacle += 1
					elif not SpeakerPlacement.valid(candidate, radius, geometry.floor, geometry.blockers, geometry.eye, geometry.forward, geometry.get("bounds", PackedVector2Array())): rejection.bounds += 1
					else: rejection.passing += 1
			status.characters.append({"name":str(person.name), "visible":person.visible, "radius":radius,
				"position":[person.global_position.x, person.global_position.y, person.global_position.z], "candidate_results":rejection})
	var output := FileAccess.open("user://room_placement_status.json",FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(status))


var _floor_check_done := false

func _speaker_floor_y() -> float:
	## The wearer's floor as the headset reports it (Stage = boundary floor), never the
	## patient's height: the trainings happen in different rooms and a mannequin on a bed
	## or table must not lift the speakers. Order: locked headset floor (with the
	## fingertip correction from the hand-menu key "Boden"), live headset floor, XR
	## origin (floor-based reference spaces put it on the floor).
	if anchor.floor_locked:
		return anchor.floor_y
	var live := xr.floor_height_world(origin) if xr != null else NAN
	if is_finite(live):
		return live
	return origin.global_position.y

func _log_floor_check_once() -> void:
	## One line per placement to judge the headset floor afterwards: the marker-placed
	## sternum and the wearer's head height (about 11 cm below body height when standing).
	if not anchor.locked:
		_floor_check_done = false
		return
	if _floor_check_done:
		return
	_floor_check_done = true
	print("NARET_FLOOR_CHECK headset_floor_y=%.3f sternum_y=%.3f head_y=%.3f play_area=%d" % [
		_speaker_floor_y(), anchor.global_position.y, xr_camera.global_position.y,
		xr.interface.get_play_area_mode() if xr != null and xr.interface != null else -1])

func _validate_speakers() -> void:
	if xr == null or not xr.active: return
	if default_character_placement:
		# Default positions are explicitly requested: room fitting and the
		# animated-envelope rollback must not hide or distort these people.
		return
	var geometry := _speaker_geometry()
	if geometry.is_empty():
		_hide_speakers("scan_or_floor_missing")
		if aed and aed.model: aed.model.visible = false
		return
	var occupied: Array = []
	for person in _speaker_people():
		if not person.visible: continue
		var radius := _speaker_envelope.radius(person)
		var point := Vector2(person.global_position.x, person.global_position.z)
		if not _actor_spot_valid(point, radius, geometry, occupied) and _speaker_assigned.has(person):
			# A gesture may exceed its space, but it does not invalidate the actor's
			# identity or standing spot. Keep the last safe rendered pose instead.
			_speaker_assigned[person].restore(person)
			radius = _speaker_envelope.radius(person)
			point = Vector2(person.global_position.x, person.global_position.z)
		if not _actor_spot_valid(point, radius, geometry, occupied):
			# Changed geometry can invalidate even the remembered pose. Replan then.
			person.visible = false
			_speaker_plan_signature = 0
		else:
			if _speaker_assigned.has(person): _speaker_assigned[person].capture(person)
			occupied.append({"point": point, "radius": radius})
	if aed and aed.model and aed.model.visible:
		var point := Vector2(aed.model.global_position.x, aed.model.global_position.z) if aed._held else Vector2(aed.home_position().x, aed.home_position().z)
		# Pad meshes on the patient are intentional. The box footprint remains reserved.
		aed.model.visible = _actor_spot_valid(point, aed.floor_radius(), geometry, [] if aed._held else occupied)

func _speaker_floor_pose(position: Vector3, centre: Vector3) -> Transform3D:
	var facing := centre - position
	facing.y = 0.0
	if facing.length_squared() < 0.001:
		facing = Vector3.BACK
	return Transform3D(Basis.looking_at(-facing, Vector3.UP), position)

## Watchdog thread (2026-11-03): reports a main-loop stall while it is still happening,
## which the in-loop stall detector cannot do when the process dies during the stall.
var _camera_parked := false
var _heartbeat_usec := 0
var _watchdog_step := ""
var _watchdog: Thread
var _watchdog_stop := false

func _start_watchdog() -> void:
	_heartbeat_usec = Time.get_ticks_usec()
	_watchdog = Thread.new()
	_watchdog.start(_watchdog_loop)

## Set by the watchdog thread, consumed by the main thread once it runs again.
var _camera_stopped_by_watchdog := false

func _watchdog_loop() -> void:
	var reported := false
	var last_report_s := 0.0
	while not _watchdog_stop:
		OS.delay_msec(1000)
		var age := float(Time.get_ticks_usec() - _heartbeat_usec) / 1000000.0
		if age > 2.0:
			if not reported or age - last_report_s >= 10.0:
				print("NARET_MAIN_STALLED for %.1f s, last step=%s" % [age, _watchdog_step])
				last_report_s = age
			reported = true
			# The main loop stops while the headset sleeps or the session pauses, but the
			# camera keeps producing 300 KB frames for it: stop the stream from here.
			if not _camera_stopped_by_watchdog and not _camera_parked and tracker:
				_camera_stopped_by_watchdog = true
				tracker.stop_camera_from_thread()
		elif reported:
			print("NARET_MAIN_RESUMED after %.1f s" % last_report_s)
			reported = false
			last_report_s = 0.0

func _exit_tree() -> void:
	_watchdog_stop = true
	if _watchdog != null and _watchdog.is_started():
		_watchdog.wait_to_finish()

## Marker detection costs ~25 ms per frame on the Quest (2026-11-06). Full rate while the
## patient is being placed and while the gate confirms a big move (30/33/... readings);
## PLACED_DETECTIONS_PER_S otherwise, enough to follow the mannequin.
const PLACED_DETECTIONS_PER_S := 10.0

func _update_detection_rate() -> void:
	if tracker == null or anchor == null or not xr.active:
		return
	var confirming := anchor.viewer_gate != null and anchor.viewer_gate.gate_state == "big_collecting"
	tracker.set_detection_rate(0.0 if not anchor.locked or confirming else PLACED_DETECTIONS_PER_S)

func _process(delta: float) -> void:
	# Frame-time foot transitions must stop even when no new camera pose arrives.
	_refresh_marker_evidence()
	_update_head_scan()
	_update_phone()
	_update_dispatcher()
	_update_safety_bubble()
	_update_breathing_hint(delta)
	_update_response_hint()
	_update_remembered_reports()
	_update_pad_guidance()
	_update_welcome_instructor()
	_update_step_back(delta)
	_update_stay_with_person(delta)
	_update_breath_pause()
	_update_ems()
	_heartbeat_usec = Time.get_ticks_usec()
	if xr != null and mannequin != null and mannequin.is_visible_in_tree(): _update_trainee_solid()
	_update_detection_rate()
	if _camera_stopped_by_watchdog:
		_camera_stopped_by_watchdog = false
		if tracker and not _camera_parked:
			tracker.restart_camera_after_stall()
	if scenario:
		_watchdog_step = NaretTrainingCoach.step(scenario)
	# Stall detector (2026-11-03): two Java out-of-memory crashes came from camera frames
	# piling up while this thread was stalled for ~30 s. Log every long frame with the
	# current step, so the next trace shows what the app was doing when it froze.
	if delta > 0.5 and scenario:
		print("NARET_STALL delta_s=%.2f state=%s step=%s" % [delta, scenario.get_state_name(), NaretTrainingCoach.step(scenario)])
	if interaction and scenario:
		var compressing := NaretTrainingCoach.step(scenario) in ["compressions", "compression_only"]
		interaction.set_cpr_feedback_visible(compressing)
		mannequin.heart_on_press = compressing
	if not scenario: return
	_try_pending_training_start()
	if xr.active:
		_refresh_floor_reference()
		_update_controller_alignment(delta)
		# The shadow lies on the measured real floor, even where the body sinks below it.
		if anchor.floor_locked:
			mannequin.set_shadow_floor(_speaker_floor_y())
	for person: NaretBystander in [$Bystanders/Anna, $Instructor, $Bystanders/Marek]:
		if audio_manager and person.speaking:
			person.set_mouth_bands(audio_manager.get_speech_bands())
	_ui_timer += delta
	if _ui_timer >= 0.1:
		_ui_timer = 0.0
		if xr != null and xr.active:
			_log_floor_check_once()
		if aed:
			aed.preview_visible = default_character_placement and not xr.active
			aed.sync(scenario, _language)
		if dashboard: dashboard.update_session(scenario)
		if hand_menu: hand_menu.update_session(scenario)
		if xr_info: xr_info.update_session(scenario)
	_spot_timer += delta
	if _spot_timer >= 1.0:
		_spot_timer = 0.0
		_place_bystanders()
	if xr.active: _keep_personal_space()

## Per helper: {"home": Vector3, "stepped": bool} (NaretPersonalSpace).
var _personal_space := {}

func _keep_personal_space() -> void:
	## An idle helper steps 0.4 m back when the trainee comes within 0.6 m, onto free
	## floor only, and returns once the trainee is more than 1 m from the own place.
	var head := Vector2(xr_camera.global_position.x, xr_camera.global_position.z)
	for person in _speaker_people():
		var key := str(person.name)
		var state: Dictionary = _personal_space.get(key, {})
		var marek_busy: bool = person == $Bystanders/Marek and director != null \
			and (director.fetching or director.away or director.presenting or director.marek_compressing or director.phase != "")
		if not person.visible or person.is_walking() or marek_busy or person._task_posture != "":
			# Busy or moved by the scene: the place it ends up in is its own again.
			_personal_space.erase(key)
			continue
		if person.is_shuffling():
			continue
		if state.is_empty() or not state.stepped:
			state = {"home": person.global_position, "stepped": false}
		var home: Vector3 = state.home
		var choice := NaretPersonalSpace.decide(Vector2(home.x, home.z), head, state.stepped)
		if choice.target != null:
			var target: Vector2 = choice.target
			if choice.stepped and not _personal_step_free(target, person):
				target = Vector2(home.x, home.z).lerp(target, 0.5) # half a step where a whole one is blocked
				if not _personal_step_free(target, person): target = Vector2.INF
			if target != Vector2.INF:
				person.shuffle_to(Vector3(target.x, home.y, target.y))
				state.stepped = choice.stepped
		_personal_space[key] = state

func _personal_step_free(point: Vector2, person: NaretBystander) -> bool:
	## Free floor for a step back: off the patient, clear of the stool and the other
	## people, and outside everything the room scan knows (furniture, walls).
	if _off_the_patient(point) != point: return false
	if _default_character_spots.has("AED") and point.distance_to(_stool_centre()) < 0.45: return false
	for other in _speaker_people():
		if other != person and other.visible and point.distance_to(Vector2(other.global_position.x, other.global_position.z)) < 0.5:
			return false
	if room != null and room.available:
		for rect: Rect2 in room.obstacle_footprints():
			if rect.grow(PERSON_RADIUS_M).has_point(point): return false
	return true

func _update_controller_alignment(delta: float) -> void:
	if anchor.manual_reposition_only:
		return
	if not anchor.locked or is_instance_valid(_modal):
		return
	var left := $XROrigin3D/LeftHand as XRController3D
	var right := $XROrigin3D/RightHand as XRController3D
	var stick := left.get_vector2("primary") if left.get_has_tracking_data() else Vector2.ZERO
	var yaw_axis := right.get_vector2("primary").x if right.get_has_tracking_data() else 0.0
	var height_axis := right.get_vector2("primary").y if right.get_has_tracking_data() else 0.0
	if absf(height_axis) <= CONTROLLER_DEAD_ZONE:
		height_axis = 0.0
	else:
		height_axis = signf(height_axis) * (minf(absf(height_axis), 1.0) - CONTROLLER_DEAD_ZONE) / (1.0 - CONTROLLER_DEAD_ZONE)
	if stick.length() <= CONTROLLER_DEAD_ZONE:
		stick = Vector2.ZERO
	else:
		stick = stick.normalized() * (minf(stick.length(), 1.0) - CONTROLLER_DEAD_ZONE) / (1.0 - CONTROLLER_DEAD_ZONE)
	if absf(yaw_axis) <= CONTROLLER_DEAD_ZONE:
		yaw_axis = 0.0
	else:
		yaw_axis = signf(yaw_axis) * (absf(yaw_axis) - CONTROLLER_DEAD_ZONE) / (1.0 - CONTROLLER_DEAD_ZONE)
	if stick == Vector2.ZERO and is_zero_approx(yaw_axis) and is_zero_approx(height_axis):
		return
	# Left stick moves horizontally. Right X turns; right Y adjusts patient height.
	# The height offset is saved separately so floor locking cannot undo the nudge.
	var dt := minf(delta, 0.05)
	if not is_zero_approx(height_axis):
		anchor.adjust_patient_height(height_axis * CONTROLLER_NUDGE_MPS * dt)
	var forward := -xr_camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()
	var sideways := forward.cross(Vector3.UP)
	anchor.nudge_world((sideways * stick.x + forward * stick.y) * CONTROLLER_NUDGE_MPS * dt,
		-deg_to_rad(CONTROLLER_YAW_DPS) * yaw_axis * dt)

func _on_alignment_button(button: StringName) -> void:
	if button == &"ax_button": # Right A saves the model offset, including yaw.
		_save_alignment()

func _save_alignment() -> void:
	## Shared by the A button and the hand menu's save key.
	if not anchor.locked:
		_toast("Wait for marker placement")
		return
	anchor.calibrated = true
	if anchor.save_calibration() == OK:
		_toast("Alignment saved")
		print("NARET_ALIGNMENT saved offset=", anchor.marker_to_mannequin)
	else:
		_toast("Save failed")

func _clear_training_session() -> void:
	llm.cancel_pending()
	_response_reported = false
	_breathing_reported = false
	_early_call_request = false
	_early_aed_request = false
	_breathing_told = false
	_safety_asked = false
	_look_hinted = false
	_answer_hinted = false
	_safety_stated = false
	_safety_bubble_text = ""
	if _park: _park.visible = false
	audio_manager.reset_training()
	_last_coach_step = ""
	_unclassified_spoken_step = ""
	_last_heard_report = ""
	_aed_announced = false
	_last_compression_ms = 0
	if interaction: interaction.rearm_cpr_cycle()
	logger.reset()
	score.reset()

func _reposition_patient() -> void:
	# Placement-only request: preserve model alignment, floor/chest measurements
	# and training progress. Fresh Start remains a separate, broader reset.
	if anchor == null: return
	anchor.unlock()
	_camera_parked = false
	if tracker:
		tracker.forget_pose()
		tracker.set_camera_streaming(true)
	_bystanders_placed_at = Vector3(INF, INF, INF)
	_speaker_view.clear()
	for path in ["Bystanders/Anna", "Instructor", "Bystanders/Marek"]:
		var speaker := get_node_or_null(path) as Node3D
		if speaker: speaker.visible = false
	_speaker_issue = ""
	var messages := {
		"en": "Repositioning: look at the mannequin markers and hold still.",
		"de": "Neu platzieren: Schauen Sie auf die Marker der Puppe und halten Sie still.",
		"pl": "Ponowne ustawianie: spójrz na markery manekina i pozostań nieruchomo."
	}
	_toast(str(messages.get(_language, messages.en)))
	print("NARET_REPOSITION requested")


func _fresh_start() -> void:
	_default_character_spots.clear()
	## Hand-menu key (2026-10-29): forget every hand measurement and placement and
	## begin as after a clean install, without leaving the app. The marker alignment
	## (marker_to_mannequin) and the marker layout are kept: they do not depend on a
	## hand measurement.
	print("NARET_FRESH_START")
	anchor.floor_touch_offset_m = 0.0
	anchor.floor_touch_source = ""
	anchor.chest_height_m = 0.0
	anchor.manual_floor_correction_m = 0.0
	anchor.save_calibration()
	if xr.active:
		_refresh_floor_reference()
	anchor.unlock()
	_camera_parked = false
	if tracker: tracker.set_camera_streaming(true)
	if tracker and tracker.has_method("forget_pose"):
		tracker.forget_pose()
	_bystanders_placed_at = Vector3(INF, INF, INF)
	_speaker_view.clear()
	$Bystanders/Anna.visible = false
	$Instructor.visible = false
	$Bystanders/Marek.visible = false
	_speaker_issue = ""
	_on_action("reset")
	_toast(NaretLanguage.ui("Neustart: Boden, Brust und Platzierung zurückgesetzt", "Od nowa: podłoga, klatka i ustawienie zresetowane", _language))

func _on_spoken_action(action: String) -> void:
	ccbm.observe_action(action)

func _try_pending_training_start() -> void:
	if _pending_training_action.is_empty() or anchor == null or not anchor.locked: return
	var action := _pending_training_action
	_pending_training_action = ""
	_on_action(action)

func _on_action(action: String, details: Dictionary = {}) -> void:
	if action in ["start", "restart", "reset"]:
		_pending_training_action = ""
		_pending_sequence.clear()
		_hands_hint_given = false
		_unsafe_reports = 0
		if phone: phone.hide_phone()
		_call_asked_ms = 0
		_phone_hinted.clear()
		if bvm: bvm.reset()
	if str(details.get("source", "")) == "speech" and action in ["attach_aed", "analyze_rhythm", "shock", "reassess", "resume_cpr"]: return
	if action == "attach_aed" and aed and aed.manual_pad_placement_required and not aed.pads_ready():
		_toast(NaretTrainingCoach.instruction("aed_apply", _language))
		return
	if action in ["clear_patient", "analyze_rhythm", "shock"] and interaction and (interaction._patient_contact_detected() or interaction.hands_touch_body()):
		scenario.submit_action("patient_contact", {"source": "hand_tracking"})
		return
	if action in ["start", "restart", "reset"]:
		_speech_confirmation.clear()
	if action == "handover" and _ems_state == 0 and not _smoke_mode:
		# 19 Nov 2026 (headset: "I'm feeling tired. Could you all give the compressions?" ended
		# the training and started the debrief). The handover ends the exercise only once the
		# ambulance crew is there; before that the trainee is told to keep going.
		# 26 Nov 2026: no spoken "keep going, help is on the way" any more; the request is ignored.
		print("NARET_HANDOVER asked before the crew arrived: ignored")
		return
	print("NARET_ACTION ", action, " placed=", anchor.locked, " calibrated=", anchor.calibrated)
	if action in ["start", "restart", "reset"] and observation_interpreter:
		observation_interpreter.cancel_pending()
	if action == "reset":
		_clear_training_session()
		audio_manager.set_listening(false)
		scenario.reset()
		_show_reply("")
		return
	if action in ["start", "restart"]:
		if hand_menu: hand_menu.close_popups()
		if xr.active and not anchor.locked:
			_pending_training_action = action
			_toast(NaretLanguage.text("notice.waiting_placement", _language))
			# In the line of sight too: the wrist notice is gone once the palm turns away.
			if speech_bubble: speech_bubble.say(NaretLanguage.text("notice.waiting_placement", _language), 8.0)
			return
		if xr.active and not anchor.calibrated:
			# 19 Nov 2026 (user: "after Start training nothing works"): a fresh install (the new
			# NaReT Szenario 1 app) has no saved alignment, and Start was refused with a small
			# English notice on the wrist. The patient is placed on the marker, so its placement
			# is the alignment: Start saves it and goes on. "Kalibrierung speichern" still
			# saves a corrected one.
			print("NARET_ALIGNMENT none saved yet: Start saves the current placement")
			_save_alignment()
			if not anchor.calibrated:
				_toast(NaretLanguage.ui("Kalibrierung konnte nicht gespeichert werden.", "Nie udało się zapisać kalibracji.", _language))
				return
		_clear_training_session()
		# A previous microphone toggle must not silently disable the new exercise.
		audio_manager.set_listening(true)
		scenario.alone = situation == "A"
		scenario.start()
		if speech_bubble and speech_bubble.visible: speech_bubble.hide_now()
		_apply_setup_to_scenario()
		_show_park()
		_show_reply(_opening_line())
		if hand_menu: hand_menu.clear_dialogue()
		if _pc_bench: _pc_bench_started()
		return
	if action == "briefing":
		_open_briefing()
		return
	if action == "compression":
		# Defence in depth: speech/LLM output cannot impersonate a detector stroke.
		if str(details.get("source", "")) == "speech":
			return
		var now := Time.get_ticks_msec()
		if details.is_empty():
			details = {"source": "desktop", "measurement_verified": false,
				"rate_bpm": 60000.0 / (now - _last_compression_ms) if _last_compression_ms > 0 and now > _last_compression_ms else 0.0}
		_last_compression_ms = now
	if action == "begin_check" and _head_scan_gate_active() and not _looked_around():
		# Gate 1 of the safety step (issue #1): look left and right before reporting.
		print("NARET_SAFETY report before the head scan: left=", head_scan.left, " right=", head_scan.right)
		_look_hinted = true
		_safety_line("coach.look_left_right")
		return
	# 26 Nov 2026: no "And who gets the AED?" gate before the breathing report any more; the
	# call step already asks for the defibrillator, and it can still be asked for later.
	if action == "check_responsiveness" and _shoulder_gate_active():
		# Hand tracking is on: the report counts only with a palm at the shoulders (12 Nov 2026).
		details = details.duplicate()
		details["shoulders_seen"] = interaction.shoulder_check.evidence_recent() or _tap_seen
		# Reported for the third time and the tap still was not seen: the hands are probably
		# not tracked there. The report is taken, so the training cannot get stuck here.
		if not details["shoulders_seen"] and str(details.get("source", "")).begins_with("speech"):
			_response_refusals += 1
			if _response_refusals >= 3:
				print("NARET_SHOULDERS not seen after three reports: the report is taken")
				details["shoulders_seen"] = true
		print("NARET_SHOULDERS gate seen=", details["shoulders_seen"], " shaken=", interaction.shoulder_check.shaken())
	if action == "ventilation" and str(details.get("source", "")) == "speech" and _bvm_gate_active():
		# The breaths are proven by the bag: a counted squeeze already went in, so a sentence
		# after it would double-count, and a sentence without it is refused (once per pair).
		if bvm.breaths_recent() == 0 and Time.get_ticks_msec() - _breath_refusal_ms > 5000:
			_breath_refusal_ms = Time.get_ticks_msec()
			print("NARET_BVM spoken breaths refused")
			_toast(NaretLanguage.text("error.breaths_not_seen", _language))
			if audio_manager and not _smoke_mode:
				audio_manager.speak(NaretLanguage.text("error.breaths_not_seen", _language), _language, "", _guide_speaker())
		return
	if action == "check_breathing" and _face_gate_active():
		# The headset was at the face for 3 s, or the report is refused (12 Nov 2026).
		details = details.duplicate()
		# The head tilt is what counts, and all that counts (13 Nov 2026, "only the tilt
		# is needed"): his head tilted back by the trainee's hands in this step. The head
		# at his face (NaretFaceCheck) is still measured and logged, and still gives the
		# 10 s hint, but no longer decides: with the tilt alone the report used to be
		# refused with "I did not see you check his breathing ... look at his chest".
		# Team to-do (issue #1, 5.): BOTH gates again — head tilted back with chin lift, AND
		# ear at the mouth with the view on the chest (the head at his face, NaretFaceCheck).
		details["face_seen"] = interaction.head_tilt_played and interaction.face_check.evidence_recent()
		_breathing_missing = "" if details["face_seen"] else ("coach.tilt_head" if not interaction.head_tilt_played else "coach.closer_to_mouth")
		print("NARET_FACE gate seen=", details["face_seen"], " head_tilt_played=", interaction.head_tilt_played, " at_face=", interaction.face_check.evidence_recent())
	# The praise for the safety step comes before the next step's instruction, which the
	# accepted action announces at once (17 Nov 2026: it was heard after it).
	if action == "begin_check" and action in scenario.get_available_actions():
		_coach_line("coach.safety_key", true)
	if scenario.submit_action(action, details):
		match action:
			"request_aed":
				# Situation B: the AED is delegated but nobody calls 112 yet (17 Nov 2026).
				# 26 Nov 2026: the call step asks for the AED first and for 112 second, so the
				# second request follows right after Marek's answer, not after 9 s.
				if situation == "B" and not scenario.emergency_called and not _smoke_mode:
					get_tree().create_timer(SECOND_TASK_AFTER_AED_S).timeout.connect(func():
						if not scenario.emergency_called and scenario.state == NaretScenario.State.CALL_HELP and not _trainee_talking():
							_coach_line("coach.who_calls_112"))
			"call_emergency":
				pass # 26 Nov 2026: no "And who gets the AED?" reminder after the call any more.
			"check_breathing":
				# Airway hint: only whether the avatar's head-tilt animation played in this step.
				if details.has("face_seen") and not interaction.head_tilt_played:
					# Spoken after the compressions instruction, which is a baked clip and is
					# already playing when this runs; the hint queues behind it. The step passed.
					_toast(NaretLanguage.text("coach.open_airway_hint", _language))
					if audio_manager and not _smoke_mode:
						audio_manager.speak(NaretLanguage.text("coach.open_airway_hint", _language), _language, "", _guide_speaker())
			"compression":
				if str(details.get("source", "desktop")) != "hand_tracking":
					mannequin.compress(float(details.get("depth_estimate_m", 0.045)))
				if dashboard: dashboard.show_compression(float(details.get("rate_bpm", 0)), float(details.get("depth_estimate_m", 0)), str(details.get("source", "desktop")))
				if xr_info: xr_info.show_compression(float(details.get("rate_bpm", 0)), float(details.get("depth_estimate_m", 0)), str(details.get("source", "desktop")))
			"ventilation":
				mannequin.ventilate()
				if scenario.cycle_ventilations == 0 and interaction: interaction.rearm_cpr_cycle()
				# The mask stays on his face after the breaths (14 Nov 2026: an automatic return
				# to the stool was tried and rejected the same day). The trainee can take it off
				# and put it back on the stool by hand, but is not told to.
			"reassure":
				$Bystanders/Anna.set_emotion("calm")
			"shock":
				aed.shock()
				_toast(NaretLanguage.ui("Schock simuliert · Sofort CPR fortsetzen", "Symulowane wyładowanie · Wznów RKO", _language))
	else:
		_toast(NaretLanguage.text(scenario.last_error, _language))
		if scenario.last_error in ["error.shoulders_not_seen", "error.breathing_not_seen"] and audio_manager and not _smoke_mode:
			# Spoken, not only shown: the trainee is looking at the patient, not at a panel.
			# For the breathing check the instructor says which part is missing (17 Nov 2026).
			_speech_confirmation.clear()
			var said := NaretLanguage.text(scenario.last_error, _language)
			if scenario.last_error == "error.shoulders_not_seen":
				_response_bubble_text = said
				# Said now, as the answer to the report: the timed hint does not say it again.
				_shoulders_hinted = true
				# The answer itself is kept: once the tap is seen the step goes on, and
				# "Does he respond?" is not asked of somebody who has already said it.
				_response_reported = true
			if scenario.last_error == "error.breathing_not_seen":
				_breathing_reported = true
			if scenario.last_error == "error.breathing_not_seen" and not _breathing_missing.is_empty():
				said = NaretLanguage.text(_breathing_missing, _language)
			_toast(said)
			if scenario.last_error == "error.breathing_not_seen" and _call_connecting(): return
			audio_manager.speak(said, _language, "", _guide_speaker())

## --- Breathing question (face checked, no report) -------------------------------------
## Asked only after the breathing instruction has been heard and then 10 s passed in
## silence. A fixed 10 s timer from the look at the face asked it while Anna and Marek
## were still talking, and the question replaced the instruction itself (17 Nov 2026).
var _breathing_told := false
var _breathing_missing := ""
var _transcript_step := ""
var _breathing_polling := false
var _breathing_quiet_s := 0

func _poll_breathing_question() -> void:
	if not (scenario and scenario.state == NaretScenario.State.CALL_HELP and scenario.emergency_called and not scenario.breathing_checked):
		_breathing_polling = false
		return
	if not _breathing_told or audio_manager.is_speaking() or audio_manager.recording or _call_connecting():
		_breathing_quiet_s = 0
	else:
		_breathing_quiet_s += 1
	if _breathing_quiet_s >= 10:
		_breathing_polling = false
		_ask_step_question()
		return
	get_tree().create_timer(1.0).timeout.connect(_poll_breathing_question)

## --- Park outside the play area (issue #1, 1. Szenario-Start) ----------------------------
## On while the scenario runs on the headset; inside the boundary passthrough stays.
const PARK_SCENE := true
var _park: NaretParkSurround

func _show_park() -> void:
	if not PARK_SCENE or xr == null or not xr.active or _smoke_mode: return
	if _park == null:
		_park = NaretParkSurround.new()
		_park.name = "ParkSurround"
		add_child(_park)
	var patient := Vector2(anchor.global_position.x, anchor.global_position.z)
	_park.visible = _park.build(_play_area_outline_world(), _speaker_floor_y(), patient)
	print("NARET_PARK shown=", _park.visible)

## --- Situation A: the dispatcher (issue #1, 4. Hilfe rufen) -------------------------------
## Steps whose instruction the dispatcher gives over the speaker once 112 is called (A).
const DISPATCHER_STEPS := ["breathing", "compressions", "compression_only", "breaths", "resume_compressions"]
const DISPATCHER := {
	"answer": {"de": "Notruf 112. Was ist passiert und wo?", "pl": "Numer alarmowy 112. Co się stało i gdzie?", "en": "Emergency 112. What has happened, and where?"},
	"speaker": {"de": "Bleib bei der Person. Ich bleibe dran und helfe dir.", "pl": "Zostań przy tej osobie. Jestem na linii i pomogę ci.", "en": "Stay with the person. I will stay on the line and help you."},
	"again": {"de": "Ich habe dich nicht verstanden. Was ist passiert, und wo bist du?", "pl": "Nie zrozumiałam. Co się stało i gdzie jesteś?", "en": "I did not catch that. What has happened, and where are you?"},
	# 26 Nov 2026: asked once when the answer named no place.
	"where": {"de": "Wo genau bist du?", "pl": "Gdzie dokładnie jesteś?", "en": "Where exactly are you?"},
}
## Words that name a place in the answer to the dispatcher (any language of the app).
const PLACE_WORDS := ["street", "road", "avenue", "square", "address", "pavement", "sidewalk", "station", "crossing", "border", "shop", "pharmacy", "park", "corner", "number", "frankfurt", "slubice", "słubice",
	"straße", "strasse", "weg", "platz", "gehweg", "bürgersteig", "adresse", "bahnhof", "grenze", "apotheke", "ecke", "hausnummer", "nummer",
	"ulica", "ulicy", "ul.", "plac", "chodnik", "adres", "dworzec", "granica", "granicy", "apteka", "apteki", "róg", "numer"]
var _place_asked := false

## The answer names where it happened ("in the Main Street", "am Gehweg vor der Apotheke").
static func _mentions_place(text: String) -> bool:
	var clean := " " + text.to_lower() + " "
	for word: String in PLACE_WORDS:
		if word in clean: return true
	return false
## 20 Nov 2026 (user: "why does the emergency-call response happen automatically even if I
## didn't say where and how?"): the dispatcher went on after ANY sentence, and by herself
## after 12 s. She now goes on when the trainee has told her something (see
## _answers_dispatcher). Without an answer she asks again after DISPATCHER_REASK_MS of
## silence, DISPATCHER_REASKS times; only after that does the call go on by itself, so a
## microphone that hears nothing cannot stop the training.
const DISPATCHER_REASK_MS := 10000
const DISPATCHER_REASKS := 2
var _dispatcher_reasks := 0

## An answer to "what has happened, and where?": a sentence of its own, not a word or two,
## and not the task given to the helper ("Marek, get the AED").
static func _answers_dispatcher(text: String) -> bool:
	const Spoken = preload("res://scripts/scenario/spoken_observation.gd")
	if _words(text).size() < 3: return false
	return not Spoken.mentions_aed_fetch(text) and Spoken.aed_action_for(text).is_empty()

func _update_dispatcher() -> void:
	if _dispatcher_step != 1 or not _dispatcher_asked or audio_manager == null: return
	if audio_manager.is_speaking() or _trainee_talking(): return
	if Time.get_ticks_msec() - _voice_end_ms < DISPATCHER_REASK_MS: return
	# "Where exactly are you?" was not answered: the call goes on (asked once only).
	if _place_asked:
		print("NARET_DISPATCHER no place given: the call goes on")
		_dispatcher_next()
		return
	if _dispatcher_reasks < DISPATCHER_REASKS:
		_dispatcher_reasks += 1
		print("NARET_DISPATCHER no answer: asking again (%d)" % _dispatcher_reasks)
		_voice_end_ms = Time.get_ticks_msec()
		_dispatcher_say("again")
	else:
		print("NARET_DISPATCHER no answer after asking again: the call goes on")
		_dispatcher_next()
var _dispatcher_step := 0 # 0 no call, 1 waiting for what/where, 2 leading
## Her "what happened and where?" has been said: only an answer after it moves the call on
## (17 Nov 2026, B: the trainee's words to Marek made her go on before she had answered).
var _dispatcher_asked := false

func _start_dispatcher(answer_after_s: float = 2.5, ring: bool = true) -> void:
	_dispatcher_step = 1
	# From the call on, the instructor is silent; the dispatcher says his lines (26 Nov 2026).
	if audio_manager: audio_manager.instructor_voice = "dispatcher"
	if ring: _play_phone_ring()
	_dispatcher_asked = false
	_place_asked = false
	_dispatcher_reasks = 0
	get_tree().create_timer(answer_after_s).timeout.connect(func(): _when_quiet(func():
		if _dispatcher_step != 1: return
		_dispatcher_say("answer")
		_dispatcher_asked = true
		# What follows is in _update_dispatcher and _on_transcript.
		_voice_end_ms = Time.get_ticks_msec()))

## Runs `then` once the instructor's "put the phone down" is neither playing nor waiting:
## the dispatcher answers after it, not into it (the scene's people go first in the queue).
func _when_quiet(then: Callable) -> void:
	var line := NaretLanguage.text("coach.phone_speaker", _language)
	var waiting := audio_manager != null and (audio_manager.current_text == line or audio_manager._pending.any(func(item): return item.get("text") == line))
	if not waiting:
		then.call()
		return
	get_tree().create_timer(0.3).timeout.connect(func(): _when_quiet(then))

## The dispatcher is on the line and the step is one she guides.
## The call is made but the dispatcher has not taken over yet (ringing, or she waits for
## "what and where"). In this window nobody gives step guidance: she gives the step herself
## as soon as she has the answer.
func _call_connecting() -> bool:
	return _dispatcher_step == 1

func _dispatcher_leads() -> bool:
	return _dispatcher_step == 2 and scenario != null and NaretTrainingCoach.step(scenario) in DISPATCHER_STEPS

## Who gives a hint or yes/no question now: the dispatcher from the moment the call has
## started, in the steps she leads (breathing, compressions, breaths); else the instructor.
## 26 Nov 2026: the instructor no longer repeats her lines while the call is connecting.
func _guide_speaker() -> String:
	var dispatcher_step := scenario != null and NaretTrainingCoach.step(scenario) in DISPATCHER_STEPS
	return "dispatcher" if _dispatcher_step >= 1 and dispatcher_step else "instructor"

static func _has_coach_text(key: String) -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/coach_steps.json"))
	return data is Dictionary and (data as Dictionary).get("en", {}).has(key)

func _dispatcher_next() -> void:
	if _dispatcher_step != 1: return
	_dispatcher_step = 2
	_dispatcher_say("speaker")
	_last_coach_step = ""
	_announce_coach_step()

func _dispatcher_say(key: String) -> void:
	var lang := bystander_language()
	var text: String = DISPATCHER[key].get(lang, DISPATCHER[key].en)
	_toast(text)
	audio_manager.speak(text, lang, "", "dispatcher")

## --- Situation A: the phone (step 4, agreed 18 Nov 2026) ---------------------------------
## No real phone: one appears in the left hand. Tap 112, then Speaker; then it lies beside
## the person. Hints: no tap 10 s after the instruction, no Speaker 5 s after 112.
## Then the trainee lays it down (ERC: on speaker, next to you, hands free): lowered to
## PHONE_DOWN_M above the floor it stays there. Not a gate: after PHONE_PLACE_S, or once
## CPR starts, it glides beside the head on its own.
const PHONE_DOWN_M := 0.12
const PHONE_PLACE_S := 12.0
var _phone_placing_ms := 0
var phone: NaretVirtualPhone
var _call_asked_ms := 0
var _phone_hinted := {}

func _update_phone() -> void:
	if scenario == null or _smoke_mode: return
	var call_step := scenario.alone and scenario.state == NaretScenario.State.CALL_HELP and not scenario.emergency_called
	if phone == null:
		if not call_step: return
		phone = NaretVirtualPhone.new()
		add_child(phone)
		phone.configure(origin, interaction)
		phone.dialed.connect(func(): _play_phone_ring())
		phone.speaker_on.connect(func(): _on_action("call_emergency", {"source": "phone"}))
	if phone.state == "placing":
		if hand_menu: hand_menu.suppressed = true
		if phone.global_position.y - _speaker_floor_y() < PHONE_DOWN_M:
			_put_phone_down(phone.global_position)
		elif scenario.state == NaretScenario.State.CPR or Time.get_ticks_msec() - _phone_placing_ms > PHONE_PLACE_S * 1000.0:
			_put_phone_down()
		return
	if call_step and phone.state == "hidden": phone.offer(_language)
	if hand_menu: hand_menu.suppressed = phone.in_hand()
	if not call_step or audio_manager.is_speaking(): return
	var now := Time.get_ticks_msec()
	if phone.state == "dial" and _call_asked_ms > 0 and now - _call_asked_ms > 14000 and not _phone_hinted.has("dial"):
		# About 10 s after the instruction ended.
		_phone_hinted["dial"] = true
		print("NARET_PHONE no tap on 112 yet")
		_coach_line("coach.phone_tap_112")
	elif phone.state == "calling" and now - phone.dialed_ms > 5000 and not _phone_hinted.has("speaker"):
		_phone_hinted["speaker"] = true
		print("NARET_PHONE no speaker yet")
		_coach_line("coach.phone_speaker")

## The call is on speaker: the phone stays in the hand until it is laid down (or glides down
## by itself after PHONE_PLACE_S). 26 Nov 2026: no separate "put the phone down" line any
## more; the speaker hint says both in one short sentence.
func _phone_on_speaker() -> void:
	if phone == null:
		phone = NaretVirtualPhone.new()
		add_child(phone)
		phone.configure(origin, interaction)
	if phone.state != "placing": phone.hold_on_speaker(_language)
	_phone_placing_ms = Time.get_ticks_msec()

## On the ground: where the hand put it (`at`), or else gliding beside the head, on the
## trainee's side.
func _put_phone_down(at := Vector3.INF) -> void:
	var body := mannequin.get_body_transform().orthonormalized()
	var eye := body.affine_inverse() * (xr_camera if xr.active else desktop_camera).global_position
	var side := 1.0 if eye.x >= 0.0 else -1.0
	var spot := body * Vector3(side * 0.30, 0.0, -PATIENT_TO_CROWN_M - 0.12)
	spot.y = _aed_rest_y()
	if at.is_finite():
		spot = Vector3(at.x, _speaker_floor_y(), at.z)
	phone.put_down(spot, -body.basis.z, not at.is_finite())
	if hand_menu: hand_menu.suppressed = false
	print("NARET_PHONE on the ground at ", spot)

## --- Handover to the ambulance crew (issue #1, 8.) -------------------------------------
## The crew arrives after a while of CPR: in A after EMS_ALONE_S (1 min) of compressions, in B after
## the AED's second decision (or EMS_LATEST_S at the latest). The trainee keeps pressing,
## hands over briefly (NaretHandover), steps back; then the debrief.
const EMS_ALONE_S := 60.0 # 1 min of CPR (user, 17 Nov 2026)
const EMS_LATEST_S := 480.0
var _ems_state := 0 # 0 not there, 1 asked for the handover, 2 taken over
var _ems_facts: Array = []
var _ems_since_ms := 0
var _ems_answers := 0
var _ems_handover_missing: Array[String] = []
var _ems_taken_ms := 0
## Step-back gate (issue #1, 8.): after "Treten Sie bitte zurück" the training ends only when
## no hand is at the patient and no compression came for STEP_BACK_S; after 8 s without it
## the crew asks once more.
const STEP_BACK_S := 2.0
var _step_back_clear_s := 0.0
var _step_back_reminded := false
var _pause_overs := 0

func _update_step_back(delta: float) -> void:
	if _ems_state != 2 or scenario == null or not "handover" in scenario.get_available_actions(): return
	# The avatar's real body shape (bone capsules), not the AED's narrow contact strip.
	var hands_on := xr != null and xr.active and interaction != null and interaction.hands_touch_body()
	var pressing := Time.get_ticks_msec() - _last_compression_ms < 1500
	_step_back_clear_s = 0.0 if hands_on or pressing else _step_back_clear_s + delta
	if _step_back_clear_s >= STEP_BACK_S and not audio_manager.is_speaking():
		print("NARET_EMS stepped back")
		_on_action("handover", {"source": "ems", "handover_facts": _ems_facts})
	# 26 Nov 2026: no separate "take your hands off" reminder any more; the crew's take-over
	# line already says it.

## Debrief (issue #1, 8.): after the handover the results open and the instructor speaks a
## short professional debrief built from the session's measurements (NaretDebrief).
func _give_debrief() -> void:
	var summary := _session_summary()
	var extra := {"situation": situation, "pause_overs": _pause_overs}
	if _ems_state == 2: extra["handover_missing"] = _ems_handover_missing
	var debrief: Dictionary = NaretDebrief.build(summary, extra, _language)
	_debrief_text = str(debrief.text)
	print("NARET_DEBRIEF ", str(debrief.spoken).left(300))
	_open_briefing()
	if audio_manager and not _smoke_mode:
		audio_manager.instructor_voice = "" # the debrief is the instructor's
		audio_manager.speak(str(debrief.spoken), _language, "", "instructor", true)

var _debrief_text := ""
var _cpr_since_ms := -1

func _update_ems() -> void:
	if scenario == null or _smoke_mode: return
	if scenario.state != NaretScenario.State.CPR and scenario.state != NaretScenario.State.AED:
		if scenario.state < NaretScenario.State.CPR: _cpr_since_ms = -1
		return
	var now := Time.get_ticks_msec()
	if _cpr_since_ms < 0: _cpr_since_ms = now
	var cpr_s := (now - _cpr_since_ms) / 1000.0
	if _ems_state == 0 and scenario.state == NaretScenario.State.CPR:
		var due := cpr_s >= EMS_LATEST_S
		if scenario.alone: due = cpr_s >= EMS_ALONE_S
		elif scenario.aed_decisions_completed >= 2: due = true # after the 2nd AED analysis (user, 17 Nov 2026)
		if due:
			_ems_state = 1
			# The ambulance is there: the call ends. Until the training is over the crew says
			# the handover prompts; the instructor speaks again only for "finish" and the debrief.
			if audio_manager: audio_manager.instructor_voice = "ems"
			_ems_facts = []
			_ems_since_ms = now
			print("NARET_EMS arrived cpr_s=%.0f" % cpr_s)
			# One prompt, once (26 Nov 2026): the crew asks for the whole handover in one
			# sentence; no follow-up questions, hints or yes/no confirmations any more.
			_ems_say("arrive_aed" if "aed" in _ems_required() else "arrive")
	elif _ems_state == 1 and now - _ems_since_ms > (EMS_AFTER_ANSWER_MS if _ems_answers > 0 else EMS_NO_ANSWER_MS):
		# The trainee has finished (or said nothing): the crew takes over; anything missing
		# goes into the debrief.
		_ems_finish()

## After the trainee's last sentence the crew waits this long before taking over; with no
## answer at all, this long after their question.
const EMS_AFTER_ANSWER_MS := 6000
const EMS_NO_ANSWER_MS := 20000

func _on_handover_speech(text: String) -> void:
	_ems_since_ms = Time.get_ticks_msec()
	for fact in NaretHandover.facts(text, _language):
		if scenario.alone and fact in ["aed", "shock"]: continue # Situation A has no AED
		if fact == "shock": fact = "aed" # "the AED shocked" answers the AED question
		if not fact in _ems_facts: _ems_facts.append(fact)
	print("NARET_EMS handover facts=", _ems_facts)
	_ems_answers += 1
	# Everything said: the crew takes over at once.
	if _ems_missing().is_empty(): _ems_finish()

## The required facts: the three of every handover, plus the AED in B when it shocked.
func _ems_required() -> Array[String]:
	var required: Array[String] = []
	required.assign(NaretHandover.REQUIRED)
	if not scenario.alone and scenario.shock_count > 0: required.append("aed")
	return required

func _ems_missing() -> Array[String]:
	var out: Array[String] = []
	for fact in _ems_required():
		if not fact in _ems_facts: out.append(fact)
	return out

func _ems_finish() -> void:
	if _ems_state != 1: return
	_ems_state = 2
	# The facts not said go into the debrief.
	_ems_handover_missing.assign(_ems_missing())
	_ems_taken_ms = Time.get_ticks_msec()
	_step_back_clear_s = 0.0
	_step_back_reminded = false
	_ems_say("take_over")

func _ems_say(key: String) -> void:
	var lang := bystander_language()
	var text := NaretHandover.crew_line(key, lang)
	_toast(text)
	audio_manager.speak(text, lang, "", "ems")

## Breaths (issue #1, 6.): the interruption for the two breaths stays under 10 s. Measured
## from the 30th compression to the next one; one spoken hint per pause.
const BREATH_PAUSE_S := 10.0
var _breath_pause_from := -1
var _breath_pause_hinted := false

func _update_breath_pause() -> void:
	if scenario == null or _smoke_mode: return
	if _ems_state > 0: return # the crew is there: no more hints
	var pausing := scenario.state == NaretScenario.State.CPR and not scenario.compression_only and scenario.cycle_compressions >= 30
	if not pausing:
		_breath_pause_from = -1
		_breath_pause_hinted = false
		return
	var now := Time.get_ticks_msec()
	if _breath_pause_from < 0: _breath_pause_from = now
	# Counted from the end of the instruction, not while it is still being spoken.
	if audio_manager.is_speaking() and not _breath_pause_hinted: _breath_pause_from = now
	if not _breath_pause_hinted and now - _breath_pause_from > int(BREATH_PAUSE_S * 1000.0):
		_breath_pause_hinted = true
		_pause_overs += 1
		print("NARET_BREATHS pause over 10 s")
		var hint := NaretLanguage.text("coach.pause_too_long", _language)
		_toast(hint)
		audio_manager.speak(hint, _language, "", _guide_speaker())

## Response check (issue #1, 3., 18 Nov 2026): the trainee taps the shoulders (seen by hand
## tracking, as before) and reports that the person does not respond. The step advances
## only with both (the scenario refuses a report without the shoulders). Feedback by what
## is missing; "the person responds" is corrected. Subtitles show the instructor's words.
var _response_asked := false
var _response_asked_ms := 0
var _response_bubble_text := ""
var _shoulders_hinted := false
var _report_hinted := false
var _shoulders_seen_ms := 0
## The tap was seen in this response step (a flag: a time of 0 can be a real time).
var _tap_seen := false

## 20 Nov 2026 (user: "track the stated intention separately from whether the action has
## actually been completed"): a report that came before its action ("he is not responding"
## without the shoulder tap, "he is not breathing" without the head tilt) is kept. The
## instructor says what is still missing, once; as soon as the action is seen the step goes
## on by itself. Nothing is asked again and the trainee does not have to repeat the report.
var _response_reported := false
var _response_refusals := 0
var _breathing_reported := false

func _update_remembered_reports() -> void:
	if scenario == null or interaction == null or audio_manager == null: return
	if _response_reported and scenario.state == NaretScenario.State.CHECK_PATIENT and _shoulder_gate_active() and interaction.shoulder_check.evidence_recent():
		_response_reported = false
		# 26 Nov 2026: no spoken "I saw you tap their shoulders" any more; the step just goes on.
		print("NARET_RESPONSE the tap is seen; the report was already given: on to the next step")
		_on_action("check_responsiveness", {"source": "speech_confirmed"})
	if _breathing_reported and scenario.state == NaretScenario.State.CALL_HELP and scenario.emergency_called and not scenario.breathing_checked \
			and _face_gate_active() and interaction.head_tilt_played and interaction.face_check.evidence_recent():
		_breathing_reported = false
		print("NARET_BREATHING the check is seen; the report was already given: on to the next step")
		_on_action("check_breathing", {"source": "speech_confirmed"})
	if scenario.state != NaretScenario.State.CHECK_PATIENT: _response_reported = false
	if scenario.state != NaretScenario.State.CALL_HELP: _breathing_reported = false

func _reset_response_gates() -> void:
	_response_reported = false
	_response_refusals = 0
	_response_asked = false
	_response_bubble_text = ""
	_shoulders_hinted = false
	_report_hinted = false
	_shoulders_seen_ms = 0
	_tap_seen = false

## An instructor line in the response step, spoken and as subtitles.
func _response_line(key: String) -> void:
	_response_bubble_text = NaretLanguage.text(key, _language)
	_toast(_response_bubble_text)
	audio_manager.speak(_response_bubble_text, _language, "", "instructor")

## 20 Nov 2026 (user: "give me time to act and speak; don't immediately repeat 'please tap
## his shoulders'; if there's no answer after a reasonable pause, ask 'Does he respond?'"):
## the hints count from the end of the last voice line and never come while the trainee is
## speaking or being recognised. The tap line is said once by this timer, and not at all if
## it was already the answer to a report without a tap. "Does he respond?" comes once: 6 s
## after a tap was seen, or 10 s after the tap line when still nothing is said. Before: the
## tap line 10 s after the instruction BEGAN, whether or not anyone was speaking.
const RESPONSE_TAP_HINT_MS := 15000
const RESPONSE_ASK_AFTER_TAP_MS := 4000
const TAP_QUESTION_DELAY_MS := 1200
const RESPONSE_ASK_AFTER_HINT_MS := 10000

func _update_response_hint() -> void:
	if scenario == null or scenario.state != NaretScenario.State.CHECK_PATIENT or not _response_asked: return
	if not _head_scan_gate_active() or audio_manager.is_speaking() or _trainee_talking(): return
	var now := Time.get_ticks_msec()
	var quiet := now - maxi(_voice_end_ms, _response_asked_ms)
	var shoulders: bool = interaction != null and interaction.shoulder_check.evidence_recent()
	if shoulders and not _tap_seen:
		_tap_seen = true
		_shoulders_seen_ms = now
		print("NARET_RESPONSE tap seen")
	var tapped := _tap_seen
	# 21 Nov 2026, the user's exact sequence: once the tap is seen (and the hands have had
	# TAP_QUESTION_DELAY_MS to finish it), the instructor says "I saw you tap their
	# shoulders. Are they responding? Please say yes or no." once, and waits for the answer.
	# "No" is the report and the step goes on; "yes" is corrected (this patient never
	# responds). Already reported before the tap: see _update_remembered_reports.
	if tapped and not _report_hinted and not _response_reported and now - _shoulders_seen_ms >= TAP_QUESTION_DELAY_MS:
		_report_hinted = true
		print("NARET_RESPONSE tap seen: asking whether they respond (yes or no)")
		_response_line("coach.tap_seen_ask")
		return
	if not tapped and not _shoulders_hinted and quiet > RESPONSE_TAP_HINT_MS:
		_shoulders_hinted = true
		print("NARET_RESPONSE no shoulder tap yet (quiet %d ms)" % quiet)
		_response_line("error.shoulders_not_seen")
	elif not _report_hinted and not _response_reported and not tapped and _shoulders_hinted and quiet > RESPONSE_ASK_AFTER_HINT_MS:
		_report_hinted = true
		print("NARET_RESPONSE no report yet: asking whether he responds (tapped=%s, quiet %d ms)" % [tapped, quiet])
		_response_line("coach.report_response")

## "The person responds" (or "yes" to the report question): this patient never does.
static func _reports_responding(text: String, language: String) -> bool:
	var clean := " " + text.to_lower().replace(",", " ").replace(".", " ").replace("!", " ").replace("?", " ") + " "
	var negations := {"de": [" nicht ", " kein", " nein "], "pl": [" nie "], "en": [" not ", "n't ", " no ", "unresponsive", "unconscious"]}
	for word: String in negations.get(language, negations.en):
		if word in clean: return false
	var positives := {"de": ["reagiert", "ist wach", "ansprechbar", "öffnet die augen", "bewegt sich", "antwortet"],
		"pl": ["reaguje", "jest przytomn", "otwiera oczy", "rusza się", "odpowiada"],
		"en": ["respond", "is awake", "is conscious", "opens his eyes", "opens her eyes", "is moving", "answers"]}
	for word: String in positives.get(language, positives.en):
		if word in clean: return true
	return false

## Safety step (issue #1): the head has to turn left and right before "the area is safe".
var head_scan := NaretHeadScan.new()

func _head_scan_gate_active() -> bool:
	# The PC test bench (below) has a head to turn too, but no hands: only the safety step.
	if _pc_bench: return scenario != null and scenario.state == NaretScenario.State.INTRO
	return xr != null and xr.active and not _smoke_mode

func _update_head_scan() -> void:
	if scenario == null or scenario.state != NaretScenario.State.INTRO or not _head_scan_gate_active(): return
	head_scan.update(-(desktop_camera if _pc_bench else xr_camera).global_basis.z)
	if _looked_around() and _scan_done_ms == 0:
		print("NARET_SAFETY looked around: left=", head_scan.left, " right=", head_scan.right)
		_scan_done_ms = Time.get_ticks_msec()
		_safety_both_done()
	_safety_hints()

## Safety hints (18 Nov 2026): no head turn 10 s after S-1 -> look around; head turned
## but no answer for 5 s -> "Are the surroundings safe? Please answer yes or no." Once each.
var _safety_asked_ms := 0
var _scan_done_ms := 0

## Step 2 gate 1: the head turned to the left AND to the right.
func _looked_around() -> bool:
	return head_scan.done()
var _look_hinted := false
var _answer_hinted := false

## 19 Nov 2026 (headset: "it suddenly asks whether it is safe, no time to answer"): with the
## 20 degree turn the look-around is often complete while the instructor is still asking, and
## the 5 s ran out during his question. The hints now count from the end of the last voice
## line, and never come while the trainee is speaking or the words are being recognised.
const SAFETY_LOOK_HINT_MS := 10000
const SAFETY_ANSWER_HINT_MS := 8000
var _voice_end_ms := 0

func _trainee_talking() -> bool:
	return audio_manager.recording or bool(audio_manager.get("_transcribing"))

func _safety_hints() -> void:
	if not _safety_asked or audio_manager.is_speaking() or _trainee_talking(): return
	var now := Time.get_ticks_msec()
	var quiet := now - maxi(_voice_end_ms, _safety_asked_ms)
	if not _looked_around() and not _look_hinted and quiet > SAFETY_LOOK_HINT_MS:
		_look_hinted = true
		print("NARET_SAFETY hint: look left and right (quiet %d ms)" % quiet)
		_safety_line("coach.look_left_right")
	elif _looked_around() and not _answer_hinted and now - maxi(_scan_done_ms, maxi(_voice_end_ms, _safety_asked_ms)) > SAFETY_ANSWER_HINT_MS:
		print("NARET_SAFETY hint: is it safe? (quiet %d ms)" % quiet)
		_answer_hinted = true
		_safety_line("coach.tell_if_safe")

## 20 Nov 2026 (user): the safety step is the trainee SAYING that they check the surroundings
## (any similar wording) and DOING it (the look to the left and right), in either order. As
## soon as both are there the instructor asks whether the surroundings are safe; "yes"
## goes on to the next step. Before, only an exact report ("the scene is safe") counted, a
## sentence like "first I'll check the surroundings" got a clarification question, and after
## the look the question came only after 8 s of silence.
var _safety_stated := false

func _safety_statement(source: String) -> void:
	if scenario == null or scenario.state != NaretScenario.State.INTRO or NaretTrainingCoach.step(scenario) != "safety": return
	print("NARET_SAFETY statement heard (", source, "), looked_around=", _looked_around())
	_safety_stated = true
	_speech_confirmation.clear()
	_safety_both_done()

func _safety_both_done() -> void:
	## Statement and look are both there: ask whether it is safe, once.
	if not _safety_stated or _answer_hinted: return
	# Without a head to turn (desktop, tests) the statement alone stands for both.
	if _head_scan_gate_active() and not _looked_around(): return
	_answer_hinted = true
	print("NARET_SAFETY statement and look done: asking whether it is safe")
	_safety_line("coach.tell_if_safe")

## An instructor line in the safety step: spoken, and the subtitles show the same words.
var _safety_bubble_text := ""

func _safety_line(key: String) -> void:
	_safety_bubble_text = NaretLanguage.text(key, _language)
	_coach_line(key)

## Breathing (17 Nov 2026): the head is tilted but the trainee's head does not come to the
## mouth: after 5 s the guide says to come closer, once per step.
var _tilt_without_face_s := 0.0
var _closer_hinted := false

func _update_breathing_hint(delta: float) -> void:
	if scenario == null or not _face_gate_active() or scenario.state != NaretScenario.State.CALL_HELP \
			or not scenario.emergency_called or scenario.breathing_checked or _call_connecting():
		_tilt_without_face_s = 0.0
		_closer_hinted = false
		return
	if _closer_hinted or not interaction.head_tilt_played or interaction.face_check.evidence_recent():
		_tilt_without_face_s = 0.0
		return
	_tilt_without_face_s += delta
	if _tilt_without_face_s >= 5.0 and not audio_manager.is_speaking():
		_closer_hinted = true
		var hint := NaretLanguage.text("coach.closer_to_mouth", _language)
		_toast(hint)
		audio_manager.speak(hint, _language, "", _guide_speaker())

## Issue #1, 4.: after the call the trainee stays with the person. More than 2 m away from
## the patient for 2 s: "Bleib bei der Person." (at most every 15 s).
const STAY_DISTANCE_M := 2.0
var _away_s := 0.0
var _stay_said_ms := -100000

func _update_stay_with_person(delta: float) -> void:
	if scenario == null or not _head_scan_gate_active() or not scenario.emergency_called \
			or not scenario.state in [NaretScenario.State.CALL_HELP, NaretScenario.State.CPR] or _ems_state == 2:
		_away_s = 0.0
		return
	var offset := xr_camera.global_position - anchor.global_position
	offset.y = 0.0
	_away_s = _away_s + delta if offset.length() > STAY_DISTANCE_M else 0.0
	if _away_s >= 2.0 and Time.get_ticks_msec() - _stay_said_ms > 15000:
		_stay_said_ms = Time.get_ticks_msec()
		print("NARET_STAY away from the patient %.1f m" % offset.length())
		var line := NaretLanguage.text("coach.stay_with_person", _language)
		_toast(line)
		audio_manager.speak(line, _language, "", _guide_speaker())

## Safety subtitles: the instructor's words while the safety step is open.
var _safety_asked := false

func _update_safety_bubble() -> void:
	if speech_bubble == null or scenario == null or not _safety_asked: return
	if scenario.state != NaretScenario.State.INTRO or NaretTrainingCoach.step(scenario) != "safety": return
	# 20 Nov 2026 (user: "use the palm for all dialogue"): the card in the line of sight is
	# for the welcome only; once the training runs every line is in the palm's dialogue.
	if speech_bubble.visible: speech_bubble.hide_now()

## A short instructor line from the UI texts: shown on the wrist and spoken.
func _coach_line(key: String, keep: bool = false) -> void:
	var text := NaretLanguage.text(key, _language)
	_toast(text)
	if audio_manager and not _smoke_mode:
		audio_manager.speak(text, _language, "", "instructor", keep)

## The shoulder gate applies only where it can be satisfied: XR with tracked hands seen
## recently. Controllers or desktop keep the plain report, as before.
## The gate stays on (13 Nov 2026: only the yellow frames were to go, not the check).
const SHOULDER_GATE := true

func _shoulder_gate_active() -> bool:
	return SHOULDER_GATE and xr != null and xr.active and interaction != null and interaction.shoulder_check.active and interaction.hands_seen_recently()

## The bag gate: in XR the breaths come from the device, never from a sentence.
func _bvm_gate_active() -> bool:
	return xr != null and xr.active and bvm != null and interaction != null and interaction.hands_seen_recently()

## The face gate needs only the headset pose, which XR always has.
func _face_gate_active() -> bool:
	return xr != null and xr.active and interaction != null and interaction.face_check.active

var _phone_ring: AudioStreamPlayer3D
var bvm: Node3D
var _breath_refusal_ms := 0
var _hands_hint_given := false

func _play_phone_ring() -> void:
	if _smoke_mode: return
	if _phone_ring == null:
		var path := "res://assets/audio/sfx/phone_ring.wav"
		if not ResourceLoader.exists(path): return
		_phone_ring = AudioStreamPlayer3D.new()
		_phone_ring.stream = load(path)
		_phone_ring.unit_size = 2.5
		_phone_ring.volume_db = -10.0
		$Bystanders/Anna.add_child(_phone_ring)
	var holder: Node3D = phone if scenario.alone and phone != null else $Bystanders/Anna
	if _phone_ring.get_parent() != holder: _phone_ring.reparent(holder, false)
	_phone_ring.play()

const NaretTrainingCoach = preload("res://scripts/ai/training_coach.gd")

func _continue_sequence() -> void:
	while not _pending_sequence.is_empty():
		var next_action: String = _pending_sequence.pop_front()
		if next_action in scenario.get_available_actions():
			print("NARET_SEQUENCE next=", next_action)
			ccbm.observe_action(next_action)
			return

var _early_call_request := false
## After one of the two tasks (112, AED) the instructor reminds of the other only after
## this long, so the trainee has time to give it (it was 4 s).
## After the AED was asked for (the call step's first request), the 112 request follows
## once Marek has answered (26 Nov 2026).
const SECOND_TASK_AFTER_AED_S := 3.0
var _marek_answers_in_turn := false
var _marek_go_text := ""

var _early_aed_request := false
var _early_aed_first := false

## What was asked before the call step is taken now, in the order it was asked.
func _take_early_call() -> void:
	if scenario.alone: return
	var called := false
	for task: String in (["aed", "call"] if _early_aed_first else ["call", "aed"]):
		if task == "call" and _early_call_request and "call_emergency" in scenario.get_available_actions():
			_early_call_request = false
			called = true
			print("NARET_CALL the request said earlier is taken now")
			_on_action("call_emergency", {"source": "speech"})
		if task == "aed" and _early_aed_request and "request_aed" in scenario.get_available_actions():
			_early_aed_request = false
			print("NARET_AED the request said earlier is taken now")
			_marek_answers_in_turn = called
			_on_action("request_aed", {"source": "speech"})
			_marek_answers_in_turn = false

func _on_event(event: Dictionary) -> void:
	if ccbm: ccbm.observe_accepted(event)
	if event.get("accepted", false) and event.get("action", "") == "check_responsiveness" and (_early_call_request or _early_aed_request):
		_take_early_call.call_deferred()
	if event.get("accepted", false) and not _pending_sequence.is_empty():
		_continue_sequence()
	score.record(event)
	logger.record(event)
	if event.get("accepted", false) and event.get("action", "") == "call_emergency" and not _smoke_mode and scenario.alone:
		# On speaker in the hand; the trainee lays it down. It rang already if 112 was tapped.
		var rang := phone != null and phone.state in ["calling", "placing"]
		_phone_on_speaker()
		_start_dispatcher(1.0 if rang else 2.5, not rang)
	elif event.get("accepted", false) and event.get("action", "") == "call_emergency" and not _smoke_mode:
		# Headset review 2026-11-03: with cloud TTS on a 2 s deadline this line often failed
		# to synthesise and Anna stayed silent. The baked "help" clip ("I am calling the
		# emergency services on 112") is the fallback when the synthesis does not arrive.
		audio_manager.speak(NaretLanguage.text("anna.calling_112", bystander_language()), bystander_language(), "help", "bystander")
		# Her phone: keypad tones and ringback from her position, a moment after she starts
		# speaking. Tied to the event, not to the spoken text, so the baked fallback clip
		# (different wording) rings too.
		get_tree().create_timer(1.5).timeout.connect(_play_phone_ring)
		# Situation B (fix 1, 17 Nov 2026): the dispatcher answers on Anna's phone, which is
		# on speaker, and leads the CPR as in A.
		_start_dispatcher(6.0, false)
	if event.get("accepted", false) and event.get("action", "") in ["shock", "resume_cpr"]:
		_last_coach_step = "" # Always announce the fresh set after either AED outcome.
		_last_compression_ms = 0 # Do not turn the AED pause into a CPR rate interval.
	if event.get("accepted", false): _announce_coach_step()
	# Contact during the analysis can come from Anna, not only from the trainee's hands.
	if event.get("action") == "patient_contact" and not event.get("accepted", true):
		_toast(NaretLanguage.text(str(event.get("reason", "")), _language))

func _on_state_changed(state: int) -> void:
	if observation_interpreter: observation_interpreter.cancel_pending()
	# After the handover: the debrief, once the closing line has been said.
	if state == NaretScenario.State.RECOVERY and scenario.outcome == "simulated_handover" and not _smoke_mode:
		get_tree().create_timer(5.0).timeout.connect(_give_debrief)
	if interaction: interaction.set_cpr_enabled(state == NaretScenario.State.CPR)
	if interaction: interaction.set_aed_active(state == NaretScenario.State.AED)
	if interaction: interaction.set_shoulder_check(state in [NaretScenario.State.INTRO, NaretScenario.State.CHECK_PATIENT])
	if state == NaretScenario.State.INTRO:
		head_scan.reset()
		_scan_done_ms = 0
	if state == NaretScenario.State.CHECK_PATIENT: _reset_response_gates()
	if interaction: interaction.set_face_check(state == NaretScenario.State.CALL_HELP)
	if state in [NaretScenario.State.IDLE, NaretScenario.State.INTRO]:
		ekg.set_rhythm(NaretEKG.Rhythm.VF)
		mannequin.zone.visible = true
		mannequin.set_recovered(false)
	if state == NaretScenario.State.RECOVERY:
		var recovered := scenario.outcome in ["trainer_simulated_rosc", "rosc"]
		mannequin.set_recovered(recovered)
		if recovered: ekg.set_rhythm(NaretEKG.Rhythm.SINUS, 75)
		mannequin.zone.visible = false # no compressions any more
		$Bystanders/Anna.set_emotion("grateful")
		_export_session.call_deferred()

func bystander_language() -> String:
	## Own-language mode keeps everyone in the trainee's language; the neighbour
	## mode replays the same steps with the bystander speaking the other one.
	## English has no neighbour language here (the pair is German and Polish): in English
	## everyone speaks English. Until 14 Nov 2026 English in neighbour mode made Anna
	## speak German, and the mode key on the wrist is easily touched by accident
	## ("after I chose English, Anna speaks German").
	if _mode == "own" or _language == "en":
		return _language
	return "pl" if _language == "de" else "de"


func _opening_line() -> String:
	return NaretLanguage.text("bystander.default", bystander_language())


var sensor_logger: NaretSensorLogger

func _add_sensor_logger() -> void:
	## Sensor log over Wi-Fi (from the team's merge/sensorlog branch, 17 Nov 2026): every
	## frame of hand, body and head tracking, the sternum and the scenario events, with a
	## live 3D view in a browser on the same network. A developer tool for testing
	## compression detectors against recordings: off at every start, switched on in the
	## wrist menu's Debug panel, and every request needs this headset's PIN.
	sensor_logger = NaretSensorLogger.new()
	sensor_logger.name = "SensorLogger"
	add_child(sensor_logger)
	sensor_logger.configure(origin, mannequin.sternum, scenario)
	sensor_logger.state_changed.connect(func(on: bool, url: String):
		if hand_menu: hand_menu.set_sensor_log(url)
		print("NARET_SENSOR_LOG ", "on port %d" % int(url.get_slice(":", 2).get_slice("/", 0)) if on else "off"))
	sensor_logger.take_changed.connect(func(recording: bool):
		if hand_menu: hand_menu.set_take(recording))
	if hand_menu:
		hand_menu.sensor_log_requested.connect(func(on: bool): sensor_logger.set_active(on))
		hand_menu.take_requested.connect(func(start: bool):
			if start:
				sensor_logger.set_active(true)
				sensor_logger.new_take({"source": "wrist_menu"})
			else:
				sensor_logger.stop_take())
	sensor_logger.context = func() -> Dictionary:
		return {"state": scenario.get_state_name(), "n": scenario.compressions,
			"cycle": scenario.cycle_compressions, "step": NaretTrainingCoach.step(scenario),
			"marker": tracker.status if tracker else "", "anchored": anchor.locked,
			"mode": interaction.counter_mode if interaction else "",
			"det_n": interaction.detector.count if interaction else 0,
			"det_p": snappedf(interaction.detector.probability, 0.01) if interaction else 0.0,
			"det_rate": snappedf(interaction.detector.rate_bpm, 1) if interaction else 0.0}
	sensor_logger.status_extra = func() -> Dictionary:
		return {"state": scenario.get_state_name(), "compressions": scenario.compressions, "language": _language,
			"marker": tracker.status if tracker else "", "anchored": anchor.locked,
			"metronome": interaction.metronome_bpm() if interaction else 0, "muted": AudioServer.is_bus_mute(0)}
	sensor_logger.control_requested.connect(_on_sensor_log_control)
	if interaction:
		interaction.compression_measured.connect(func(depth: float, rate: float, correct: bool):
			sensor_logger.log_line("detected", {"depth": snappedf(depth, 0.0001), "rate": snappedf(rate, 0.1), "correct": correct}))
		interaction.placement_changed.connect(func(correct: bool): sensor_logger.log_line("placement", {"correct": correct}))
		interaction.metronome_beat.connect(func(bpm: int): sensor_logger.log_line("beat", {"bpm": bpm}))
	# QCPR manikin values (ground truth) whenever one is connected.
	if qcpr:
		qcpr.compression_measured.connect(func(depth_mm: float, rate: float, recoil: bool, _quality: Dictionary):
			sensor_logger.log_line("qcpr", {"depth_mm": depth_mm, "rate": rate, "recoil": recoil}))

func _on_sensor_log_control(command: String, args: Dictionary) -> void:
	## Buttons on the sensor log web page.
	match command:
		"cpr":
			# Straight to compressions, compression-only and without an AED, so a take
			# is not interrupted by 30:2 pauses or the AED's analysis.
			_on_action("start")
			for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "compression_only"]:
				_on_action(action, {"source": "desktop"})
		"scenario":
			_on_action("start")
		"language":
			var lang := str(args.get("lang", "en"))
			if lang in NaretLanguage.SUPPORTED: _set_language(lang)
		"mute":
			AudioServer.set_bus_mute(0, args.get("on", "1") == "1")
		"metronome":
			if interaction: interaction.set_metronome_bpm(int(args.get("bpm", "0")))

## Questions before the scenario (team to-do, issue #1, 0. App-Start). See NaretSetupFlow.
var setup := NaretSetupFlow.new()
## "A" alone, no AED; "B" other people and an AED (didactic structure p. 6).
var situation := "B"
## "male" / "female": Polish forms like „sam/sama“ when Polish is the neighbour language.
var trainee_gender := ""
var speech_bubble: NaretSpeechBubble

## 17 Nov 2026: plus where to go next (the wrist; the key reads "Start training" in
## every language).
## 18 Nov 2026 (user): first the markers; the palm only once the patient is placed.
const WELCOME := {"de": "Hallo, willkommen beim NaReT-Simulator! Ich leite dich durch das Szenario. Schau zuerst von vorne auf die Marker an der Puppe.",
	"pl": "Cześć, witaj w symulatorze NaReT! Poprowadzę cię przez scenariusz. Najpierw spójrz z przodu na znaczniki na manekinie.",
	"en": "Hello, welcome to the NaReT simulator! I will guide you through the scenario. First, look at the markers on the mannequin from the front."}
const WELCOME_MENU := {"de": "Wähle Sprache, Modus, Situation und Beatmung aus und drück dann auf Start training.",
	"pl": "Wybierz język, tryb, sytuację i oddechy, a potem naciśnij Start training.",
	"en": "Choose your language, mode, situation and ventilation, then press Start training."}
var _menu_line_said := false
## The welcome card's heading (20 Nov 2026).
const WELCOME_TITLE := {"de": "Willkommen bei NaReT", "pl": "Witamy w NaReT", "en": "Welcome to NaReT"}
const WELCOME_PALM := {"de": "Die Person liegt jetzt richtig. Bitte öffne deine linke Handfläche, um das Menü zu öffnen.",
	"pl": "Pacjent jest na miejscu. Otwórz lewą dłoń, aby otworzyć menu.",
	"en": "The patient is in place. Please open your left palm to access the menu."}

## The instructor in front of the trainee during the welcome, until the patient is placed.
const WELCOME_INSTRUCTOR_M := 1.6
var _welcome_instructor := false
var _welcome_instructor_placed := false
## 20 Nov 2026 (user: "the welcome should start only when we see the instructor"): the
## greeting used to start with the app, before the headset had a pose and so before the
## instructor stood anywhere. In the headset it now waits until he stands in front and
## has been within WELCOME_SEEN_DEG of the line of sight for WELCOME_SEEN_MS.
const WELCOME_SEEN_DEG := 30.0
const WELCOME_SEEN_MS := 400
## Roughly the instructor's chest above his feet: what the eyes rest on at 1.6 m.
const WELCOME_LOOK_HEIGHT_M := 1.3
var _welcome_text := ""
var _welcome_seen_since_ms := -1

func _instructor_in_view() -> bool:
	if not $Instructor.is_visible_in_tree(): return false
	var to_him: Vector3 = $Instructor.global_position + Vector3.UP * WELCOME_LOOK_HEIGHT_M - xr_camera.global_position
	if to_him.length() < 0.2: return false
	return (-xr_camera.global_basis.z).angle_to(to_him) < deg_to_rad(WELCOME_SEEN_DEG)

func _say_welcome(text: String) -> void:
	# Subtitles in the line of sight until the left palm is opened (the menu appears).
	if speech_bubble: speech_bubble.say(text, 600.0, WELCOME_TITLE.get(_language, WELCOME_TITLE.en))
	audio_manager.speak(text, _language, "", "instructor")

func _update_welcome_instructor() -> void:
	if not _welcome_instructor: return
	if anchor.locked:
		# The patient is placed: the usual placement of the people takes over, and the
		# instructor tells the trainee to open the menu (subtitles until the palm opens).
		_welcome_instructor = false
		# A greeting still waiting is dropped: "look at the markers first" is done.
		_welcome_text = ""
		var palm: String = WELCOME_PALM.get(_language, WELCOME_PALM.en)
		if speech_bubble: speech_bubble.say(palm, 600.0, WELCOME_TITLE.get(_language, WELCOME_TITLE.en))
		audio_manager.speak(palm, _language, "", "instructor", true)
		print("NARET_WELCOME patient placed: open the palm")
		return
	if _welcome_instructor_placed:
		if _welcome_text.is_empty(): return
		if not _instructor_in_view():
			_welcome_seen_since_ms = -1
			return
		if _welcome_seen_since_ms < 0: _welcome_seen_since_ms = Time.get_ticks_msec()
		if Time.get_ticks_msec() - _welcome_seen_since_ms >= WELCOME_SEEN_MS:
			print("NARET_WELCOME instructor seen: greeting starts")
			_say_welcome(WELCOME.get(_language, WELCOME.de))
			_welcome_text = ""
		return
	var eye := xr_camera.global_position
	var floor_y := _speaker_floor_y()
	if not is_finite(floor_y) or eye.y - floor_y < 0.8: return # no headset pose yet
	var ahead := -xr_camera.global_basis.z
	ahead.y = 0.0
	if ahead.length() < 0.1: return
	var spot := eye + ahead.normalized() * WELCOME_INSTRUCTOR_M
	spot.y = floor_y
	$Instructor.place_on_floor(_speaker_floor_pose(spot, eye))
	$Instructor.visible = true
	_welcome_instructor_placed = true
	print("NARET_WELCOME instructor in front at %.1f m" % WELCOME_INSTRUCTOR_M)

func _welcome() -> void:
	## Speech bubble and voice in the line of sight, once at app start.
	if _smoke_mode: return
	speech_bubble = NaretSpeechBubble.new()
	speech_bubble.name = "WelcomeBubble"
	speech_bubble.camera = xr_camera if xr.active else desktop_camera
	add_child(speech_bubble)
	if not xr.active and "--pc-step1" in OS.get_cmdline_user_args(): _pc_bench_setup()
	var text: String = WELCOME.get(_language, WELCOME.de)
	_welcome_instructor = xr.active
	# In the headset the greeting waits for the instructor (_update_welcome_instructor);
	# on the desktop there is no instructor in front, so it starts at once as before.
	if xr.active: _welcome_text = text
	else: _say_welcome.call_deferred(text)
	if hand_menu:
		hand_menu.menu_shown_changed.connect(func(shown: bool):
			if not shown or speech_bubble == null: return
			# W-2c (18 Nov 2026): once the patient is placed and the palm is open, what to do in
			# the menu; it stays as subtitles until "Start training".
			if anchor.locked and not _menu_line_said and scenario.state == NaretScenario.State.IDLE:
				_menu_line_said = true
				var line: String = WELCOME_MENU.get(_language, WELCOME_MENU.en)
				speech_bubble.say(line, 600.0, WELCOME_TITLE.get(_language, WELCOME_TITLE.en))
				audio_manager.speak(line, _language, "", "instructor", true)
			elif speech_bubble.visible and not _menu_line_said: speech_bubble.hide_now())
	# The choices are the fold-out keys on the wrist (Languages, Mode, Situation,
	# Ventilation), preset; "Start training" uses whatever is set (18 Nov 2026).
	setup.answers = {"language": _language, "mode": _mode, "situation": situation, "breaths": "yes"}
	_load_setup_choices()
	print("NARET_SETUP answers=", setup.answers)
	if hand_menu: hand_menu.set_setup(setup.answers)

func _apply_setup_to_scenario() -> void:
	## Breaths only when trained, willing and with a barrier (p. 9): otherwise
	## uninterrupted compressions, no 30-compression gate.
	if setup.done() and setup.answers.get("breaths") == "no":
		scenario.compression_only = true
	scenario.set_meta("situation", situation)
	# Shock advised or not at random for every analysis (18 Nov 2026). Drawn once per
	# training, so an interrupted and repeated analysis gives the same decision.
	var pattern: Array[bool] = []
	for i in 12: pattern.append(randf() < 0.5)
	scenario.aed_training_pattern = pattern
	print("NARET_AED pattern ", pattern.slice(0, 4))
	scenario.alone = situation == "A"
	if scenario.alone:
		scenario.aed_available = false
	# Situation A: nobody else is there; Anna and Marek and their lines stay away.
	if director: director.process_mode = Node.PROCESS_MODE_DISABLED if scenario.alone else Node.PROCESS_MODE_INHERIT
	_ems_state = 0
	if audio_manager: audio_manager.instructor_voice = ""
	_ems_answers = 0
	_ems_handover_missing = []
	_pause_overs = 0
	_debrief_text = ""
	_dispatcher_step = 0

func _set_language(language: String) -> void:
	_language = language
	scenario.language = language
	_apply_language()


## Choices made on the hand menu. Two touches within MENU_CHOICE_GAP_MS are one touch
## (headset logs 13 Nov 2026: English, German and English again within a second, from
## one reach for the key), and the choice is kept for the next start of the app, which
## used to begin in German every time.
## 19 Nov 2026: the gap holds per key (language, mode, ...), no longer across keys: a mode
## chosen within 1.2 s of the language was dropped, so a choice seemed not to stick.
const MENU_CHOICE_GAP_MS := 1200
## A var so tests can write somewhere other than the real choice.
var language_file := "user://language_choice.cfg"
var _menu_choice_ms := {}

func _menu_choice_repeated(kind: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_menu_choice_ms.get(kind, -100000)) < MENU_CHOICE_GAP_MS: return true
	_menu_choice_ms[kind] = now
	return false

func _menu_language(language: String) -> void:
	if _menu_choice_repeated("language"): return
	_set_language(language)
	setup.answers["language"] = _language
	setup.answers["mode"] = _mode
	_save_language_choice()
	print("NARET_SETUP answers=", setup.answers)
	if hand_menu: hand_menu.set_setup(setup.answers)

func _menu_mode(mode: String) -> void:
	if _menu_choice_repeated("mode"): return
	_set_mode(mode)
	setup.answers["mode"] = _mode
	_save_language_choice()
	print("NARET_SETUP answers=", setup.answers)
	if hand_menu: hand_menu.set_setup(setup.answers)

## Situation, Ventilation and Gender from the wrist's setup keys.
func _menu_setup(step: String, value: String) -> void:
	if _menu_choice_repeated(step): return
	setup.answers[step] = value
	if step == "situation": situation = value
	if step == "gender": trainee_gender = value
	_save_language_choice()
	print("NARET_SETUP answers=", setup.answers)
	if hand_menu: hand_menu.set_setup(setup.answers)

## Every choice is kept: across the other choices, a restart of the training and the next
## start of the app (19 Nov 2026).
const SETUP_KEPT := ["situation", "breaths", "gender"]

func _save_language_choice() -> void:
	if _smoke_mode: return
	var file := ConfigFile.new()
	file.set_value("language", "selected", _language)
	file.set_value("language", "mode", _mode)
	for step: String in SETUP_KEPT:
		if setup.answers.has(step): file.set_value("setup", step, str(setup.answers[step]))
	file.save(language_file)

func _load_setup_choices() -> void:
	if _smoke_mode: return
	var file := ConfigFile.new()
	if file.load(language_file) != OK: return
	var allowed := {"situation": ["A", "B"], "breaths": ["yes", "no"], "gender": ["male", "female", "other"]}
	for step: String in SETUP_KEPT:
		var value := str(file.get_value("setup", step, ""))
		if value in allowed[step]: setup.answers[step] = value
	situation = str(setup.answers.get("situation", situation))
	trainee_gender = str(setup.answers.get("gender", trainee_gender))

func _load_language_choice() -> void:
	if _smoke_mode: return
	var file := ConfigFile.new()
	if file.load(language_file) != OK: return
	var language := str(file.get_value("language", "selected", _language))
	var mode := str(file.get_value("language", "mode", _mode))
	if language in ["de", "pl", "en"] and (language != _language or mode != _mode):
		_mode = mode if mode in ["own", "neighbour"] else "own"
		_set_language(language)

func _set_mode(mode: String) -> void:
	_mode = mode if mode in ["own", "neighbour"] else "own"
	_apply_language()


## Name cards over the three people (NaretNameTag), in the trainee's language. The
## instructor is named by his role; Marek's role is under his name. They replace the
## plain "Marek · AED" label that only Marek had.
const NAME_TAGS := {
	"Anna": {"name": {"en": "Witness", "de": "Zeugin", "pl": "Świadek"}, "role": {}},
	"Instructor": {"name": {"en": "NARET Instructor", "de": "NARET Instructor", "pl": "NARET Instructor"}, "role": {}}, # 19 Nov 2026 (user)
	"Marek": {"name": {"en": "AED Helper", "de": "AED-Helfer", "pl": "Pomocnik AED"}, "role": {}},
}
## Above the top of the head, so the card never covers the face.
const NAME_TAG_ABOVE_HEAD_M := 0.22
var _name_tags := {}

func _update_name_tags() -> void:
	for person in _speaker_people():
		if person == null: continue # tests that build main without the people
		var key := str(person.name)
		if not NAME_TAGS.has(key): continue
		if not _name_tags.has(key):
			var tag := NaretNameTag.new()
			tag.name = "NameTag"
			person.add_child(tag)
			tag.position = Vector3(0.0, _head_top_local(person) + NAME_TAG_ABOVE_HEAD_M, 0.0)
			_name_tags[key] = tag
		var texts: Dictionary = NAME_TAGS[key]
		(_name_tags[key] as NaretNameTag).set_text(str(texts.name.get(_language, texts.name.en)), str(texts.role.get(_language, texts.role.get("en", ""))))

## From the head bone (at the base of the skull) to the top of the head.
const HEAD_BONE_TO_TOP_M := 0.17

func _head_top_local(person: Node3D) -> float:
	## The top of the head, standing, in the person's own frame. Taken from the head
	## bone: the meshes' bounding boxes are larger than the body (the instructor's card
	## floated 40 cm over his head).
	for found in person.find_children("*", "Skeleton3D", true, false):
		var skeleton := found as Skeleton3D
		for bone in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(bone).to_lower()
			if bone_name.ends_with("head") or bone_name == "head":
				var at := skeleton.global_transform * skeleton.get_bone_global_rest(bone).origin
				var top := person.to_local(at).y + HEAD_BONE_TO_TOP_M
				if top > 1.0 and top < 2.3: return top
	return 1.75

func _apply_language() -> void:
	_speech_confirmation.clear()
	if observation_interpreter: observation_interpreter.cancel_pending()
	llm.cancel_pending()
	# Recognition follows the trainee's selection; Anna may speak another language.
	audio_manager.set_language(_language)
	_update_name_tags()
	print("NARET_LANGUAGE selected=", _language, " microphone=", audio_manager.language, " mode=", _mode, " bystander=", bystander_language())
	audio_manager.stop_speech()
	if dashboard:
		dashboard.set_language(_language)
		dashboard.set_mode(_mode)
	if hand_menu:
		hand_menu.set_language(_language)
		hand_menu.set_mode(_mode)
	if xr_info: xr_info.set_language(_language)
	if interaction: interaction.set_hud_language(_language)
	_toast("")
	_on_tracking_status(_last_tracking_status)
	_on_service_status(_last_service_status)
	_show_reply(_opening_line())
	# A language switch deliberately stops the old language. Reissue the active
	# instruction in the new language, instead of leaving its dedup flag set.
	_last_coach_step = ""
	_unclassified_spoken_step = ""
	if scenario != null and scenario.state != NaretScenario.State.IDLE:
		_announce_coach_step()

func _shadow_state_machine(event: Dictionary) -> void:
	## The explicit state machine only watches: the scenario still decides everything.
	## A mismatch is logged, so the two can be compared on real sessions.
	if not event.get("accepted", false): return
	var action := str(event.get("action", ""))
	if action not in FSM_ACTIONS: return
	var result: Dictionary = _fsm.handle(action)
	if not result.accepted:
		print("NARET_FSM mismatch action=", action, " machine_state=", _fsm.state_name(), " scenario_state=", scenario.get_state_name())

func _on_transcript(text: String) -> void:
	if text.strip_edges().is_empty(): return
	_dialogue_line("trainee", text)
	# The timed hints and questions count their silence from here too: nothing is asked
	# while an answer that was just given is still being worked on.
	_voice_end_ms = Time.get_ticks_msec()
	# "Please call 112" said before that step is due (with "he is not responding", or
	# while the shoulder tap is still open) is kept: the call starts as soon as the step
	# comes, and the trainee does not have to say it again (headset 20 Nov 2026).
	var early_states := [NaretScenario.State.INTRO, NaretScenario.State.CHECK_PATIENT]
	if scenario.state in early_states and not scenario.alone and preload("res://scripts/scenario/spoken_observation.gd").requests_emergency_call(text):
		_early_call_request = true
		print("NARET_CALL asked early, kept for the call step: ", text.left(80))
	# The same for "get the defibrillator" (headset 20 Nov 2026: asked early, it was lost,
	# and the instructor later asked "who gets the defibrillator?" although it had been said).
	if scenario.state in early_states and not scenario.alone and not scenario.cpr_witness_only and preload("res://scripts/scenario/spoken_observation.gd").requests_aed_fetch(text):
		_early_aed_request = true
		_early_aed_first = not _early_call_request or not preload("res://scripts/scenario/spoken_observation.gd").call_comes_first(text)
		print("NARET_AED asked early, kept for the call step: ", text.left(80))
	# The tasks are kept; what remains is the report of the step itself ("He is not
	# responding."). Left in, the whole sentence matched no rule and the report was lost.
	if scenario.state in early_states and (_early_call_request or _early_aed_request) and not scenario.alone:
		var report := preload("res://scripts/scenario/spoken_observation.gd").without_task_requests(text)
		if report != text:
			print("NARET_TRANSCRIPT tasks kept, the rest is the report: ", report.left(80))
			text = report
			if text.strip_edges().is_empty(): return
	if _ems_state == 1:
		_on_handover_speech(text)
		return
	# 26 Nov 2026: the crew has taken over; only "finish" and the debrief follow. Nothing the
	# trainee says now gets an answer.
	if _ems_state == 2:
		print("NARET_TRANSCRIPT ignored, training over: ", text.left(80))
		return
	if _dispatcher_step == 1 and _dispatcher_asked and not (not scenario.alone and "request_aed" in scenario.get_available_actions() and preload("res://scripts/scenario/spoken_observation.gd").requests_aed_fetch(text)):
		# She asked "what has happened, and where?": what is said now is the answer to HER
		# (only "get the defibrillator" is still for the helper). It is not read as a report
		# of the breathing step, which made the instructor say his breathing instruction in
		# the middle of the call (headset 20 Nov 2026).
		# After "where exactly are you?" a short answer ("Main Street") is enough.
		if _answers_dispatcher(text) or (_place_asked and not _words(text).is_empty()):
			print("NARET_DISPATCHER answered: ", text.left(80))
			# No place named: she asks once "where exactly are you?", then the call goes on.
			if not _place_asked and not _mentions_place(text):
				_place_asked = true
				_voice_end_ms = Time.get_ticks_msec()
				_dispatcher_say("where")
				return
			_dispatcher_next()
		elif _dispatcher_reasks < DISPATCHER_REASKS:
			_dispatcher_reasks += 1
			print("NARET_DISPATCHER did not get it, asks again: ", text.left(80))
			_voice_end_ms = Time.get_ticks_msec()
			_dispatcher_say("again")
		else:
			_dispatcher_next()
		return
	if scenario.state == NaretScenario.State.CHECK_PATIENT:
		# "The person responds" / "yes" is corrected: this patient never responds.
		if _reports_responding(text, _language) or (_report_hinted and NaretHandover.answers_yes(text, _language)):
			print("NARET_RESPONSE trainee reports a response: ", text.left(80))
			_response_line("coach.patient_unresponsive")
			return
		# "No" to "does the person respond or not?" is the report itself.
		if _report_hinted and NaretHandover.answers_no(text, _language) and not NaretTrainingCoach.asks_for_help(text):
			_on_action("check_responsiveness", {"source": "speech_confirmed"})
			return
	if scenario.state == NaretScenario.State.CHECK_PATIENT and preload("res://scripts/scenario/spoken_observation.gd").is_response_address(text):
		var rest := preload("res://scripts/scenario/spoken_observation.gd").without_patient_address(preload("res://scripts/scenario/spoken_observation.gd").normalise(text))
		if rest.strip_edges().is_empty(): return
	# A newer utterance supersedes an outstanding model interpretation/repair.
	if observation_interpreter: observation_interpreter.cancel_pending()
	if preload("res://scripts/scenario/spoken_observation.gd").reports_breath_pair(text):
		_last_heard_report = text.left(100)
		_record_speech_status("heard")
		print("NARET_TRANSCRIPT ", text.left(160))
		_speech_confirmation.clear()
		ccbm.observe_breath_pair()
		return
	# Both helpers in one sentence: they answer in the order they were asked (user, 20 Nov
	# 2026: "if to Anna request first then Anna should do, else defib should do"). Asked
	# first, Marek answers at once; asked second, his answer follows Anna's "I'm calling 112".
	const Spoken = preload("res://scripts/scenario/spoken_observation.gd")
	if Spoken.requests_aed_fetch(text) and Spoken.requests_emergency_call(text):
		print("NARET_TRANSCRIPT both helpers: ", text.left(160))
		if Spoken.call_comes_first(text) and "call_emergency" in scenario.get_available_actions() and not scenario.alone:
			_speech_confirmation.clear()
			# Taken directly, like the AED task. Headset 21 Nov 2026: handed to the step
			# model first, its answer was still on the way when the AED task was accepted
			# in the same moment; that made the model's answer "uncertain", the call was
			# dropped and the trainee had to say "please call 112" again.
			_on_action("call_emergency", {"source": "speech"})
			if "request_aed" in scenario.get_available_actions():
				_marek_answers_in_turn = true
				_on_action("request_aed", {"source": "speech"})
				_marek_answers_in_turn = false
			return
		if "request_aed" in scenario.get_available_actions():
			_on_action("request_aed", {"source": "speech"})
		# The call is taken from this sentence directly. Left to the general reading,
		# "Anna, please call 112 and Marek, could you bring the AED?" came back as
		# "uncertain" and the trainee had to say the call again (headset 14 Nov 2026;
		# Marek had already been sent from the hand menu, so the sentence was not even
		# recognised as the double request).
		if "call_emergency" in scenario.get_available_actions():
			_speech_confirmation.clear()
			_on_action("call_emergency", {"source": "speech"})
			return
		text = Spoken.without_aed_clause(text)
		if text.strip_edges().is_empty(): return
	# A plain request to call 112 at the call step is taken as it is, without the cloud's
	# reading of the sentence in between (20 Nov 2026: "please call 112" was not picked up).
	if not scenario.alone and "call_emergency" in scenario.get_available_actions() and Spoken.requests_emergency_call(text):
		print("NARET_CALL request heard: ", text.left(80))
		_speech_confirmation.clear()
		_on_action("call_emergency", {"source": "speech"})
		return
	# The same for a plain "get the defibrillator" in any wording: before, only eleven exact
	# sentences were taken directly and everything else depended on the cloud's reading.
	if not scenario.alone and "request_aed" in scenario.get_available_actions() and Spoken.requests_aed_fetch(text):
		print("NARET_AED request heard: ", text.left(80))
		_speech_confirmation.clear()
		_on_action("request_aed", {"source": "speech"})
		return
	var aed_request := preload("res://scripts/scenario/spoken_observation.gd").aed_action_for(text)
	if not aed_request.is_empty():
		_on_spoken_action(aed_request)
		return
	# Help questions cannot become a completed clinical observation.
	if NaretTrainingCoach.asks_for_help(text):
		_queue_coach_question(text)
		return
	if NaretTrainingCoach.asks_witness(text):
		_on_conversation(text)
		return
	_last_heard_report = text.left(100)
	_record_speech_status("heard")
	print("NARET_TRANSCRIPT ", text.left(160))
	# Several steps in one breath (11 Nov 2026): each clear sentence is taken in order, a step
	# already done or not yet due is skipped, and the next is handed over once the previous
	# was accepted. Only when at least one of them is due now; otherwise the usual path.
	var sequence: Array[String] = preload("res://scripts/scenario/spoken_observation.gd").actions_for(text)
	if sequence.size() >= 2 and sequence.any(func(a: String) -> bool: return a in scenario.get_available_actions()):
		_speech_confirmation.clear()
		_pending_sequence = sequence
		print("NARET_SEQUENCE heard=", sequence)
		_continue_sequence()
		return
	# Scene safety is understood by meaning before the phrase grammar and the cloud: trainees
	# got stuck at this first step, and "not safe" had no answer at all (2026-11-03).
	if "begin_check" in scenario.get_available_actions():
		var safety := preload("res://scripts/scenario/spoken_observation.gd").classify_safety(text, _language)
		# A plain "yes" / "no" to "Are the surroundings safe?" (18 Nov 2026).
		if safety.is_empty() and NaretHandover.answers_yes(text, _language): safety = "safe"
		elif safety.is_empty() and NaretHandover.answers_no(text, _language): safety = "unsafe"
		if safety == "safe":
			print("NARET_SAFETY safe")
			_speech_confirmation.clear()
			# Said before the look: it counts as the statement, and the question whether it is
			# safe follows once the trainee has looked (the gate in _on_action asks for the look).
			if _head_scan_gate_active() and not _looked_around(): _safety_stated = true
			ccbm.observe_action("begin_check")
			return
		if safety == "unsafe":
			# The instructor answers from the deviation guide: remove the danger, move him, or keep
			# away and call 112 when there is no safe place. Without the cloud it repeats the step.
			# 14 Nov 2026: answered at once with a fixed line. It used to go to the language
			# model only, which takes seconds and, when the cloud is slow or away, said
			# nothing ("it is not responding to: the scene is not safe").
			#
			# Same day, the wording: in this exercise the scene IS safe, so the instructor
			# does not explain what to do about a danger. The first time he says he thinks
			# it is safe and asks to check again; the second time he is sure, and the
			# exercise goes on to the patient instead of going round in a circle.
		# 16 Nov 2026 ("'Go to the patient' seems very generic"): the second answer names
		# what he checked (no traffic, fire, electricity, gas or water). What to do next
		# is the response step's own instruction, which follows it at once.
			_unsafe_reports += 1
			print("NARET_SAFETY unsafe count=", _unsafe_reports)
			_speech_confirmation.clear()
			var answer := NaretLanguage.text("coach.scene_unsafe" if _unsafe_reports == 1 else "coach.scene_unsafe_again", _language)
			_safety_bubble_text = answer
			_toast(answer)
			_show_reply(answer)
			if audio_manager and not _smoke_mode:
				audio_manager.speak(answer, _language, "", "instructor")
			if _unsafe_reports >= 2:
				ccbm.observe_action("begin_check")
			return
		# "First I'll check the surroundings" and the like: the statement of this step.
		if NaretTrainingCoach.step(scenario) == "safety" and preload("res://scripts/scenario/spoken_observation.gd").states_safety_check(text):
			_safety_statement("words")
			return
	if _language in ["en", "de", "pl"]:
		var context := _confirmation_context()
		var interpreted: Dictionary = _speech_confirmation.evaluate(text, context, scenario.get_available_actions(), Time.get_ticks_msec(), _language)
		if interpreted.has("action"):
			if interpreted.get("breaths", 1) == 2:
				ccbm.observe_breath_pair()
			else:
				ccbm.observe_action(str(interpreted.action))
			return
		if interpreted.has("proposal"):
			var candidate := str(interpreted.proposal)
			var question := preload("res://scripts/ai/speech_pipeline.gd").Confirmation.question(candidate, int(interpreted.get("breaths", 1)), _language)
			_toast(question)
			# Exact text is mandatory: do not substitute a one-breath recording
			# for a two-breath question or an unrelated clip when TTS is down.
			_speak_question(question, candidate)
			return
		if interpreted.has("message"):
			_toast(str(interpreted.message))
			audio_manager.speak(str(interpreted.message), _language, "", _guide_speaker())
			return
	# Progression observations go to CCBM, never to Anna's generated action field.
	if ccbm and ccbm.observe_speech(text): return
	# The step this sentence belongs to: its answer may come after the step moved on.
	_transcript_step = NaretTrainingCoach.step(scenario)
	observation_interpreter.interpret(text, bystander_language(), _confirmation_context())

func _confirmation_context() -> String:
	return str(scenario.state) + ":" + str(scenario.get_available_actions()) + ":" + str(scenario.cycle_compressions) + ":" + str(scenario.cycle_ventilations)


## When nothing usable was heard (silence, empty transcript, cloud doubt), ask about the step
## the trainee is on as the yes/no question the confirmation path accepts (11 Nov 2026).
## "Did you report that he is not breathing normally?" is answered with one word; "please say
## it again" looped on the headset (9 Nov). Steps without a spoken report keep the old prompt.
func _ask_step_question() -> bool:
	if scenario == null or _smoke_mode or audio_manager == null or _call_connecting(): return false
	var pick: Dictionary = NaretTrainingCoach.step_question(NaretTrainingCoach.step(scenario))
	if pick.is_empty() or str(pick.action) not in scenario.get_available_actions(): return false
	_speech_confirmation.propose(str(pick.action), _confirmation_context(), Time.get_ticks_msec(), _language, int(pick.breaths))
	var question := preload("res://scripts/ai/speech_pipeline.gd").Confirmation.question(str(pick.action), int(pick.breaths), _language)
	_toast(question)
	_speak_question(question, str(pick.action))
	return true

## The same yes/no question is not spoken again within this time. It has three
## independent triggers (an unclear sentence, a touch without a report after 10 s, a
## silent recording), and in the headset on 14 Nov 2026 they fired one after the other:
## "Did you report that he is not responding?" three times in a row. It stays open for a
## "yes" and stays on the display; it is just not said again so soon.
const QUESTION_QUIET_MS := 25000
var _question_said := ""
var _question_said_ms := -100000

func _speak_question(question: String, action: String = "") -> void:
	var now := Time.get_ticks_msec()
	if question == _question_said and now - _question_said_ms < QUESTION_QUIET_MS:
		print("NARET_QUESTION not repeated (asked %.0f s ago)" % ((now - _question_said_ms) / 1000.0))
		return
	_question_said = question
	_question_said_ms = now
	# The breaths question is always the dispatcher's (26 Nov 2026), never the instructor's.
	var speaker := "dispatcher" if action == "ventilation" else _guide_speaker()
	audio_manager.speak(question, _language, "", speaker)

func _on_conversation(text: String) -> void:
	if NaretTrainingCoach.asks_for_help(text):
		_queue_coach_question(text)
		return
	var context := NaretTrainingCoach.context(scenario, bystander_language())
	context["speaker"] = "bystander"
	context["bystander_state"] = $Bystanders/Anna.emotion
	llm.enqueue_transcript(text, context)

## Help and uncertainty (18 Nov 2026): what the trainee has done and what is still missing in
## this step, for the cloud instructor; offline, the recorded hint for the first missing one.
var _help_step := ""
var _help_asked_ms := -100000
var _help_attempt := 0

func _step_actions() -> Dictionary:
	var done: Array[String] = []
	var missing: Array[Dictionary] = []
	var step := NaretTrainingCoach.step(scenario)
	var hands := interaction != null and xr != null and xr.active
	match step:
		"setup":
			if anchor.locked: done.append("patient placed on the markers")
			else: missing.append({"what": "look at the markers on the mannequin from the front until the patient appears", "hint": ""})
			missing.append({"what": "open the left palm, choose language, mode, situation and ventilation, press Start training", "hint": ""})
		"safety":
			if head_scan.done(): done.append("looked left and right")
			else: missing.append({"what": "turn the head to the left and to the right to look for hazards", "hint": "coach.look_left_right"})
			missing.append({"what": "say whether the surroundings are safe", "hint": "coach.tell_if_safe"})
		"response":
			if hands and interaction.shoulder_check.evidence_recent(): done.append("tapped the shoulders")
			else: missing.append({"what": "tap the person firmly on both shoulders", "hint": "error.shoulders_not_seen"})
			missing.append({"what": "report whether the person responds or not", "hint": "coach.report_response"})
		"call":
			if situation == "A":
				if phone != null and phone.state == "calling": done.append("dialled 112 on the phone in the left hand")
				else: missing.append({"what": "tap the green 112 key on the phone in your left hand (or say: I am calling 112)", "hint": "coach.phone_tap_112"})
				missing.append({"what": "tap Speaker on the phone, so the hands stay free", "hint": "coach.phone_speaker"})
			else:
				if scenario.emergency_called: done.append("asked someone to call 112")
				else: missing.append({"what": "ask one specific person (the woman in the red jacket) to call 112 and put the phone on speaker", "hint": "coach.who_calls_112"})
				if scenario.aed_requested: done.append("asked someone to fetch the AED")
				else: missing.append({"what": "ask one specific person (the man with the blue backpack) to fetch the AED", "hint": ""})
		"breathing":
			if hands and interaction.head_tilt_played: done.append("tilted the head back")
			else: missing.append({"what": "tilt the head back: one hand on the forehead, lift the chin with the other", "hint": "coach.tilt_head"})
			if hands and interaction.face_check.evidence_recent(): done.append("ear at the mouth, looking at the chest")
			else: missing.append({"what": "bring the ear close to the mouth and watch the chest, at most 10 seconds", "hint": "coach.closer_to_mouth"})
			missing.append({"what": "report whether the person is breathing normally", "hint": ""})
		_:
			missing.append({"what": "follow the current instruction", "hint": ""})
	return {"step": step, "done": done, "missing": missing}

func _queue_coach_question(text: String) -> void:
	if _call_connecting(): return
	var actions := _step_actions()
	if actions.step != _help_step:
		_help_step = actions.step
		_help_attempt = 0
	_help_attempt += 1
	var context := NaretTrainingCoach.context(scenario, _language)
	# After the 112 call the dispatcher leads the CPR cycles; she answers the questions too
	# (19 Nov 2026: the instructor repeated what she had just said).
	context["speaker"] = _guide_speaker()
	context["done_actions"] = actions.done
	var missing: Array = []
	for item: Dictionary in actions.missing: missing.append(item.what)
	context["missing_actions"] = missing
	context["help_attempt"] = _help_attempt
	# Offline: the recorded hint for the first missing action (not the step text again).
	for item: Dictionary in actions.missing:
		if not str(item.hint).is_empty():
			context["approved_instruction"] = NaretLanguage.text(str(item.hint), _language)
			break
	print("NARET_HELP step=", actions.step, " attempt=", _help_attempt, " missing=", missing)
	llm.enqueue_transcript(text, context)

## 20 Nov 2026 (user: "check both pads individually ... if both are already correctly
## placed, skip the placement instruction; if one is missing or misplaced, give guidance
## only for that pad"). The pads are looked at one by one before anything is said:
##   both on their outlines     -> nothing is said
##   none on yet                -> how to place them (the general instruction, once)
##   one on, one missing        -> only where the missing one goes
##   a pad let go off its place -> that it is not on the outline, and where it belongs
## Before: one fixed instruction 4 s after "attach the pads" unless both were already on.
const PAD_GUIDANCE_QUIET_MS := 15000 # 8 s until 26 Nov 2026: pad hints came too often
var _pad_guidance_ms := -100000
var _pads_missing_before := -1

func _pad_guidance(why: String) -> void:
	if aed == null or scenario == null or _smoke_mode or not aed.powered or scenario.aed_attached: return
	if scenario.state != NaretScenario.State.CPR and scenario.state != NaretScenario.State.CALL_HELP: return
	var missing: Array[String] = aed.missing_pads()
	if missing.is_empty(): return
	var key := "aed_pads_how"
	if why == "missed":
		# Both pads off the outlines: no extra line (26 Nov 2026); the outlines show it.
		if missing.size() != 1: return
		key = "aed_pad_missed_" + missing[0]
	elif missing.size() == 1: key = "aed_pad_" + missing[0]
	var now := Time.get_ticks_msec()
	if why != "one_left" and now - _pad_guidance_ms < PAD_GUIDANCE_QUIET_MS: return
	_pad_guidance_ms = now
	var text := NaretTrainingCoach.instruction(key, _language)
	print("NARET_AED pad guidance ", key, " missing=", missing)
	_toast(text)
	audio_manager.speak(text, _language, "", "instructor")

## The first pad is on: the instructor says where the other one goes (once).
func _update_pad_guidance() -> void:
	if aed == null or scenario == null or not aed.powered or scenario.aed_attached:
		_pads_missing_before = -1
		return
	var missing := aed.missing_pads().size()
	if _pads_missing_before == 2 and missing == 1: _pad_guidance("one_left")
	_pads_missing_before = missing

## The device's own "attach the pads" takes about this long.
const AED_PADS_HOW_AFTER_S := 4.0
var _last_coach_step := ""
var _coach_waits_for_aed := false
## How often "the scene is not safe" was said in this exercise.
var _unsafe_reports := 0
var _unclassified_spoken_step := ""
func _announce_coach_step() -> void:
	# The instructor's step instructions use approved text and baked clips, so they
	# never depended on the PC dialogue server. The old guard on local_ai_url silenced
	# every instruction in cloud-only setups (headset review 2026-11-03).
	if _smoke_mode or not audio_manager: return
	var key := NaretTrainingCoach.step(scenario)
	if key == "setup":
		_last_coach_step = ""
		_unclassified_spoken_step = ""
		return
	if key == _last_coach_step: return
	# The crew has taken over: only the closing line ("finish") follows.
	if _ems_state == 2 and key != "finish": return
	# "Training has ended" is the instructor's again, like the debrief that follows.
	if key == "finish" and audio_manager: audio_manager.instructor_voice = ""
	# Situation A: while the dispatcher is still answering, the step waits; she gives it
	# herself right after "put the phone on speaker" (_dispatcher_next).
	if key in DISPATCHER_STEPS and _dispatcher_step == 1:
		return
	# The AED's own voice first (14 Nov 2026: "resume compressions" was spoken over
	# "shock advised" and "shock delivered"). Its lines are recorded clips on the
	# device's own speaker, so they are not in the instructor's queue; he waits here.
	if aed and aed.device_voice_pending():
		if not _coach_waits_for_aed:
			_coach_waits_for_aed = true
			get_tree().create_timer(0.3).timeout.connect(func():
				_coach_waits_for_aed = false
				_announce_coach_step())
		return
	# The AED is there and its pads are not on yet: that is the one thing to do now. The
	# 30-compressions and two-breaths prompts stay silent until the pads are on; they
	# used to cut off the AED instructions every time the count passed 30.
	# The same while Marek is on his way in with it: he arrives at the end of the first
	# 30 compressions, and "now two breaths" would be cut off by "the AED is here".
	var arriving: bool = director != null and director.get("presenting") == true
	if (arriving or (scenario.aed_available and not scenario.aed_attached)) and key in ["breaths", "breath_one", "breath_two", "compressions", "compression_only"]:
		return
	# Replies requested during the previous step must not follow its replacement.
	llm.cancel_pending()
	observation_interpreter.cancel_pending()
	if key in ["breaths", "breath_one", "breath_two", "compressions", "compression_only"]:
		audio_manager.stop_speech()
	var previous_step := _last_coach_step
	_last_coach_step = key
	_unclassified_spoken_step = ""
	print("NARET_COACH_STEP ", key, " count=", scenario.cycle_compressions)
	# From "pads on" to the shock the AED's own voice leads; the instructor comes back
	# with "resume compressions". His four prompts in between asked for a spoken
	# "everyone is clear" twice, which the device no longer waits for.
	if key in ["aed_clear", "aed_analyse", "aed_shock_clear", "aed_countdown"]:
		return
	# Critical instructions use approved text. The LLM handles follow-up questions.
	var instruction := NaretTrainingCoach.current_instruction(scenario, _language)
	# Asked for early (before this step): the tasks are taken in a moment (_take_early_call),
	# so the instructor does not ask for what was already said.
	if key == "call" and not scenario.alone:
		if _early_call_request and (_early_aed_request or scenario.cpr_witness_only):
			print("NARET_COACH_STEP call: both tasks were given early, nothing to ask")
			return
		if _early_call_request:
			# 112 was asked for already: only the AED is left (the call step's own sentence).
			instruction = NaretTrainingCoach.instruction("call_aed", _language)
		elif _early_aed_request:
			instruction = NaretTrainingCoach.instruction("call", _language)
	# After the call the dispatcher leads over the speaker (A and B), in her own words: she
	# cannot see the green box, the bag or the stool. Lines she has no wording for (the
	# AED's) stay with the instructor.
	# After the shock (and after "no shock") the AED itself says to start compressions
	# (18 Nov 2026); the instructor's line is only shown, not said again.
	if NaretTrainingCoach.current_key(scenario) in ["aed_resume", "aed_resume_only"]:
		_toast(instruction)
		return
	var dispatcher_key := "dispatcher_" + NaretTrainingCoach.current_key(scenario)
	# Switched to compression-only during CPR (26 Nov 2026): the compression instruction was
	# already given; nothing more is said.
	if key == "compression_only" and previous_step in ["compressions", "breaths"]:
		print("NARET_COACH_STEP compression_only after a switch: silent")
		return
	if _dispatcher_leads() and _has_coach_text(dispatcher_key):
		var dispatcher_text := NaretTrainingCoach.instruction(dispatcher_key, _language)
		_toast(dispatcher_text)
		audio_manager.speak(dispatcher_text, _language, "", "dispatcher")
	else:
		_toast(instruction)
		audio_manager.speak(instruction, _language, "", "instructor")
	# The safety question's subtitles and hints start with the step itself (19 Nov 2026):
	# they used to wait for the voice to start, so a late or failed clip left the trainee
	# with no words at all after "Start training". The voice start resets the hint clock.
	if key == "safety" and not _safety_asked:
		_safety_asked = true
		_safety_asked_ms = Time.get_ticks_msec()
		print("NARET_SAFETY asked: ", instruction)
	if key == "breaths" and bvm:
		bvm.offer()
		if not bvm.is_placed():
			get_tree().create_timer(10.0).timeout.connect(func():
				if not bvm.is_placed() and NaretTrainingCoach.step(scenario) == "breaths" and not audio_manager.is_speaking():
					audio_manager.speak(NaretLanguage.text("coach.bvm_place_mask", _language), _language, "", _guide_speaker()))
	# Repeat guidance only when requested; timed repeats interrupt conversation.

func _on_reply(reply: Dictionary) -> void:
	# Anna has no scripted "calm" line any more: an empty reply means she stays silent.
	if str(reply.get("text", "")).strip_edges().is_empty(): return
	var speaker := str(reply.get("speaker", "bystander"))
	print("NARET_REPLY speaker=", speaker, " source=", reply.get("source", ""), " action=", reply.get("action", ""), " next=", reply.get("next_step", ""), " text=", str(reply.get("text", "")).left(120))
	if speaker in ["instructor", "dispatcher"] and reply.get("next_step", "") != NaretTrainingCoach.step(scenario): return
	if speaker in ["instructor", "dispatcher"] and _repeats_instruction(str(reply.get("text", ""))):
		print("NARET_REPLY dropped: repeats the current instruction")
		return
	if speaker == "bystander" and reply.get("action", "none") in ["calm", "thank"]:
		$Bystanders/Anna.set_emotion("calm")
		# Anna's own reply is not evidence that the learner reassured her.
	_show_reply(str(reply.get("text", "")), str(reply.get("source", "")))
	if speaker in ["instructor", "dispatcher"]: _instructor_subtitles(str(reply.get("text", "")))
	audio_manager.speak(str(reply.get("text", "")), str(reply.get("language", bystander_language())), str(reply.get("clip_key", "")), speaker)

## A generated answer that only says the step's instruction again (what the instructor or the
## dispatcher has just said): 70 % of its words are in that instruction.
func _repeats_instruction(text: String) -> bool:
	var said := _words(text)
	if said.size() < 5: return false
	var step_key := NaretTrainingCoach.current_key(scenario)
	for key in [step_key, "dispatcher_" + step_key]:
		if not _has_coach_text(key): continue
		var given := _words(NaretTrainingCoach.instruction(key, _language))
		var shared := 0
		for word in said:
			if word in given: shared += 1
		if shared >= 0.7 * said.size(): return true
	return false

static func _words(text: String) -> PackedStringArray:
	var clean := ""
	for c in text.to_lower():
		clean += c if (c.unicode_at(0) > 127 or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")) else " "
	return clean.split(" ", false)

## The instructor's answer as subtitles in the line of sight (18 Nov 2026). In the safety and
## response steps it replaces their running subtitles; elsewhere it shows for a while.
func _instructor_subtitles(text: String) -> void:
	if speech_bubble == null or text.is_empty(): return
	match NaretTrainingCoach.step(scenario):
		"safety": _safety_bubble_text = text
		"response": _response_bubble_text = text

func _on_ccbm_status(status: String) -> void:
	print("NARET_CCBM_STATUS ", status)
	_record_speech_status(status)
	var messages := {
		"ccbm_tracking_unavailable": ["Aktivitätserkennung derzeit nicht verfügbar.", "Rozpoznawanie czynności jest chwilowo niedostępne.", "Activity tracking is currently unavailable."],
		"ccbm_unavailable": ["CCBM nicht verbunden. Schritt nicht bestätigt.", "CCBM nie jest połączony. Krok niepotwierdzony.", "CCBM unavailable: step not confirmed."],
		"ccbm_busy_repeat": ["Bitte warten, dann wiederholen.", "Poczekaj, potem powtórz.", "Please wait, then repeat."],
		"ccbm_uncertain_repeat": ["Nicht eindeutig. Bitte wiederholen.", "Niepewne. Powtórz.", "Uncertain observation: please repeat."],
		"ccbm_out_of_order": ["Dieser Schritt ist jetzt nicht verfügbar.", "Ten krok nie jest teraz dostępny.", "That step is not available yet."],
		"ccbm_session_limit": ["Sitzungslimit erreicht.", "Osiągnięto limit sesji.", "Session observation limit reached."],
		"ccbm_accepted": ["Gesprochene Meldung angenommen.", "Przyjęto zgłoszenie głosowe.", "Spoken report accepted."]
	}
	var index := 2 if _language == "en" else (1 if _language == "pl" else 0)
	var message := str(messages.get(status, [status, status, status])[index])
	if status in ["ccbm_out_of_order", "ccbm_uncertain_repeat"]:
		_pending_sequence.clear()
		if _call_connecting():
			print("NARET_CCBM_STATUS not answered: the emergency call is connecting")
			return
		message = NaretTrainingCoach.feedback(scenario, _last_heard_report, status, _language, _dispatcher_leads())
		# Said with the step's own instruction, which has a recorded voice. The longer
		# sentence ("That report does not confirm the current check. ...") had none, and
		# when the cloud voice timed out the instructor's answer was silent (21 Nov 2026).
		var spoken := NaretTrainingCoach.current_instruction(scenario, _language)
		if _dispatcher_leads() and _has_coach_text("dispatcher_" + NaretTrainingCoach.current_key(scenario)):
			spoken = NaretTrainingCoach.instruction("dispatcher_" + NaretTrainingCoach.current_key(scenario), _language)
		# The step line is repeated at most once per step (26 Nov 2026): every further
		# unclear or out-of-order report only updates the text on screen.
		var repeat_step := NaretTrainingCoach.step(scenario)
		if not _smoke_mode and not spoken.is_empty() and _unclassified_spoken_step != repeat_step:
			_unclassified_spoken_step = repeat_step
			audio_manager.speak(spoken, _language, "", _guide_speaker())
	if _language == "en":
		message = "Heard: " + _last_heard_report + "\n" + message + "\nNext: " + _next_spoken_step()
	_toast(message)

func _next_spoken_step() -> String:
	var allowed: Array = scenario.get_available_actions()
	var labels := {"begin_check": "check scene safety", "check_responsiveness": "check responsiveness", "call_emergency": "ask the woman in the red jacket to call 112", "check_breathing": "open airway and check breathing", "ventilation": "perform and report one rescue breath", "compression": "perform compressions"}
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "compression", "ventilation"]:
		if action in allowed: return str(labels[action])
	return "follow the exercise instructions"

func _scripted_speech(key: String) -> void:
	if _smoke_mode: return
	audio_manager.speak("", bystander_language(), key, "bystander")

func _on_recording(active: bool) -> void:
	audio_manager.set_listening(active)
	# Cable-local speech uses the explicit button as the start boundary. Waiting
	# for VAD here can lose the first words of a short report.
	if active and not api.local_asr_url.is_empty() and audio_manager.listening:
		audio_manager.begin_recording()

func _on_hand_compression(depth: float, rate: float, correct: bool) -> void:
	if xr.active and (not anchor.locked or not anchor.calibrated): return
	if not correct: return
	# The manikin's own sensor counts the strokes while it is delivering data; the
	# hand-tracked stroke would count the same compression a second time. Only in the
	# CPR phase: during the AED analysis a hand-tracked compression is the contact that
	# cancels the clearance, and the manikin path does not report that.
	if qcpr and qcpr.manikin_live() and scenario and scenario.state == NaretScenario.State.CPR: return
	_on_action("compression", {"source": "hand_tracking", "measurement_verified": false,
		"evidence_kind": "tracked_hand_motion", "depth_measurement_kind": "hand_excursion",
		"depth_estimate_m": depth, "rate_bpm": rate, "correct_position": correct})

func _toggle_qcpr_panel() -> void:
	if qcpr_debug_panel:
		qcpr_debug_panel.visible = not qcpr_debug_panel.visible

func _on_qcpr_compression(depth_mm: float, rate_bpm: float, recoil_ok: bool, quality: Dictionary) -> void:
	mannequin.compress(depth_mm / 1000.0)
	# The measured depth replaces the hand-tracking estimate for the coach and the debrief.
	if interaction != null and interaction._zone != null and interaction._zone.motion_session != null:
		var session = interaction._zone.motion_session
		session.last_stroke_travel_m = depth_mm / 1000.0
		session.last_stroke_quality = str(quality.get("depth_status", session.last_stroke_quality))
	print("NARET_QCPR compression depth_mm=%.0f rate_bpm=%.0f recoil_ok=%s" % [depth_mm, rate_bpm, recoil_ok])
	if dashboard:
		dashboard.show_qcpr_compression(depth_mm, rate_bpm, recoil_ok, quality)
	if xr_info:
		xr_info.show_qcpr_compression(depth_mm, rate_bpm, recoil_ok, quality)

func _on_qcpr_quality_feedback(_type: String, msg_de: String, msg_pl: String, is_good: bool) -> void:
	var text := msg_de if _language == "de" else msg_pl
	if not is_good:
		_toast(text)

func _on_xr_action(action: String) -> void:
	match action:
		"patient_contact":
			if scenario.state == NaretScenario.State.AED: scenario.submit_action("patient_contact", {"source": "hand_tracking"})
		_: _on_action(action)

func _on_tracking_status(status: String) -> void:
	_last_tracking_status = status
	print("NARET_TRACKING ", status)
	var text := NaretLanguage.status(status, _language)
	if dashboard: dashboard.set_tracking(text)
	if xr_info: xr_info.set_tracking(text)

func _record_speech_status(status: String) -> void:
	# Retain bounded diagnostics: logcat's native tracking output can overwrite
	# the speech failure before the connected PC has a chance to inspect it.
	var path := "user://speech_diagnostics.jsonl"
	var trace := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if trace:
		if trace.get_length() > 262144:
			trace.close()
			trace = FileAccess.open(path, FileAccess.WRITE)
		if trace:
			trace.seek_end()
			trace.store_line(JSON.stringify({"time_ms": Time.get_ticks_msec(), "unix_time_s": Time.get_unix_time_from_system(), "status": status,
				"selected_language": _language, "mode": _mode, "bystander_language": bystander_language(),
				"microphone_language": audio_manager.language if audio_manager else "",
				"recording_language": audio_manager.recording_language if audio_manager else "",
				"recognition_language": audio_manager.recognition_language if audio_manager else "",
				"step": NaretTrainingCoach.step(scenario) if scenario else "setup",
				"heard": _last_heard_report, "focused": audio_manager._input_focused if audio_manager else false,
				"listening": audio_manager.listening if audio_manager else false,
				"recording": audio_manager.recording if audio_manager else false,
				"playing": audio_manager._playing if audio_manager else false,
				"preparing": audio_manager._preparing if audio_manager else false,
				"recognising": audio_manager._transcribing if audio_manager else false}))
			trace.close()

## The trainee's plate on the palm shows "…" while their words are being recognised.
func _speech_progress(status: String) -> void:
	if hand_menu == null or scenario == null or scenario.state in [NaretScenario.State.IDLE]: return
	var names: Dictionary = DIALOGUE_NAMES.get("trainee", {})
	var who := str(names.get(_language, names.get("en", "You")))
	if status == "transcribing": hand_menu.set_own_pending(who, true)
	elif status in ["microphone_silent", "speech_not_understood", "speech_recognition_timeout", "speech_connection_failed", "speech_server_error", "speech_request_busy", "asr_offline_use_text", "recording_empty"]:
		hand_menu.set_own_pending(who, false)

func _on_service_status(status: String) -> void:
	_speech_progress(status)
	print("NARET_SPEECH_STATUS ", status)
	if _pc_bench: _pc_note("Status: " + status)
	_last_service_status = status
	_record_speech_status(status)
	var text := NaretLanguage.status(status, _language)
	if dashboard: dashboard.set_status(text)
	if xr_info: xr_info.set_status(text)
	if hand_menu: hand_menu.show_notice(text)
	# Spoken every time, not once per step: a trainee whose microphone delivers silence must
	# hear that the app is still listening (2026-11-05: three silent attempts felt like a freeze).
	if status in ["microphone_silent", "speech_not_understood"] and audio_manager and not _smoke_mode:
		# First the reason ("I cannot hear you"), then the step's own yes/no question, so the
		# trainee knows both what happened and what one word gets them on (11 Nov 2026).
		audio_manager.speak(text, _language, "", _guide_speaker())
		# Safety step, not looked around yet: no "is it safe? yes or no" now (19 Nov 2026: a
		# 1.8 s silent recording asked it before the trainee had checked anything).
		if not (NaretTrainingCoach.step(scenario) == "safety" and not _looked_around()):
			_ask_step_question()

func _show_reply(text: String, source: String = "") -> void:
	if dashboard: dashboard.show_reply(text)
	if xr_info: xr_info.show_reply(text)
	if not source.is_empty(): _on_service_status(source)

## 20 Nov 2026 (user: "no repetition of subtitles in different parts"): a sentence the card
## in the line of sight shows, or is about to show as the running subtitle of the safety or
## response step, is not written on the hand as well. Before, every spoken line went to the
## hand notice too.
func _on_card(text: String) -> bool:
	if text.is_empty() or speech_bubble == null: return false
	return speech_bubble.shown_text() == text

## Who said a line, as named in the palm's dialogue.
const DIALOGUE_NAMES := {
	"instructor": {"de": "Instruktor", "pl": "Instruktor", "en": "Instructor"},
	"dispatcher": {"de": "Leitstelle 112", "pl": "Dyspozytor 112", "en": "Dispatcher 112"},
	"bystander": {"de": "Zeugin", "pl": "Świadek", "en": "Witness"},
	"marek": {"de": "AED-Helfer", "pl": "Pomocnik AED", "en": "AED helper"},
	"aed": {"de": "AED", "pl": "AED", "en": "AED"},
	"ems": {"de": "Rettungsdienst", "pl": "Ratownik", "en": "Ambulance crew"},
	"trainee": {"de": "Du", "pl": "Ty", "en": "You"},
}

## 20 Nov 2026 (user: "use the palm for all dialogue; show my dialogue too"): every line that
## is spoken, and what the app heard the trainee say, goes to the dialogue on the hand menu.
func _dialogue_line(speaker: String, text: String) -> void:
	if text.strip_edges().is_empty(): return
	if speaker == "anna": speaker = "bystander"
	var names: Dictionary = DIALOGUE_NAMES.get(speaker, {})
	var who := str(names.get(_language, names.get("en", speaker.capitalize())))
	if _pc_bench: _pc_note(who + ": " + text.left(150))
	if hand_menu: hand_menu.add_dialogue(who, text, speaker == "trainee")

## A notice on the hand: only what is not spoken (measurements, saving, errors). A line that
## is being said or about to be said is in the dialogue instead, once.
func _toast(text: String) -> void:
	if text.is_empty() or _on_card(text):
		if hand_menu: hand_menu.show_notice("")
		return
	_notice_unless_spoken.call_deferred(text)

func _notice_unless_spoken(text: String) -> void:
	# Deferred: most callers queue the voice line right after this call.
	if audio_manager != null and audio_manager.has_line(text): return
	if _pc_bench: _pc_note("Notice on the hand: " + text.left(120))
	if hand_menu: hand_menu.show_notice(text)
	if dashboard: dashboard.toast(text)
	if xr_info: xr_info.toast(text)

func _export_session() -> void:
	var result := logger.save(_session_summary())
	_toast((NaretLanguage.ui("Exportiert: ", "Zapisano: ", _language)) + result if not result.is_empty() else "Export failed")

func _session_summary() -> Dictionary:
	return {"scenario": scenario.get_summary(), "score": score.get_summary(), "debrief_text": _debrief_text,
		"performance": performance.get_summary() if performance else {}, "api_latencies": _api_latencies,
		"tracking": {"calibrated": anchor.calibrated, "source": "aruco" if tracker and tracker.tracked else "preview"}}

func _open_briefing() -> void:
	if is_instance_valid(_modal): return
	var panel := NaretBriefingPanel.new()
	panel.summary = _session_summary()
	panel.language = _language
	panel.export_requested.connect(_export_session)
	_show_modal(panel)

func _show_modal(panel: Control) -> void:
	_modal = panel
	if _info_surface:
		_info_surface.visible = true
		panel.tree_exited.connect(func(): _info_surface.visible = false)
	if xr.active: _info_viewport.add_child(panel)
	else:
		_ui_layer.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		panel.position = Vector2(330, 115)
		panel.size = Vector2(760, 730)

func _trainer_rosc() -> void:
	if "simulate_rosc" in scenario.get_available_actions():
		_on_action("simulate_rosc", {"trainer": true, "source": "desktop"})
		_toast(NaretLanguage.ui("Trainer: ROSC simuliert", "Instruktor: symulacja ROSC", _language))
	else:
		_toast(NaretLanguage.ui("Trainer-ROSC nach AED und fortgesetzter CPR verfügbar", "ROSC instruktora po AED i wznowieniu RKO", _language))

func _unhandled_input(event: InputEvent) -> void:
	if not scenario or xr.active: return
	if _pc_bench:
		_pc_bench_input(event)
		return
	if is_instance_valid(_modal):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE: _modal.queue_free()
		return
	if dashboard and dashboard.has_text_focus(): return
	if event is InputEventKey and not event.echo:
		if event.physical_keycode == KEY_T: _on_recording(event.pressed)
		if event.pressed:
			match event.physical_keycode:
				KEY_C:
					if qcpr and qcpr.sim_backend and qcpr.sim_backend.control_mode == NaretSimulatedManikinBackend.ControlMode.MANUAL:
						qcpr.trigger_manual_compression(55.0)
					else:
						_on_action("compression")
				KEY_V:
					if qcpr and qcpr.sim_backend and qcpr.sim_backend.control_mode == NaretSimulatedManikinBackend.ControlMode.MANUAL:
						qcpr.trigger_manual_ventilation(500.0)
					else:
						_on_action("ventilation")
				KEY_F2: _toggle_qcpr_panel()
				KEY_F3: mannequin.set_reference_visible(not mannequin.get_node("ScanReference").visible)
				KEY_F8: pass
				KEY_ESCAPE:
					# An open modal already took Escape above.
					if is_instance_valid(qcpr_debug_panel): qcpr_debug_panel.visible = false
	if is_instance_valid(_modal): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: _dragging = event.pressed
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _distance = maxf(1.6, _distance - 0.2)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _distance = minf(6.0, _distance + 0.2)
		_update_camera()
	if event is InputEventMouseMotion and _dragging:
		_rotation -= event.relative.x * 0.007
		_elevation = clampf(_elevation + event.relative.y * 0.005, 0.3, 1.45)
		_update_camera()

## --- PC test bench for the first step (20 Nov 2026) ---------------------------------------
## User: "let's test Step 1 here: the instructor speaks, I reply by voice, the cloud
## processes my response and replies, so we can make changes before installing on the
## Quest." Started with the user argument --pc-step1 on a PC:
##   godot --path . --xr-mode off -- --pc-step1
## It is the app itself (same scenario, speech recognition, interpreter and voice), seen
## from the trainee's eyes instead of the desktop dashboard: the instructor stands in front
## and greets, Enter presses "Start training", and the PC's microphone is the headset's.
## What a PC cannot do is left out: no hands, no markers, no hand menu. Texts that would go
## to the hand menu are listed in the corner instead. The look to the left and right of
## the safety step is done with the arrow keys or by dragging the mouse.
const PC_EYE := Vector3(0.4, 1.62, 2.6)
var _pc_bench := false
var _pc_yaw := 0.0
var _pc_log: Label
var _pc_lines: Array[String] = []
var _pc_instructor_home: Transform3D

func _pc_bench_setup() -> void:
	_pc_bench = true
	get_window().title = "NaReT Step 1 test (PC)"
	if dashboard: dashboard.visible = false
	desktop_camera.fov = 62.0
	_update_camera()
	# As at the welcome in the headset: the instructor 1.6 m in front, nobody else yet.
	_pc_instructor_home = $Instructor.global_transform
	var spot := Vector3(PC_EYE.x, 0.0, PC_EYE.z - WELCOME_INSTRUCTOR_M)
	$Instructor.place_on_floor(_speaker_floor_pose(spot, PC_EYE))
	$Instructor.visible = true
	$Bystanders/Anna.visible = false
	$Bystanders/Marek.visible = false
	_update_name_tags()
	var help := Label.new()
	help.position = Vector2(16, 10)
	help.add_theme_font_size_override("font_size", 17)
	help.text = "Enter: Start / Restart training     Left / Right arrow or mouse drag: turn your head     Down arrow: look ahead\nSpeak into the microphone when the instructor has finished (hold T to force recording)     D / E / P: language     Esc: close"
	_ui_layer.add_child(help)
	_pc_log = Label.new()
	_pc_log.position = Vector2(16, 70)
	_pc_log.add_theme_font_size_override("font_size", 16)
	_pc_log.add_theme_color_override("font_color", Color(1, 1, 0.75))
	_ui_layer.add_child(_pc_log)
	_pc_note("Cloud: " + ("connected" if api.is_available() else "NOT available (offline)"))
	if "--pc-auto" in OS.get_cmdline_user_args(): _pc_auto()

func _pc_auto() -> void:
	## --pc-auto: plays step 1 by itself with typed answers in place of the microphone, to
	## check the loop (question, answer, interpretation, reply) without a person.
	var wait := func(seconds: float): await get_tree().create_timer(seconds).timeout
	await wait.call(8.0)
	_on_action("start")
	await wait.call(10.0)
	_pc_note("AUTO state=%s step=%s" % [scenario.get_state_name(), NaretTrainingCoach.step(scenario)])
	_on_transcript("Ich schaue zuerst, ob die Umgebung sicher ist.")
	await wait.call(12.0)
	_pc_note("AUTO state=%s looked_around=%s" % [scenario.get_state_name(), _looked_around()])
	for yaw in [-0.7, 0.7, 0.0]:
		_pc_yaw = yaw
		_update_camera()
		await wait.call(1.0)
	_pc_note("AUTO looked_around=%s" % _looked_around())
	await wait.call(1.0)
	_on_transcript("Ja, es ist sicher.")
	await wait.call(12.0)
	_pc_note("AUTO state=%s step=%s" % [scenario.get_state_name(), NaretTrainingCoach.step(scenario)])
	get_tree().quit()

func _pc_note(line: String) -> void:
	if _pc_log == null: return
	print("PC_BENCH ", line)
	_pc_lines.append(line)
	while _pc_lines.size() > 9: _pc_lines.pop_front()
	_pc_log.text = "\n".join(_pc_lines)

func _pc_bench_started() -> void:
	# The training runs: the instructor takes his place beside the patient, the others come.
	$Instructor.global_transform = _pc_instructor_home
	$Instructor.visible = true
	$Bystanders/Anna.visible = situation == "B"
	$Bystanders/Marek.visible = situation == "B"
	_pc_yaw = 0.0
	_update_camera()
	_pc_note("Training started: Situation %s, ventilation %s, language %s" % [situation, setup.answers.get("breaths", "?"), _language])

func _pc_bench_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: _dragging = event.pressed
	if event is InputEventMouseMotion and _dragging:
		_pc_yaw = clampf(_pc_yaw + event.relative.x * 0.004, -1.4, 1.4)
		_update_camera()
	if not (event is InputEventKey) or event.echo: return
	if event.physical_keycode == KEY_T: _on_recording(event.pressed)
	if not event.pressed: return
	match event.physical_keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_ENTER, KEY_KP_ENTER: _on_action("start" if scenario.state == NaretScenario.State.IDLE else "restart")
		KEY_LEFT: _pc_yaw = clampf(_pc_yaw - deg_to_rad(30), -1.4, 1.4)
		KEY_RIGHT: _pc_yaw = clampf(_pc_yaw + deg_to_rad(30), -1.4, 1.4)
		KEY_DOWN, KEY_UP: _pc_yaw = 0.0
		KEY_D: _menu_language("de")
		KEY_E: _menu_language("en")
		KEY_P: _menu_language("pl")
	_update_camera()

func _update_camera() -> void:
	if _pc_bench:
		# The trainee's eyes: standing, looking ahead, the head turned by _pc_yaw.
		desktop_camera.global_transform = Transform3D(Basis(Vector3.UP, -_pc_yaw), PC_EYE)
		return
	var target := Vector3(0.38, 0.08, -0.03)
	desktop_camera.position = target + Vector3(sin(_rotation) * cos(_elevation), sin(_elevation), cos(_rotation) * cos(_elevation)) * _distance
	desktop_camera.look_at(target)

func _build_room() -> void:
	# Training mat and grid are desktop-preview scenery, not passthrough overlays.
	# The mat belongs to SpatialAnchor, so hiding Room alone did not hide it.
	if OS.get_name() == "Android":
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("24404a")
	mat.roughness = 0.95
	var mat_mesh := BoxMesh.new()
	mat_mesh.size = Vector3(0.82, 0.026, 1.95)
	var training_mat := MeshInstance3D.new()
	training_mat.mesh = mat_mesh
	training_mat.material_override = mat
	training_mat.position = Vector3(0, -0.046, 0.22)
	anchor.add_child(training_mat)
	var grid_mesh := ImmediateMesh.new()
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for n in range(-10, 11):
		grid_mesh.surface_add_vertex(Vector3(n * 0.5, -0.009, -5))
		grid_mesh.surface_add_vertex(Vector3(n * 0.5, -0.009, 5))
		grid_mesh.surface_add_vertex(Vector3(-5, -0.009, n * 0.5))
		grid_mesh.surface_add_vertex(Vector3(5, -0.009, n * 0.5))
	grid_mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = grid_mesh
	var grid_mat := StandardMaterial3D.new()
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.albedo_color = Color("1d3039")
	grid.material_override = grid_mat
	$Room.add_child(grid)

func _smoke_test() -> void:
	await get_tree().process_frame
	for mode: String in ["own", "neighbour"]:
		for language: String in ["de", "pl", "en"]:
			_set_mode(mode)
			_set_language(language)
			var expected: String = language if mode == "own" or language == "en" else ("pl" if language == "de" else "de")
			if bystander_language() != expected or audio_manager.language != language:
				push_error("Anna must follow training mode; recognition must follow the trainee language")
				get_tree().quit(1)
				return
			await _smoke_run()
	print("NARET_SMOKE_PASS DE+PL+EN, own/neighbour mode, scene wiring, ECG, export")
	audio_manager.stop_speech()
	get_tree().create_timer(0.1).timeout.connect(get_tree().quit)


func _smoke_run() -> void:
	_on_action("start")
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
		_on_action(action)
	for i in 30: _on_action("compression")
	_on_action("ventilation")
	_on_action("ventilation")
	_on_action("handover")
	if scenario.state != NaretScenario.State.RECOVERY:
		push_error("Main scene BLS smoke failed")
		get_tree().quit(1)
		return
	await get_tree().process_frame
