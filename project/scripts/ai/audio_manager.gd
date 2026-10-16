class_name NaretAudioManager
extends Node
## Voice-activated microphone, asynchronous ASR, and bounded double-buffered speech.

signal transcript_ready(text: String)
signal playback_changed(active: bool)
signal recording_changed(active: bool)
signal listening_changed(active: bool)
signal status_changed(message: String)
signal utterance_started(text: String, language: String, source: String, speaker: String)

const MAX_RECORDING_SECONDS := 12.0
## Voice activity detection, ported from the learning platform's SpeakGame VAD.
## The threshold is room- and microphone-dependent; treat it as a calibration knob.
const VAD_THRESHOLD := 0.02
const VAD_SILENCE_MS := 1200
const VAD_MIN_SPEECH_MS := 500
## Keep audio just before activation so the first word is not clipped.
const PRE_ROLL_SECONDS := 0.35
var language := "pl"
var recording := false
var listening := false
var _api: NaretUniAPIClient
var _microphone: AudioStreamPlayer
var _recorder: AudioEffectRecord
var _players: Array[AudioStreamPlayer] = []
var _player_index := 0
var _playing := false
var _instruction_revision := 0
var _voice_cache: Dictionary = {}
var _recording_start := 0
var _transcribing := false
var _preparing := false
var _pending: Array[Dictionary] = []
var _ready_audio: Array[Dictionary] = []
var _clips: Dictionary = {}
var _clip_texts: Dictionary = {}
var _capture_bus_name := ""
var _capture: AudioEffectCapture
var _level := 0.0
var _speech_seen := false
var _silence_start := 0
var _speech_bus_name := ""
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _generation := 0
var _recent_frames := PackedVector2Array()
var _recording_prefix := PackedVector2Array()


func configure(api_client: NaretUniAPIClient) -> void:
	_api = api_client


func _ready() -> void:
	# Configure with the shared client before speech. Standalone use is supported.
	AudioServer.add_bus()
	var speech_bus := AudioServer.bus_count - 1
	_speech_bus_name = "NaretSpeech_" + str(get_instance_id())
	AudioServer.set_bus_name(speech_bus, _speech_bus_name)
	var analyzer := AudioEffectSpectrumAnalyzer.new()
	analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_256
	AudioServer.add_bus_effect(speech_bus, analyzer)
	_spectrum = AudioServer.get_bus_effect_instance(speech_bus, 0) as AudioEffectSpectrumAnalyzerInstance
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "SpeechBuffer" + str(index)
		player.bus = _speech_bus_name
		add_child(player)
		player.finished.connect(_on_playback_finished)
		_players.append(player)
	_load_offline_clips()
	var coach_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/coaching/manifest.json")) if FileAccess.file_exists("res://assets/audio/coaching/manifest.json") else {}
	if coach_manifest is Dictionary:
		for clip: Dictionary in coach_manifest.get("clips", []):
			var coach_key := str(clip.language) + ":instructor:" + str(clip.text)
			_voice_cache[coach_key] = load(str(clip.path))
	_microphone = AudioStreamPlayer.new()
	_microphone.name = "Microphone"
	_microphone.stream = AudioStreamMicrophone.new()
	add_child(_microphone)
	AudioServer.add_bus()
	var capture_bus := AudioServer.bus_count - 1
	var bus_name := "NaretCapture_" + str(get_instance_id())
	_capture_bus_name = bus_name
	AudioServer.set_bus_name(capture_bus, bus_name)
	_recorder = AudioEffectRecord.new()
	_recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(capture_bus, _recorder)
	# A second tap on the same bus supplies the level the recorder cannot report.
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(capture_bus, _capture)
	AudioServer.set_bus_mute(capture_bus, true) # Capture before muting; no mic feedback.
	_microphone.bus = bus_name


func _exit_tree() -> void:
	listening = false
	if recording:
		recording = false
		_recorder.set_recording_active(false)
		recording_changed.emit(false)
	if is_instance_valid(_microphone):
		_microphone.stop()
	for bus_name in [_capture_bus_name, _speech_bus_name]:
		var index := AudioServer.get_bus_index(bus_name)
		if index > 0: AudioServer.remove_bus(index)


func get_speech_amplitude() -> float:
	if not _playing or _spectrum == null: return 0.0
	var magnitude := _spectrum.get_magnitude_for_frequency_range(90.0, 4000.0)
	return clampf(maxf(magnitude.x, magnitude.y) * 18.0, 0.0, 1.0)


func set_language(lang: String) -> void:
	language = lang if lang in ["de", "pl", "en"] else "pl"


func set_listening(enabled: bool) -> void:
	## Arms voice activation. The recorder only runs once someone actually speaks.
	if enabled == listening:
		return
	if enabled and not _microphone_available():
		listening_changed.emit(false)
		return
	listening = enabled
	if enabled:
		_microphone.play()
		_reset_vad()
		status_changed.emit("listening")
	else:
		if recording:
			end_recording()
		_microphone.stop()
		status_changed.emit("listening_off")
	listening_changed.emit(enabled)


func _microphone_available() -> bool:
	if OS.get_name() == "Android" and "android.permission.RECORD_AUDIO" not in OS.get_granted_permissions():
		OS.request_permissions()
		status_changed.emit("microphone_permission_required")
		return false
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		status_changed.emit("microphone_input_disabled")
		return false
	return true


func _reset_vad() -> void:
	_speech_seen = false
	_silence_start = 0
	_level = 0.0
	_recent_frames.clear()
	if _capture != null:
		_capture.clear_buffer()


func input_level() -> float:
	## Root mean square of the frames captured since the last call.
	if _capture == null:
		return 0.0
	var frames := _capture.get_frames_available()
	if frames <= 0:
		# Missing frames are not continuing speech. A stale loud sample previously
		# kept the silence timer reset until the 12-second recording limit.
		_level = 0.0
		return 0.0
	var buffer := _capture.get_buffer(frames)
	# Capture and Record share the mixer rate. Retain only idle microphone audio;
	# never prepend Anna's or the instructor's playback to a learner recording.
	if not recording and not _playing and not _preparing and not _transcribing:
		_recent_frames.append_array(buffer)
		var limit := int(AudioServer.get_mix_rate() * PRE_ROLL_SECONDS)
		if _recent_frames.size() > limit:
			_recent_frames = _recent_frames.slice(_recent_frames.size() - limit)
	var total := 0.0
	for frame: Vector2 in buffer:
		total += frame.x * frame.x
	_level = sqrt(total / float(buffer.size())) if buffer.size() > 0 else 0.0
	return _level


func _process(_delta: float) -> void:
	if recording and (Time.get_ticks_msec() - _recording_start) >= int(MAX_RECORDING_SECONDS * 1000):
		end_recording()
		return
	if not listening:
		return
	update_voice_activity(input_level(), Time.get_ticks_msec())


func update_voice_activity(level: float, now: int) -> void:
	## Speech starts a recording; trailing silence ends it. While the bystander is
	## speaking or a transcript is in flight the microphone must not retrigger on
	## the app's own voice.
	# Preparing a response must also suppress automatic microphone activation.
	# Otherwise ambient sound can call begin_recording(), which cancels the
	# in-flight TTS before its first sample is played.
	if _playing or _preparing or _transcribing:
		_reset_vad()
		return
	if not recording:
		if level > VAD_THRESHOLD:
			begin_recording()
			# The triggering block already contained speech, including quick words.
			_speech_seen = recording
		return
	if level > VAD_THRESHOLD:
		_speech_seen = true
		_silence_start = 0
		return
	if not _speech_seen or now - _recording_start < VAD_MIN_SPEECH_MS:
		return
	if _silence_start == 0:
		_silence_start = now
	elif now - _silence_start > VAD_SILENCE_MS:
		end_recording()


func begin_recording() -> void:
	if recording:
		return
	if _transcribing:
		recording_changed.emit(false)
		return
	if not _microphone_available():
		recording_changed.emit(false)
		return
	_recording_prefix = _recent_frames.duplicate()
	stop_speech()
	recording = true
	_recording_start = Time.get_ticks_msec()
	_speech_seen = false
	_silence_start = 0
	# Voice activation already opened the microphone in set_listening().
	# Restarting its playback here can stop the shared Android input stream.
	if not _microphone.playing:
		_microphone.play()
	_recorder.set_recording_active(true)
	recording_changed.emit(true)
	status_changed.emit("recording")


func end_recording() -> void:
	if not recording:
		return
	recording = false
	recording_changed.emit(false)
	_recorder.set_recording_active(false)
	# Under 0.1 s the recorder may hold no mixed audio yet, and get_recording()
	# errors on an empty buffer; it would be too short to transcribe anyway.
	var too_short := Time.get_ticks_msec() - _recording_start < 100
	# Voice activation keeps the microphone open for the next utterance.
	if not listening:
		_microphone.stop()
	else:
		_reset_vad()
	var captured: AudioStreamWAV = null if too_short else _recorder.get_recording()
	if captured == null or captured.data.size() < 3200:
		status_changed.emit("recording_empty")
		return
	if not _recording_prefix.is_empty():
		captured.data = encode_prefix(_recording_prefix, captured.stereo) + captured.data
	_recording_prefix.clear()
	_ensure_api()
	_transcribing = true
	status_changed.emit("transcribing")
	var result: Dictionary = await _api.transcribe(NaretUniAPIClient.encode_wav(captured), language)
	_transcribing = false
	if result.get("ok", false):
		var transcript: Variant = result.get("json", {}).get("text", "")
		if transcript is String and not transcript.strip_edges().is_empty():
			status_changed.emit("transcribed")
			transcript_ready.emit(transcript.strip_edges().left(1000))
			return
		status_changed.emit("speech_not_understood")
		return
	if result.get("error", "") == "local_asr_timeout":
		status_changed.emit("speech_recognition_timeout")
	else:
		status_changed.emit("asr_offline_use_text")


func speak(text: String, lang: String = "pl", clip_key: String = "calm", speaker: String = "bystander") -> void:
	## `speaker` says who is talking. Language no longer distinguishes them: in the
	## own-language mode the instructor and the bystander share one language.
	var target_language := lang if lang in ["de", "pl", "en"] else language
	if speaker == "anna": speaker = "bystander"
	if _pending.size() >= 6:
		_pending.pop_front()
	var item := {"text": text.left(1000), "language": target_language, "clip_key": clip_key, "speaker": speaker,
		"queued_ms": Time.get_ticks_msec()}
	if speaker == "instructor":
		_instruction_revision += 1
		item["instruction_revision"] = _instruction_revision
		# Only the newest instruction matters; one still waiting is out of date.
		_pending.assign(_pending.filter(func(other): return other.get("speaker") != "instructor"))
		_ready_audio.assign(_ready_audio.filter(func(other): return other.get("speaker") != "instructor"))
	_pending.insert(_queue_slot(_pending, speaker), item)
	if not _preparing:
		_prepare_next()


const STALE_INSTRUCTION_MS := 30000 # Allow the witness to finish before guidance.

static func _queue_slot(queue: Array, speaker: String) -> int:
	## People in the scene go before waiting instructor lines: a bystander reacts
	## now, the instructor's step prompt can wait a moment.
	if speaker == "instructor":
		return queue.size()
	for i in queue.size():
		if queue[i].get("speaker") == "instructor":
			return i
	return queue.size()


func stop_speech() -> void:
	_pending.clear()
	_ready_audio.clear()
	_generation += 1 # In-flight HTTP audio is discarded after a barge-in.
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream = null
	if _playing:
		_playing = false
		playback_changed.emit(false)


func is_speaking() -> bool:
	return _playing or _preparing or not _pending.is_empty() or not _ready_audio.is_empty()

func _prepare_next() -> void:
	_preparing = true
	_ensure_api()
	while not _pending.is_empty():
		# At most two decoded streams are held while the current utterance plays.
		if _ready_audio.size() >= 2:
			break
		var item: Dictionary = _pending.pop_front()
		var generation := _generation
		var stream: AudioStream = null
		var source := "offline_clip"
		var requested_clip: String = item["language"] + "/" + item["clip_key"]
		var scripted: bool = item["text"].is_empty() or _clip_texts.get(requested_clip, "") == item["text"]
		var spoken_text := str(item["text"]) if not str(item["text"]).is_empty() else str(_clip_texts.get(requested_clip, ""))
		var cache_key := str(item["language"]) + ":" + str(item.get("speaker", "bystander")) + ":" + spoken_text
		stream = _voice_cache.get(cache_key)
		if stream == null and (not scripted or not _api.local_ai_url.is_empty()) and not spoken_text.is_empty() and _api.is_available(_api.tts_model):
			var result: Dictionary = await _api.synthesize(spoken_text, item["language"], item.get("speaker", "bystander"))
			if result.get("ok", false):
				stream = NaretUniAPIClient.decode_audio(result["body"])
				if stream != null:
					source = str(result.get("source", "cloud"))
					if _voice_cache.size() >= 32: _voice_cache.erase(_voice_cache.keys()[0])
					_voice_cache[cache_key] = stream
		if generation != _generation:
			continue
		if item.get("speaker") == "instructor" and item.get("instruction_revision", -1) != _instruction_revision: continue
		if stream == null:
			# Unscripted clarification has no matching recording. Keep its displayed
			# text instead of replacing it with the unrelated bystander calm clip.
			if str(item["clip_key"]).is_empty():
				status_changed.emit("audio_clip_missing")
				continue
			var clip_id: String = item["language"] + "/" + item["clip_key"]
			if not _clips.has(clip_id):
				clip_id = item["language"] + "/calm"
			stream = _clips.get(clip_id)
			item["text"] = _clip_texts.get(clip_id, item["text"])
			status_changed.emit("tts_offline_clip")
		if stream != null:
			item["stream"] = stream
			item["source"] = source
			_ready_audio.insert(_queue_slot(_ready_audio, item.get("speaker", "bystander")), item)
			if not _playing:
				_play_next()
		else:
			status_changed.emit("audio_clip_missing")
	_preparing = false


func _play_next() -> void:
	if _ready_audio.is_empty() or _players.is_empty():
		return
	var item: Dictionary = _ready_audio.pop_front()
	# An instruction that waited behind the people for too long is out of date.
	while item.get("speaker") == "instructor" and Time.get_ticks_msec() - int(item.get("queued_ms", 0)) > STALE_INSTRUCTION_MS:
		if _ready_audio.is_empty():
			if _playing:
				_playing = false
				playback_changed.emit(false)
			return
		item = _ready_audio.pop_front()
	_player_index = 1 - _player_index
	var player := _players[_player_index]
	player.stream = item["stream"]
	player.play()
	print("NARET_VOICE_START speaker=", item.get("speaker", "bystander"), " source=", item["source"])
	if not _playing:
		_playing = true
		playback_changed.emit(true)
	utterance_started.emit(item["text"], item["language"], item["source"], item.get("speaker", "bystander"))


func _on_playback_finished() -> void:
	if _ready_audio.is_empty():
		_playing = false
		playback_changed.emit(false)
	else:
		_play_next()
	if not _preparing and not _pending.is_empty():
		_prepare_next()


func _ensure_api() -> void:
	if not is_instance_valid(_api):
		_api = NaretUniAPIClient.new()
		add_child(_api)


func _load_offline_clips() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	if not manifest is Dictionary:
		return
	for item: Dictionary in manifest.get("clips", []):
		var clip_id: String = item["language"] + "/" + item["key"]
		var path: String = "res://assets/audio/" + item["file"]
		if ResourceLoader.exists(path):
			_clips[clip_id] = load(path)
			_clip_texts[clip_id] = item["text"]

static func encode_prefix(frames: PackedVector2Array, stereo: bool) -> PackedByteArray:
	## Encode the same signed, little-endian 16-bit PCM as AudioEffectRecord.
	var pcm := StreamPeerBuffer.new()
	pcm.big_endian = false
	for frame in frames:
		if stereo:
			pcm.put_16(int(clampf(frame.x, -1.0, 1.0) * 32767.0))
			pcm.put_16(int(clampf(frame.y, -1.0, 1.0) * 32767.0))
		else:
			pcm.put_16(int(clampf((frame.x + frame.y) * 0.5, -1.0, 1.0) * 32767.0))
	return pcm.data_array
