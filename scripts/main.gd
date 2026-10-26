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
var _speech_confirmation := preload("res://scripts/scenario/speech_confirmation.gd").new()
var _last_heard_report := ""
var _smoke_mode := false
const EN_STATUS := {
  "room_scan_ready": "Room scan ready: placing the witness",
  "room_scan_waiting": "Looking for room scan...",
  "room_scan_missing": "No room scan: configure your room",
  "room_scan_unsupported": "Room scan unavailable: using default placement",
  "desktop_preview": "Desktop preview: no marker tracking",
  "marker_tracked": "ArUco: marker detected",
  "marker_lost_pose_held": "Marker lost: holding placement",
  "scanning_marker": "Looking for markers...",
  "tracking_standby": "Waiting for markers in view",
  "native_backend_missing": "ArUco library missing",
  "online": "University cloud connected",
  "offline": "Offline: local audio",
  "local_asr_ready": "PC speech recognition configured — USB required",
  "recording": "Recording microphone",
  "transcribing": "Recognising speech...",
  "speech_recognition_timeout": "Recognition took too long. Please try a shorter utterance.",
  "speech_not_understood": "No speech understood. Please try again.",
  "transcribed": "Speech recognised",
  "cloud": "Reply from university cloud",
  "local": "Reply and voice from local PC",
  "scripted_fallback": "Scripted dialogue",
  "offline_clip": "Local speech audio",
  "tts_offline_clip": "Local speech audio",
  "asr_offline_use_text": "Speech recognition unavailable: use buttons or text",
  "microphone_paused": "Microphone paused: close the Quest menu and return to training",
  "speech_connection_failed": "Speech connection lost: PC/USB connection needed",
  "speech_server_error": "Speech server returned an error",
  "speech_request_busy": "Still processing the previous recording",
  "microphone_permission_required": "Microphone permission needed",
  "recording_empty": "No speech recorded",
  "models_unverified": "Service model list unavailable"
}


func _ready() -> void:
	_smoke_mode = "--smoke-test" in OS.get_cmdline_user_args()
	_build_room()
	xr = NaretOpenXRSetup.new()
	add_child(xr)
	scenario = NaretScenario.new()
	scenario.cpr_witness_only = true
	scenario.observation_driven = true
	add_child(scenario)
	ccbm = preload("res://scripts/scenario/ccbm_bridge.gd").new()
	ccbm.configure(scenario)
	add_child(ccbm)
	ccbm.decision.connect(_on_action)
	ccbm.status_changed.connect(_on_ccbm_status)
	ekg = NaretEKG.new()
	add_child(ekg)
	ekg.set_rhythm(NaretEKG.Rhythm.VF)
	ekg.beat.connect(mannequin.heart.pulse)
	director = load("res://scripts/scenario/single_witness_director.gd").new()
	add_child(director)
	director.configure(scenario, $Bystanders/Anna, null, mannequin, null)
	# The instructor is a speaker, not a second rescuer in the scenario.
	$Instructor.patient = mannequin
	$Instructor.attention = "trainee"
	$Instructor.set_emotion("calm")
	director.language = bystander_language
	director.trainee = func(): return (xr_camera if xr.active else desktop_camera).global_position
	director.speak = func(key: String, text: String, lang: String, speaker: String):
		if not _smoke_mode: audio_manager.speak(text, lang, key, speaker)
	scenario.event_recorded.connect(_on_event)
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
		_record_speech_status("voice_started_" + speaker)
		if speaker in ["bystander", "anna"]: _show_reply(text, source)
		else: _toast(text))
	audio_manager.playback_changed.connect(func(active: bool):
		if interaction: interaction.set_audio_busy(active or audio_manager.recording)
		if not active:
			$Bystanders/Anna.speaking = false
			$Instructor.speaking = false)
	llm = NaretLLMOrchestrator.new()
	llm.single_witness = true
	llm.configure(api)
	add_child(llm)
	llm.reply_ready.connect(_on_reply)
	llm.status_changed.connect(_on_service_status)
	observation_interpreter = preload("res://scripts/ai/observation_interpreter.gd").new()
	observation_interpreter.configure(api)
	add_child(observation_interpreter)
	observation_interpreter.observation_ready.connect(func(action: String): ccbm.observe_action(action))
	# Explicit witness questions are already routed to Anna in _on_transcript.
	# An unclear exercise report needs the instructor, not unrelated witness chat.
	observation_interpreter.conversation.connect(func(_text: String):
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
	interaction.action_requested.connect(_on_xr_action)
	interaction.compression_measured.connect(_on_hand_compression)
	interaction.head_tilt_gesture_detected.connect(func():
		_toast("Head-tilt gesture detected — technique unverified"))
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
		$XROrigin3D/RightHand.button_pressed.connect(_on_alignment_button)
		_build_xr_ui()
		room = NaretRoomLayout.new()
		add_child(room)
		room.layout_ready.connect(_on_room_status)
		room.configure(origin)
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
		for person: NaretBystander in [$Bystanders/Anna, $Instructor]:
			person.cast_floor_shadow(shadow_direction)
		mannequin.cast_floor_shadow(shadow_direction)
	else:
		_update_camera()
	performance = NaretPerformanceMonitor.new()
	add_child(performance)
	performance.updated.connect(func(metrics: Dictionary):
		if dashboard: dashboard.set_performance(metrics))
	_set_language("de")
	_on_state_changed(scenario.state)
	# Voice activation is the default: a trainee doing compressions cannot hold a button.
	if not _smoke_mode: audio_manager.set_listening(true)
	print("NARET_READY platform=%s xr=%s" % [OS.get_name(), xr.active])
	if _smoke_mode: _smoke_test.call_deferred()

func _on_marker_pose(pose: Transform3D) -> void:
	var hands_cover_chest := false
	if interaction != null and interaction._zone != null:
		hands_cover_chest = bool(interaction._zone.get("hand_over_chest"))
	anchor.full_marker_evidence = tracker.has_full_marker_evidence() and not hands_cover_chest
	anchor.update_pose(pose)

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
	hand_menu.language_requested.connect(_set_language)
	hand_menu.mode_requested.connect(_set_mode)
	hand_menu.recording_requested.connect(_on_recording)
	hand_menu.voice_sample_requested.connect(func():
		audio_manager.stop_speech()
		audio_manager.speak("", _language, "anna_arrive", "bystander"))
	hand_menu.export_requested.connect(_export_session)
	hand_menu.floor_calibration_requested.connect(_calibrate_floor)
	hand_menu.alignment_save_requested.connect(_save_alignment)
	hand_menu.reference_scan_toggled.connect(mannequin.set_reference_visible)
	hand_menu.hand_meshes_toggled.connect(xr.set_hands_visible)
	hand_menu.marker_gizmos_toggled.connect(_set_marker_gizmos)
	hand_menu.chest_calibration_requested.connect(_calibrate_chest)
	hand_menu.chest_fit_requested.connect(_set_chest_fit)
	hand_menu.set_chest_fit(anchor.chest_fit)
	hand_menu.sternum_landmark_apply_requested.connect(_apply_sternum_landmark)
	hand_menu.occlusion_requested.connect(_set_occlusion)
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

func _on_room_status(status: String) -> void:
	print("NARET_ROOM %s anchors=%d" % [status, room.anchor_count()])
	var labels := {
		"room_scan_ready": ["Raumscan erkannt · Angehörige werden platziert", "Wykryto skan pomieszczenia · rozmieszczanie świadków"],
		"room_scan_waiting": ["Raumscan wird gesucht …", "Szukanie skanu pomieszczenia …"],
		"room_scan_missing": ["Kein Raumscan · bitte Raum einrichten", "Brak skanu pomieszczenia · skonfiguruj pokój"],
		"room_scan_unsupported": ["Raumscan nicht verfügbar · feste Platzierung", "Skan niedostępny · stałe rozmieszczenie"],
	}
	if labels.has(status):
		_toast((str(EN_STATUS.get(status, status)) if _language == "en" else str(labels[status][0 if _language == "de" else 1])))
	if status == "room_scan_ready":
		_refresh_floor_reference()
		_place_bystanders()

func _refresh_floor_reference() -> void:
	# The room scan is preferred; the original LOCAL_FLOOR provider is the fallback.
	# If neither is valid, keep the last valid reference rather than snapping to 0.
	var height := room.floor_height_world() if room and room.available else NAN
	var source := "room_scan"
	if not is_finite(height):
		height = xr.floor_height_world(origin)
		source = "local_floor"
	if not is_finite(height):
		return
	_floor_source = source
	_floor_source_y = height
	if anchor.floor_touch_source == source:
		height += anchor.floor_touch_offset_m
	if not anchor.floor_locked or not is_equal_approx(anchor.floor_y, height):
		anchor.floor_locked = true
		anchor.floor_y = height
		anchor.refresh()
		_bystanders_placed_at = Vector3(INF, INF, INF)
		print("NARET_FLOOR_SOURCE source=%s world_y=%.3f touch_offset=%.3f reference_y=%.3f play_area=%d" % [source, height, height - _floor_source_y, XRServer.get_reference_frame().origin.y, xr.interface.get_play_area_mode()])

func _calibrate_floor() -> void:
	## Hand-menu key: the next fingertip resting on the floor sets its height.
	if floor_touch == null:
		return
	floor_touch.start(origin, xr_camera)
	hand_menu.set_floor_calibrating(true)
	_toast(NaretLanguage.ui("Zeigefinger auf den Boden legen und still halten", "Połóż palec wskazujący na podłodze i trzymaj nieruchomo", _language))

func _on_floor_measured(floor_y: float) -> void:
	# Stored against the automatic source, so recentring and the next session
	# keep the correction; a different source later ignores it.
	hand_menu.set_floor_calibrating(false)
	var offset := floor_y - _floor_source_y
	if _floor_source.is_empty() or not is_finite(offset) or absf(offset) > 0.3:
		# No headset floor yet (e.g. room scan still loading) or one far off.
		print("NARET_FLOOR_TOUCH rejected source=%s source_y=%.3f touch_y=%.3f offset=%.3f" % [_floor_source if not _floor_source.is_empty() else "none", _floor_source_y, floor_y, offset])
		_toast(NaretLanguage.ui("Boden nicht erkannt · erneut versuchen", "Nie wykryto podłogi · spróbuj ponownie", _language))
		return
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
	var height := surface_y - anchor.floor_y
	if not is_finite(height) or height < 0.05 or height > 0.5:
		_toast(NaretLanguage.ui("Brust nicht erkannt · Hand flach auflegen", "Nie wykryto klatki · połóż płasko dłoń", _language))
		return
	anchor.chest_height_m = height
	anchor.refresh()
	var saved := anchor.save_calibration() == OK
	print("NARET_CHEST height=%.3f fit=%s thickness=%.3f" % [height, anchor.chest_fit, mannequin.thickness])
	_toast(NaretLanguage.ui("Brust: ", "Klatka: ", _language) + "%.1f" % (height * 100.0) + NaretLanguage.ui(" cm über Boden", " cm nad podłogą", _language) + ("" if saved else " (Save failed)"))

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
		return
	if gizmos == null:
		gizmos = load("res://scripts/tracking/marker_gizmos.gd").new()
		gizmos.name = "MarkerGizmos"
		add_child(gizmos)
		gizmos.bind(provider)

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
			var corner := mannequin.global_transform * Vector3(x, 0.0, z)
			minimum = minimum.min(Vector2(corner.x, corner.z))
			maximum = maximum.max(Vector2(corner.x, corner.z))
	return Rect2(minimum, maximum - minimum)

func _place_bystanders() -> void:
	## Bystanders belong on real free floor, never inside the trainee's furniture.
	if xr.active and not anchor.locked:
		return
	var centre := mannequin.global_position
	# Scanned anchors stream in one by one, so a placement made on the first few
	# has not seen the furniture that arrives after it.
	var anchors := room.anchor_count() if room else 0
	var speakers_in_view := true
	if xr.active:
		var forward := -xr_camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		# Preserve standing positions while either speaker is ahead. If both
		# are hidden behind the wearer, recalculate instead of keeping them lost.
		speakers_in_view = false
		for person: Node3D in [$Bystanders/Anna, $Instructor]:
			if person.visible and forward.dot(person.global_position - xr_camera.global_position) > 0.0:
				speakers_in_view = true
	if speakers_in_view and centre.distance_to(_bystanders_placed_at) < 0.4 and anchors == _bystanders_placed_anchors:
		return
	# The scanned room knows nothing about the patient, so the floor they occupy is
	# excluded explicitly; nobody stands where the trainee kneels (the patient's
	# right side) either: they belong across the patient or at the feet, in view.
	var spots: Array[Transform3D] = []
	if room and room.available:
		spots = room.find_spots(centre, 4, [_local_rect([-0.35, 0.35], [-1.05, 1.05]), _local_rect([-1.4, -0.3], [-1.1, 1.1])])
		if anchor.floor_locked:
			# Stand on the reference floor, which includes a fingertip correction.
			for index in spots.size():
				spots[index].origin.y = anchor.floor_y
		if xr.active:
			# Choose among free scanned spots by viewing direction at placement.
			# Once placed, the existing cache holds Anna there as the head moves.
			var view_forward := -xr_camera.global_basis.z
			view_forward.y = 0.0
			view_forward = view_forward.normalized()
			spots.sort_custom(func(a: Transform3D, b: Transform3D):
				return view_forward.dot((a.origin - xr_camera.global_position).normalized()) > view_forward.dot((b.origin - xr_camera.global_position).normalized()))
	if spots.is_empty() and xr.active and not (room and room.available):
		# A scene scan is optional. The play-area polygon can still constrain
		# placement, though it describes the boundary rather than furniture.
		var boundary := PackedVector2Array()
		for point: Vector3 in xr.interface.get_play_area():
			var world := origin.global_transform * (XRServer.get_reference_frame() * point)
			boundary.append(Vector2(world.x, world.z))
		var flat := NaretRoomLayout.pick_spots(boundary, [_local_rect([-0.35, 0.35], [-1.05, 1.05])], Vector2(centre.x, centre.z), 2)
		for point in flat:
			spots.append(_speaker_floor_pose(Vector3(point.x, anchor.floor_y + anchor.manual_floor_correction_m, point.y), centre))
		if flat.is_empty():
			# Missing or too-small play area: retain a patient-relative arrangement.
			# This makes the speakers visible, but cannot promise wall avoidance.
			var forward := -xr_camera.global_basis.z
			forward.y = 0.0
			forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
			var side := forward.cross(Vector3.UP)
			for direction: float in [-1.0, 1.0]:
				var position := centre + forward * 1.2 + side * direction * 0.6
				position.y = anchor.floor_y + anchor.manual_floor_correction_m
				spots.append(_speaker_floor_pose(position, centre))
		print("NARET_ROOM fallback boundary_points=", boundary.size(), " speakers=", spots.size())
	if spots.is_empty():
		if xr.active:
			# Without scanned free space we cannot know where real walls are.
			$Bystanders/Anna.visible = false
			$Instructor.visible = false
		return
	_bystanders_placed_at = centre
	_bystanders_placed_anchors = anchors
	var people: Array[NaretBystander] = [$Bystanders/Anna, $Instructor]
	for index in people.size():
		var person := people[index]
		person.visible = index < spots.size()
		if person.visible:
			person.place_on_floor(spots[index])
	print("NARET_ROOM placed speakers=", mini(spots.size(), people.size()),
		" anna=", $Bystanders/Anna.global_position, " instructor=", $Instructor.global_position,
		" viewer=", xr_camera.global_position, " corrected_floor=", anchor.floor_y + anchor.manual_floor_correction_m)

func _speaker_floor_pose(position: Vector3, centre: Vector3) -> Transform3D:
	var facing := centre - position
	facing.y = 0.0
	if facing.length_squared() < 0.001:
		facing = Vector3.BACK
	return Transform3D(Basis.looking_at(-facing, Vector3.UP), position)

func _process(delta: float) -> void:
	if interaction and scenario:
		var compressing := NaretTrainingCoach.step(scenario) in ["compressions", "compression_only"]
		interaction.set_cpr_feedback_visible(compressing)
		mannequin.heart_on_press = compressing
	if not scenario: return
	if xr.active:
		_refresh_floor_reference()
		_update_controller_alignment(delta)
		# The shadow lies on the measured real floor, even where the body sinks below it.
		if anchor.floor_locked:
			mannequin.set_shadow_floor(anchor.floor_y)
	for person: NaretBystander in [$Bystanders/Anna, $Instructor]:
		if audio_manager and person.speaking:
			person.set_mouth_open(audio_manager.get_speech_amplitude())
	_ui_timer += delta
	if _ui_timer >= 0.1:
		_ui_timer = 0.0
		if dashboard: dashboard.update_session(scenario)
		if hand_menu: hand_menu.update_session(scenario)
		if xr_info: xr_info.update_session(scenario)
	_spot_timer += delta
	if _spot_timer >= 1.0:
		_spot_timer = 0.0
		_place_bystanders()

func _update_controller_alignment(delta: float) -> void:
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

func _on_action(action: String, details: Dictionary = {}) -> void:
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
			var placement_message := {"en": "Waiting for marker placement. Look at the mannequin markers; your saved alignment is retained.", "de": "Warte auf Markerplatzierung. Schauen Sie auf die Marker der Puppe; die gespeicherte Ausrichtung bleibt erhalten.", "pl": "Oczekiwanie na umieszczenie markerów. Spójrz na markery manekina; zapisane ustawienie pozostaje zachowane."}
			_toast(str(placement_message.get(_language, placement_message.en)))
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
	if scenario.submit_action(action, details):
		match action:
			"call_emergency":
				pass # Anna's acknowledgement is queued by _on_event before the next task.
			"compression":
				if str(details.get("source", "desktop")) != "hand_tracking":
					mannequin.compress(float(details.get("depth_estimate_m", 0.045)))
				if dashboard: dashboard.show_compression(float(details.get("rate_bpm", 0)), float(details.get("depth_estimate_m", 0)), str(details.get("source", "desktop")))
				if xr_info: xr_info.show_compression(float(details.get("rate_bpm", 0)), float(details.get("depth_estimate_m", 0)), str(details.get("source", "desktop")))
			"ventilation":
				mannequin.ventilate()
				if scenario.cycle_ventilations == 0 and interaction: interaction.rearm_cpr_cycle()
			"reassure":
				$Bystanders/Anna.set_emotion("calm")
				_scripted_speech("calm")
			"shock":
				aed.shock()
				_toast(NaretLanguage.ui("Schock simuliert · Sofort CPR fortsetzen", "Symulowane wyładowanie · Wznów RKO", _language))
	else:
		_toast(NaretLanguage.text(scenario.last_error, _language))

const NaretTrainingCoach = preload("res://scripts/ai/training_coach.gd")

func _on_event(event: Dictionary) -> void:
	if ccbm: ccbm.observe_accepted(event)
	score.record(event)
	logger.record(event)
	if event.get("accepted", false) and event.get("action", "") == "call_emergency" and not _smoke_mode:
		var replies := {"en": "I'm calling 112 now. I'll put the phone on speaker.", "de": "Ich rufe jetzt 112 an und schalte den Lautsprecher ein.", "pl": "Dzwonię teraz pod 112 i włączam głośnik."}
		audio_manager.speak(str(replies[bystander_language()]), bystander_language(), "", "bystander")
	if event.get("accepted", false): _announce_coach_step()
	# Contact during the analysis can come from Anna, not only from the trainee's hands.
	if event.get("action") == "patient_contact" and not event.get("accepted", true):
		_toast(NaretLanguage.text(str(event.get("reason", "")), _language))

func _on_state_changed(state: int) -> void:
	if observation_interpreter: observation_interpreter.cancel_pending()
	if interaction: interaction.set_cpr_enabled(state == NaretScenario.State.CPR)
	if interaction: interaction.set_aed_active(state == NaretScenario.State.AED)
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
	if audio_manager and not _smoke_mode and state > NaretScenario.State.IDLE:
		if not api.local_ai_url.is_empty():
			_announce_coach_step()
			return
		# A new step queues behind a bystander's line instead of cutting it off (the
		# start action clears the queue itself). The AED instruction comes with the
		# device (see _process), not with each analysis.
		if state in [NaretScenario.State.IDLE, NaretScenario.State.INTRO]: _aed_announced = false
		var clip := ["", "start", "check_patient", "call_help", "cpr", "", "recovery"][state] as String
		# Back to CPR after an analysis: the AED says so itself.
		if state == NaretScenario.State.CPR and (scenario.shock_count > 0 or scenario.reassessments > 0 or scenario.aed_attached): clip = ""
		if state == NaretScenario.State.RECOVERY and scenario.outcome == "rosc":
			# The closing words wait for the handover to the ambulance crew (1.18).
			get_tree().create_timer(NaretBystanderDirector.EMS_AFTER_S + 4.0).timeout.connect(func():
				if scenario.state == NaretScenario.State.RECOVERY: audio_manager.speak("", _language, "recovery", "instructor"))
		elif not clip.is_empty():
			audio_manager.speak("", _language, clip, "instructor")

func bystander_language() -> String:
	## Own-language mode keeps everyone in the trainee's language; the neighbour
	## mode replays the same steps with the bystander speaking the other one.
	if _mode == "own":
		return _language
	return "pl" if _language == "de" else "de"


func _opening_line() -> String:
	return NaretLanguage.text("bystander.default", bystander_language())


func _set_language(language: String) -> void:
	_language = language
	scenario.language = language
	_apply_language()


func _set_mode(mode: String) -> void:
	_mode = mode if mode in ["own", "neighbour"] else "own"
	_apply_language()


func _apply_language() -> void:
	_speech_confirmation.clear()
	if observation_interpreter: observation_interpreter.cancel_pending()
	llm.cancel_pending()
	# Recognition follows the trainee's selection; Anna may speak another language.
	audio_manager.set_language(_language)
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

func _on_transcript(text: String) -> void:
	if text.strip_edges().is_empty(): return
	if preload("res://scripts/scenario/spoken_observation.gd").reports_breath_pair(text):
		_last_heard_report = text.left(100)
		_record_speech_status("heard")
		print("NARET_TRANSCRIPT ", text.left(160))
		_speech_confirmation.clear()
		ccbm.observe_breath_pair()
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
	if bystander_language() == "en":
		var context := str(scenario.state) + ":" + str(scenario.get_available_actions()) + ":" + str(scenario.cycle_compressions) + ":" + str(scenario.cycle_ventilations)
		var interpreted: Dictionary = _speech_confirmation.evaluate(text, context, scenario.get_available_actions(), Time.get_ticks_msec())
		if interpreted.has("action"):
			if interpreted.get("breaths", 1) == 2:
				ccbm.observe_breath_pair()
			else:
				ccbm.observe_action(str(interpreted.action))
			return
		if interpreted.has("proposal"):
			var candidate := str(interpreted.proposal)
			var questions := {"begin_check": "Did you say the scene is safe? Say yes or no.", "check_responsiveness": "Did you report that he is not responding? Say yes or no.", "check_breathing": "Did you report that he is not breathing normally? Say yes or no.", "ventilation": "Did you complete one rescue breath? Say yes or no."}
			if interpreted.get("breaths", 1) == 2:
				questions["ventilation"] = "Did you complete two rescue breaths? Say yes or no."
			_toast(str(questions[candidate]))
			audio_manager.speak(str(questions[candidate]), "en", "confirm_" + candidate, "instructor")
			return
		if interpreted.has("message"):
			_toast(str(interpreted.message))
			audio_manager.speak("", "en", "speech_repeat", "instructor")
			return
	# Progression observations go to CCBM, never to Anna's generated action field.
	if ccbm and ccbm.observe_speech(text): return
	observation_interpreter.interpret(text, bystander_language())

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

var _last_coach_step := ""
var _unclassified_spoken_step := ""
func _announce_coach_step() -> void:
	if _smoke_mode or not audio_manager or api.local_ai_url.is_empty(): return
	var key := NaretTrainingCoach.step(scenario)
	if key == "setup":
		_last_coach_step = ""
		_unclassified_spoken_step = ""
		return
	if key == _last_coach_step: return
	# Replies requested during the previous step must not follow its replacement.
	llm.cancel_pending()
	observation_interpreter.cancel_pending()
	if key in ["breaths", "breath_one", "breath_two", "compressions", "compression_only"]:
		audio_manager.stop_speech()
	_last_coach_step = key
	_unclassified_spoken_step = ""
	print("NARET_COACH_STEP ", key, " count=", scenario.cycle_compressions)
	# Critical instructions use approved text. The LLM handles follow-up questions.
	var instruction := NaretTrainingCoach.current_instruction(scenario, _language)
	_toast(instruction)
	audio_manager.speak(instruction, _language, "", "instructor")
	# Repeat guidance only when requested; timed repeats interrupt conversation.

func _on_reply(reply: Dictionary) -> void:
	var speaker := str(reply.get("speaker", "bystander"))
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
	_on_action("compression", {"source": "hand_tracking", "measurement_verified": false,
		"evidence_kind": "tracked_hand_motion", "depth_measurement_kind": "hand_excursion",
		"depth_estimate_m": depth, "rate_bpm": rate, "correct_position": correct})

func _toggle_qcpr_panel() -> void:
	if qcpr_debug_panel:
		qcpr_debug_panel.visible = not qcpr_debug_panel.visible

func _on_qcpr_compression(depth_mm: float, rate_bpm: float, recoil_ok: bool, quality: Dictionary) -> void:
	mannequin.compress(depth_mm / 1000.0)
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
	var labels := {
		"desktop_preview": ["Desktop-Vorschau · kein Marker-Tracking", "Podgląd komputera · bez śledzenia znacznika"],
		"marker_tracked": ["ArUco · Marker erfasst", "ArUco · znacznik wykryty"],
		"marker_lost_pose_held": ["Marker verloren · Pose gehalten", "Utracono znacznik · pozycja zachowana"],
		"scanning_marker": ["Suche Marker 0 …", "Szukanie znacznika 0 …"],
		"tracking_standby": ["Tracking wartet auf Sichtkontakt", "Śledzenie czeka na znacznik"],
		"native_backend_missing": ["ArUco-Bibliothek fehlt", "Brak biblioteki ArUco"],
	}
	var text := (str(EN_STATUS.get(status, status)) if _language == "en" else str(labels[status][0 if _language == "de" else 1])) if labels.has(status) else status
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
			trace.store_line(JSON.stringify({"time_ms": Time.get_ticks_msec(), "status": status,
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
	var labels := {"online": ["Uni-Cloud verbunden", "Połączono z chmurą uczelni"],
		"microphone_paused": ["Mikrofon pausiert: Quest-Menü schließen", "Mikrofon wstrzymany: zamknij menu Quest"],
		"speech_connection_failed": ["Sprachverbindung unterbrochen: PC/USB prüfen", "Brak połączenia głosowego: sprawdź PC/USB"],
		"speech_server_error": ["Fehler beim Spracherkennungsserver", "Błąd serwera rozpoznawania mowy"],
		"speech_request_busy": ["Vorherige Aufnahme wird verarbeitet", "Poprzednie nagranie jest przetwarzane"],
		"offline": ["Offline · lokale Sprachclips", "Offline · lokalne nagrania"],
		"recording": ["Mikrofonaufnahme", "Nagrywanie mikrofonu"],
		"transcribing": ["Sprache wird erkannt …", "Rozpoznawanie mowy …"],
		"transcribed": ["Sprache erkannt", "Rozpoznano mowę"],
		"cloud": ["Antwort aus der Uni-Cloud", "Odpowiedź z chmury uczelni"],
		"scripted_fallback": ["Offline-Dialog", "Dialog offline"],
		"offline_clip": ["Lokales Sprach-Audio", "Lokalne nagranie"],
		"tts_offline_clip": ["Lokales Sprach-Audio", "Lokalne nagranie"],
		"asr_offline_use_text": ["ASR nicht erreichbar · Text oder Tasten verwenden", "ASR niedostępne · użyj tekstu lub przycisków"],
		"microphone_permission_required": ["Mikrofonfreigabe benötigt", "Wymagane uprawnienie mikrofonu"],
		"recording_empty": ["Keine Sprache aufgenommen", "Brak nagrania"],
		"models_unverified": ["Modellprüfung nicht erreichbar", "Lista modeli niedostępna"],
	}
	var text := (str(EN_STATUS.get(status, status)) if _language == "en" else str(labels[status][0 if _language == "de" else 1])) if labels.has(status) else status
	if dashboard: dashboard.set_status(text)
	if xr_info: xr_info.set_status(text)
	if hand_menu: hand_menu.show_notice(text)

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
			var expected: String = language if mode == "own" else ("pl" if language == "de" else "de")
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
