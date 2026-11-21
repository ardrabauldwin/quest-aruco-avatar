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
			get_tree().create_timer(AED_PADS_HOW_AFTER_S).timeout.connect(func():
				if aed.powered and not aed.pads_ready() and scenario.state == NaretScenario.State.CPR:
					var how := NaretTrainingCoach.instruction("aed_pads_how", _language)
					_toast(how)
					audio_manager.speak(how, _language, "", "instructor")))
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
	# One short sentence when the AED is there, and the pads only after it is switched
	# on (see aed.spoke below). The former text explained power, both pads, the outlines
	# and the whole shock pattern in one 40 s speech that every CPR prompt cut off.
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
	director.speak = func(key: String, text: String, lang: String, speaker: String):
		if not _smoke_mode: audio_manager.speak(text, lang, key, speaker)
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
		if hand_menu: hand_menu.show_notice("Playing " + _lang.to_upper() + " audio")
		$Bystanders/Anna.speaking = speaker in ["bystander", "anna"]
		$Instructor.speaking = speaker == "instructor"
		$Bystanders/Marek.speaking = speaker == "marek"
		_record_speech_status("voice_started_" + speaker)
		if speaker in ["bystander", "anna"]: _show_reply(text, source)
		else: _toast(text))
	audio_manager.playback_changed.connect(func(active: bool):
		if interaction: interaction.set_audio_busy(active or audio_manager.recording)
		if not active:
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
	# Explicit witness questions are already routed to Anna in _on_transcript.
	# An unclear exercise report needs the instructor, not unrelated witness chat.
	observation_interpreter.conversation.connect(func(_text: String):
		# A question to the exercise ("can't I call 112 myself?") gets an answer from the
		# instructor, who explains the approved step; repeating the step text did not answer
		# it (headset, 2026-11-04). Other unclassified audio only repeats the step.
		if observation_interpreter.last_kind == "question" and not _smoke_mode:
			_queue_coach_question(_text)
			return
		# Help and witness questions were routed explicitly before classification.
		# Unclassified audio must not provoke generated clinical instructions.
		var step := NaretTrainingCoach.step(scenario)
		var guidance := NaretTrainingCoach.instruction(step, _language)
		_toast(guidance)
		# The patient-side text panel is removed. Give audible feedback once per
		# step so an unrelated recognition cannot leave the learner in silence.
		if not _smoke_mode and _unclassified_spoken_step != step:
			_unclassified_spoken_step = step
			audio_manager.speak(guidance, _language, "", "instructor"))
	observation_interpreter.clarification.connect(func(text: String):
		# A clear report with another finding ("he is breathing normally") is not a doubt: the
		# instructor answers it from the deviation guide instead of "no step confirmed".
		if not observation_interpreter.last_doubtful and not _last_heard_report.is_empty() and not _smoke_mode:
			_queue_coach_question(_last_heard_report)
			return
		if observation_interpreter.last_doubtful and not _smoke_mode:
			# The cloud could not tell either: say so, then ask the step's yes/no question.
			var heard := NaretLanguage.status("speech_not_understood", _language)
			_toast(heard)
			audio_manager.speak(heard, _language, "", "instructor")
			if _ask_step_question():
				return
		if not api.local_ai_url.is_empty():
			text = NaretTrainingCoach.feedback(scenario, _last_heard_report, "unclear", _language)
		_toast(text)
		if not _smoke_mode:
			var clip := "speech_repeat" if bystander_language() == "en" else ""
			audio_manager.speak(text, bystander_language(), clip, "instructor"))
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
					audio_manager.speak(NaretLanguage.text("coach.bvm_squeeze", _language), _language, "", "instructor")))
	interaction.action_requested.connect(_on_xr_action)
	interaction.compression_measured.connect(_on_hand_compression)
	interaction.head_tilt_gesture_detected.connect(func():
		_toast("Head-tilt gesture detected — technique unverified"))
	# Shoulders touched but no report within 10 s: ask the step's yes/no question.
	interaction.shoulders_touched.connect(func(_shaken: bool):
		get_tree().create_timer(10.0).timeout.connect(func():
			if scenario and scenario.state == NaretScenario.State.CHECK_PATIENT and not scenario.responsiveness_checked \
					and audio_manager and not audio_manager.is_speaking() and not audio_manager.recording:
				_ask_step_question()))
	# Face at the patient but no breathing report within 10 s: the step's yes/no question.
	interaction.face_checked.connect(func():
		get_tree().create_timer(10.0).timeout.connect(func():
			if scenario and scenario.state == NaretScenario.State.CALL_HELP and scenario.emergency_called \
					and not scenario.breathing_checked and audio_manager and not audio_manager.is_speaking() and not audio_manager.recording:
				_ask_step_question()))
	# The spoken "place your hands correctly ... on the yellow box" for a press beside the
	# box is gone (14 Nov 2026, "after placing and doing compressions the instructor says
	# place correctly, heels on yellow; remove it"). It came after the hands had been
	# placed right: one press measured beside the box, which the tracked hands' wobble
	# produces, was enough. The box itself still shows where the hands belong.
	# ERC 2025: no more than 10 s at the face. Spoken, because the trainee's head is down.
	interaction.face_check_long.connect(func():
		if audio_manager and not _smoke_mode:
			audio_manager.speak(NaretLanguage.text("coach.check_time", _language), _language, "", "instructor"))
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
		$Instructor.visible = false
		$Bystanders/Marek.visible = false
		return
	if default_character_placement:
		_place_default_characters()
	else:
		_place_speakers_strict()

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

const MAREK_SHIRT := Color(0.16, 0.27, 0.45) # denim blue; the instructor keeps olive
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
	return maxf(surface, floor_y + STOOL_MIN_HEIGHT_M) + 0.01

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
	if _stool and _stool.visible:
		found.append({"point": Vector2(_stool.global_position.x, _stool.global_position.z), "radius": 0.40})
	# The patient, as a row of circles from crown to feet: nobody walks across him either.
	if mannequin and mannequin.is_visible_in_tree():
		var body := mannequin.get_body_transform().orthonormalized()
		var along := -PATIENT_TO_CROWN_M + 0.25
		while along <= PATIENT_TO_FEET_M - 0.20:
			var at := body * Vector3(0.0, 0.0, along)
			found.append({"point": Vector2(at.x, at.z), "radius": 0.28})
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
	_stool.visible = mannequin.is_visible_in_tree()
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
	$Instructor.visible = false
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

## The instructor sends Marek for the AED during the first compressions (16 Nov 2026:
## "the instructor must say 'Marek, please bring the AED', then Marek replies; this
## should happen while I give CPR, so it is not the trainee saying it"). After
## MAREK_SEND_AFTER compressions, when nobody is speaking, the instructor says the line
## to Marek; when it has been said, Marek is sent (request_aed), and he answers "I will
## get the defibrillator" and goes. A trainee who asked him already is not overruled.
## 2 since the same day ("after 2 presses let him say it"; it was 5).
const MAREK_SEND_AFTER := 2
var _marek_send_state := 0 # 0 not yet, 1 the instructor is saying it, 2 done
var _marek_send_ms := 0

func _send_marek_for_aed() -> void:
	if scenario == null or audio_manager == null or _smoke_mode or scenario.cpr_witness_only: return
	if scenario.aed_requested:
		_marek_send_state = 2
		return
	if _marek_send_state == 0:
		if scenario.state != NaretScenario.State.CPR: return
		if scenario.cycles == 0 and scenario.cycle_compressions < MAREK_SEND_AFTER: return
		if audio_manager.recording: return
		if audio_manager.is_speaking():
			# The trainee is already pressing: the rest of the instructor's own compressions
			# instruction is not needed, and is cut for the line to Marek. Anything else
			# being said (Anna, Marek, another instruction) is let finish.
			var pressing_prompt := NaretTrainingCoach.current_instruction(scenario, _language)
			if audio_manager.current_text != pressing_prompt or audio_manager._pending.size() > 0: return
			audio_manager.stop_speech()
			print("NARET_COACH compressions_prompt_cut_for_marek")
		var line := NaretLanguage.text("coach.send_marek_aed", _language)
		_toast(line)
		audio_manager.speak(line, _language, "", "instructor")
		print("NARET_COACH send_marek_aed")
		_marek_send_state = 1
		_marek_send_ms = Time.get_ticks_msec()
	elif _marek_send_state == 1:
		# His answer comes after the instructor's line, not into it.
		if audio_manager.is_speaking() or Time.get_ticks_msec() - _marek_send_ms < 600: return
		_marek_send_state = 2
		if "request_aed" in scenario.get_available_actions():
			_on_action("request_aed", {"source": "instructor"})

func _process(delta: float) -> void:
	# Frame-time foot transitions must stop even when no new camera pose arrives.
	_refresh_marker_evidence()
	_send_marek_for_aed()
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
		_marek_send_state = 0
		if bvm: bvm.reset()
	if str(details.get("source", "")) == "speech" and action in ["attach_aed", "analyze_rhythm", "shock", "reassess", "resume_cpr"]: return
	if action == "attach_aed" and aed and aed.manual_pad_placement_required and not aed.pads_ready():
		_toast(NaretTrainingCoach.instruction("aed_apply", _language))
		return
	if action in ["clear_patient", "analyze_rhythm", "shock"] and interaction and interaction._patient_contact_detected():
		scenario.submit_action("patient_contact", {"source": "hand_tracking"})
		return
	if action in ["start", "restart", "reset"]:
		_speech_confirmation.clear()
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
		if xr.active and not anchor.locked:
			_pending_training_action = action
			_toast(NaretLanguage.text("notice.waiting_placement", _language))
			return
		if xr.active and not anchor.calibrated:
			_toast("Save the patient alignment before starting training.")
			return
		_clear_training_session()
		# A previous microphone toggle must not silently disable the new exercise.
		audio_manager.set_listening(true)
		scenario.start()
		_show_reply(_opening_line())
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
	if action == "check_responsiveness" and _shoulder_gate_active():
		# Hand tracking is on: the report counts only with a palm at the shoulders (12 Nov 2026).
		details = details.duplicate()
		details["shoulders_seen"] = interaction.shoulder_check.evidence_recent()
		print("NARET_SHOULDERS gate seen=", details["shoulders_seen"], " shaken=", interaction.shoulder_check.shaken())
	if action == "ventilation" and str(details.get("source", "")) == "speech" and _bvm_gate_active():
		# The breaths are proven by the bag: a counted squeeze already went in, so a sentence
		# after it would double-count, and a sentence without it is refused (once per pair).
		if bvm.breaths_recent() == 0 and Time.get_ticks_msec() - _breath_refusal_ms > 5000:
			_breath_refusal_ms = Time.get_ticks_msec()
			print("NARET_BVM spoken breaths refused")
			_toast(NaretLanguage.text("error.breaths_not_seen", _language))
			if audio_manager and not _smoke_mode:
				audio_manager.speak(NaretLanguage.text("error.breaths_not_seen", _language), _language, "", "instructor")
		return
	if action == "check_breathing" and _face_gate_active():
		# The headset was at the face for 3 s, or the report is refused (12 Nov 2026).
		details = details.duplicate()
		# The head tilt is what counts, and all that counts (13 Nov 2026, "only the tilt
		# is needed"): his head tilted back by the trainee's hands in this step. The head
		# at his face (NaretFaceCheck) is still measured and logged, and still gives the
		# 10 s hint, but no longer decides: with the tilt alone the report used to be
		# refused with "I did not see you check his breathing ... look at his chest".
		details["face_seen"] = interaction.head_tilt_played
		print("NARET_FACE gate seen=", details["face_seen"], " head_tilt_played=", interaction.head_tilt_played)
	if scenario.submit_action(action, details):
		match action:
			"call_emergency":
				pass # Anna's acknowledgement is queued by _on_event before the next task.
			"check_responsiveness":
				if details.has("shoulders_seen") and not interaction.shoulder_check.shaken():
					_toast(NaretLanguage.text("coach.shake_firmly", _language))
			"check_breathing":
				# Airway hint: only whether the avatar's head-tilt animation played in this step.
				if details.has("face_seen") and not interaction.head_tilt_played:
					# Spoken after the compressions instruction, which is a baked clip and is
					# already playing when this runs; the hint queues behind it. The step passed.
					_toast(NaretLanguage.text("coach.open_airway_hint", _language))
					if audio_manager and not _smoke_mode:
						audio_manager.speak(NaretLanguage.text("coach.open_airway_hint", _language), _language, "", "instructor")
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
				_scripted_speech("calm")
			"shock":
				aed.shock()
				_toast(NaretLanguage.ui("Schock simuliert · Sofort CPR fortsetzen", "Symulowane wyładowanie · Wznów RKO", _language))
	else:
		_toast(NaretLanguage.text(scenario.last_error, _language))
		if scenario.last_error in ["error.shoulders_not_seen", "error.breathing_not_seen"] and audio_manager and not _smoke_mode:
			# Spoken, not only shown: the trainee is looking at the patient, not at a panel.
			_speech_confirmation.clear()
			audio_manager.speak(NaretLanguage.text(scenario.last_error, _language), _language, "", "instructor")

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
	_phone_ring.play()

const NaretTrainingCoach = preload("res://scripts/ai/training_coach.gd")

func _continue_sequence() -> void:
	while not _pending_sequence.is_empty():
		var next_action: String = _pending_sequence.pop_front()
		if next_action in scenario.get_available_actions():
			print("NARET_SEQUENCE next=", next_action)
			ccbm.observe_action(next_action)
			return

func _on_event(event: Dictionary) -> void:
	if ccbm: ccbm.observe_accepted(event)
	if event.get("accepted", false) and not _pending_sequence.is_empty():
		_continue_sequence()
	score.record(event)
	logger.record(event)
	if event.get("accepted", false) and event.get("action", "") == "call_emergency" and not _smoke_mode:
		# Headset review 2026-11-03: with cloud TTS on a 2 s deadline this line often failed
		# to synthesise and Anna stayed silent. The baked "help" clip ("I am calling the
		# emergency services on 112") is the fallback when the synthesis does not arrive.
		audio_manager.speak(NaretLanguage.text("anna.calling_112", bystander_language()), bystander_language(), "help", "bystander")
		# Her phone: keypad tones and ringback from her position, a moment after she starts
		# speaking. Tied to the event, not to the spoken text, so the baked fallback clip
		# (different wording) rings too.
		get_tree().create_timer(1.5).timeout.connect(_play_phone_ring)
	if event.get("accepted", false) and event.get("action", "") in ["shock", "resume_cpr"]:
		_last_coach_step = "" # Always announce the fresh set after either AED outcome.
		_last_compression_ms = 0 # Do not turn the AED pause into a CPR rate interval.
	if event.get("accepted", false): _announce_coach_step()
	# Contact during the analysis can come from Anna, not only from the trainee's hands.
	if event.get("action") == "patient_contact" and not event.get("accepted", true):
		_toast(NaretLanguage.text(str(event.get("reason", "")), _language))

func _on_state_changed(state: int) -> void:
	if observation_interpreter: observation_interpreter.cancel_pending()
	if interaction: interaction.set_cpr_enabled(state == NaretScenario.State.CPR)
	if interaction: interaction.set_aed_active(state == NaretScenario.State.AED)
	if interaction: interaction.set_shoulder_check(state in [NaretScenario.State.INTRO, NaretScenario.State.CHECK_PATIENT])
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


func _set_language(language: String) -> void:
	_language = language
	scenario.language = language
	_apply_language()


## Choices made on the hand menu. Two touches within MENU_CHOICE_GAP_MS are one touch
## (headset logs 13 Nov 2026: English, German and English again within a second, from
## one reach for the key), and the choice is kept for the next start of the app, which
## used to begin in German every time.
const MENU_CHOICE_GAP_MS := 1200
const LANGUAGE_FILE := "user://language_choice.cfg"
var _menu_choice_ms := -100000

func _menu_language(language: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _menu_choice_ms < MENU_CHOICE_GAP_MS: return
	_menu_choice_ms = now
	_set_language(language)
	_save_language_choice()

func _menu_mode(mode: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _menu_choice_ms < MENU_CHOICE_GAP_MS: return
	_menu_choice_ms = now
	_set_mode(mode)
	_save_language_choice()

func _save_language_choice() -> void:
	if _smoke_mode: return
	var file := ConfigFile.new()
	file.set_value("language", "selected", _language)
	file.set_value("language", "mode", _mode)
	file.save(LANGUAGE_FILE)

func _load_language_choice() -> void:
	if _smoke_mode: return
	var file := ConfigFile.new()
	if file.load(LANGUAGE_FILE) != OK: return
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
	"Anna": {"name": {"en": "Anna", "de": "Anna", "pl": "Anna"}, "role": {}},
	"Instructor": {"name": {"en": "Instructor", "de": "Instruktor", "pl": "Instruktor"}, "role": {}},
	"Marek": {"name": {"en": "Marek", "de": "Marek", "pl": "Marek"}, "role": {"en": "AED Assistant", "de": "AED-Assistent", "pl": "Asystent AED"}},
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
	_toast("")
	_on_tracking_status(_last_tracking_status)
	_on_service_status(_last_service_status)
	_show_reply(_opening_line())
	# A language switch deliberately stops the old language. Reissue the active
	# instruction in the new language, instead of leaving its dedup flag set.
	_last_coach_step = ""
	_unclassified_spoken_step = ""
	if scenario != null and scenario.state != NaretScenario.State.IDLE:
		if scenario.state == NaretScenario.State.INTRO and director != null:
			director._say("anna_arrive", 0.0)
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
	# A newer utterance supersedes an outstanding model interpretation/repair.
	if observation_interpreter: observation_interpreter.cancel_pending()
	if preload("res://scripts/scenario/spoken_observation.gd").reports_breath_pair(text):
		_last_heard_report = text.left(100)
		_record_speech_status("heard")
		print("NARET_TRANSCRIPT ", text.left(160))
		_speech_confirmation.clear()
		ccbm.observe_breath_pair()
		return
	# Both helpers in one sentence: Marek is sent at once (he answers first), and the rest
	# of the sentence goes on as the call to Anna.
	const Spoken = preload("res://scripts/scenario/spoken_observation.gd")
	if Spoken.mentions_aed_fetch(text) and Spoken.mentions_emergency_call(text):
		print("NARET_TRANSCRIPT both helpers: ", text.left(160))
		if "request_aed" in scenario.get_available_actions():
			_on_action("request_aed", {"source": "speech"})
		# The call is taken from this sentence directly. Left to the general reading,
		# "Anna, please call 112 and Marek, could you bring the AED?" came back as
		# "uncertain" and the trainee had to say the call again (headset 14 Nov 2026;
		# Marek had already been sent from the hand menu, so the sentence was not even
		# recognised as the double request).
		if "call_emergency" in scenario.get_available_actions():
			_speech_confirmation.clear()
			ccbm.observe_action("call_emergency")
			return
		text = Spoken.without_aed_clause(text)
		if text.strip_edges().is_empty(): return
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
	_toast("Heard: " + text.left(160))
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
		if safety == "safe":
			print("NARET_SAFETY safe")
			_speech_confirmation.clear()
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
			_toast(answer)
			_show_reply(answer)
			if audio_manager and not _smoke_mode:
				audio_manager.speak(answer, _language, "", "instructor")
			if _unsafe_reports >= 2:
				ccbm.observe_action("begin_check")
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
			_speak_question(question)
			return
		if interpreted.has("message"):
			_toast(str(interpreted.message))
			audio_manager.speak(str(interpreted.message), _language, "", "instructor")
			return
	# Progression observations go to CCBM, never to Anna's generated action field.
	if ccbm and ccbm.observe_speech(text): return
	observation_interpreter.interpret(text, bystander_language(), _confirmation_context())

func _confirmation_context() -> String:
	return str(scenario.state) + ":" + str(scenario.get_available_actions()) + ":" + str(scenario.cycle_compressions) + ":" + str(scenario.cycle_ventilations)


## When nothing usable was heard (silence, empty transcript, cloud doubt), ask about the step
## the trainee is on as the yes/no question the confirmation path accepts (11 Nov 2026).
## "Did you report that he is not breathing normally?" is answered with one word; "please say
## it again" looped on the headset (9 Nov). Steps without a spoken report keep the old prompt.
func _ask_step_question() -> bool:
	if scenario == null or _smoke_mode or audio_manager == null: return false
	var pick: Dictionary = NaretTrainingCoach.step_question(NaretTrainingCoach.step(scenario))
	if pick.is_empty() or str(pick.action) not in scenario.get_available_actions(): return false
	_speech_confirmation.propose(str(pick.action), _confirmation_context(), Time.get_ticks_msec(), _language, int(pick.breaths))
	var question := preload("res://scripts/ai/speech_pipeline.gd").Confirmation.question(str(pick.action), int(pick.breaths), _language)
	_toast(question)
	_speak_question(question)
	return true

## The same yes/no question is not spoken again within this time. It has three
## independent triggers (an unclear sentence, a touch without a report after 10 s, a
## silent recording), and in the headset on 14 Nov 2026 they fired one after the other:
## "Did you report that he is not responding?" three times in a row. It stays open for a
## "yes" and stays on the display; it is just not said again so soon.
const QUESTION_QUIET_MS := 25000
var _question_said := ""
var _question_said_ms := -100000

func _speak_question(question: String) -> void:
	var now := Time.get_ticks_msec()
	if question == _question_said and now - _question_said_ms < QUESTION_QUIET_MS:
		print("NARET_QUESTION not repeated (asked %.0f s ago)" % ((now - _question_said_ms) / 1000.0))
		return
	_question_said = question
	_question_said_ms = now
	audio_manager.speak(question, _language, "", "instructor")

func _on_conversation(text: String) -> void:
	if NaretTrainingCoach.asks_for_help(text):
		_queue_coach_question(text)
		return
	var context := NaretTrainingCoach.context(scenario, bystander_language())
	context["speaker"] = "bystander"
	context["bystander_state"] = $Bystanders/Anna.emotion
	llm.enqueue_transcript(text, context)

func _queue_coach_question(text: String) -> void:
	var context := NaretTrainingCoach.context(scenario, _language)
	context["speaker"] = "instructor"
	llm.enqueue_transcript(text, context)

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
	_toast(instruction)
	audio_manager.speak(instruction, _language, "", "instructor")
	if key == "breaths" and bvm:
		bvm.offer()
		if not bvm.is_placed():
			get_tree().create_timer(10.0).timeout.connect(func():
				if not bvm.is_placed() and NaretTrainingCoach.step(scenario) == "breaths" and not audio_manager.is_speaking():
					audio_manager.speak(NaretLanguage.text("coach.bvm_place_mask", _language), _language, "", "instructor"))
	# Repeat guidance only when requested; timed repeats interrupt conversation.

func _on_reply(reply: Dictionary) -> void:
	var speaker := str(reply.get("speaker", "bystander"))
	print("NARET_REPLY speaker=", speaker, " source=", reply.get("source", ""), " action=", reply.get("action", ""), " next=", reply.get("next_step", ""), " text=", str(reply.get("text", "")).left(120))
	if speaker == "instructor" and reply.get("next_step", "") != NaretTrainingCoach.step(scenario): return
	if speaker == "bystander" and reply.get("action", "none") in ["calm", "thank"]:
		$Bystanders/Anna.set_emotion("calm")
		# Anna's own reply is not evidence that the learner reassured her.
	_show_reply(str(reply.get("text", "")), str(reply.get("source", "")))
	audio_manager.speak(str(reply.get("text", "")), str(reply.get("language", bystander_language())), str(reply.get("clip_key", "")), speaker)

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
		message = NaretTrainingCoach.feedback(scenario, _last_heard_report, status, _language)
		if not _smoke_mode: audio_manager.speak(message, _language, "", "instructor")
	if _language == "en":
		message = "Heard: " + _last_heard_report + "\n" + message + "\nNext: " + _next_spoken_step()
	_toast(message)

func _next_spoken_step() -> String:
	var allowed: Array = scenario.get_available_actions()
	var labels := {"begin_check": "check scene safety", "check_responsiveness": "check responsiveness", "call_emergency": "ask Anna to call 112", "check_breathing": "open airway and check breathing", "ventilation": "perform and report one rescue breath", "compression": "perform compressions"}
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

func _on_service_status(status: String) -> void:
	print("NARET_SPEECH_STATUS ", status)
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
		audio_manager.speak(text, _language, "", "instructor")
		_ask_step_question()

func _show_reply(text: String, source: String = "") -> void:
	if dashboard: dashboard.show_reply(text)
	if xr_info: xr_info.show_reply(text)
	if not source.is_empty(): _on_service_status(source)

func _toast(text: String) -> void:
	if hand_menu: hand_menu.show_notice(text)
	if dashboard: dashboard.toast(text)
	if xr_info: xr_info.toast(text)

func _export_session() -> void:
	var result := logger.save(_session_summary())
	_toast((NaretLanguage.ui("Exportiert: ", "Zapisano: ", _language)) + result if not result.is_empty() else "Export failed")

func _session_summary() -> Dictionary:
	return {"scenario": scenario.get_summary(), "score": score.get_summary(),
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

func _update_camera() -> void:
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
