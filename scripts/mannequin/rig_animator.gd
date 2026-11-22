class_name NaretRigAnimator
extends Node
## Plays imported skin animations and facial morphs without moving/scaling the model root.
## Imported clips may be named idle, Armature|idle, or AnimationLibrary/idle.

const LOOPING_CLIPS := ["idle", "anxious", "talk", "phone", "walk", "reach", "cpr", "listen"]
## Talk takes: "talk" plus any "talk_2".."talk_n" clip. A speaker chains them, never the
## same one twice in a row, so a long instruction does not loop one gesture (2026-11-06).
const TAKE_BLEND_S := 0.4
## Optional face morphs beyond mouth_open (generator from 2026-11-07): blink_l, blink_r,
## brow_up, jaw_open, lips_round, lips_wide. A model without them just skips those.
const BLINK_CLOSE_S := 0.08
const BLINK_HOLD_S := 0.04
const BLINK_OPEN_S := 0.12
## Head nod on a speech onset, degrees about the head bone's side axis, decaying.
const BEAT_NOD_DEG := 3.5
const BEAT_DECAY_S := 0.25
var _talk_takes: Array[String] = []
var _take_left := 0.0
var _last_take := ""
var _blink_in := 2.5
var _blink_at := -1.0         # seconds into the current blink, -1 = eyes open
var _brow := 0.0
var _bands := Vector3.ZERO    # smoothed low/mid/high speech energy (0..1 each)
var _bands_raw := Vector3.ZERO
var _bands_until_ms := 0
var _level_slow := 0.0
var _beat := 0.0
var _head_bone := -1
var _model: Node3D
var _clips: Dictionary = {}
var _morphs: Dictionary = {}
var _players: Array[AnimationPlayer] = []
var _skeleton: Skeleton3D
var _active_player: AnimationPlayer
var _current_clip := ""
var _emotion := "anxious"
var _speaking := false
var _action_active := false
var _clock := 0.0
## Per-character art setting, separate from the measured audio level.
var speech_jaw_scale := 1.0
var _external_mouth_until_ms := 0
var _morph_tween: Tween
var _gaze_target: Node3D
var _gaze: Array[LookAtModifier3D] = []
var _posture := ""
var _posture_speed := 1.0
## Spine, neck and head share the turn toward the gaze target, each within what
## that joint can do; the eyes take the rest. Degrees: sideways, up/down.
const HEAD_TURN := {"spine_03": [18.0, 8.0], "neck_01": [30.0, 20.0], "head": [42.0, 28.0]}

## Matches LookAtModifier3D.forward_axis: +X, -X, +Y, -Y, +Z, -Z.
const FORWARD_AXES := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]

func configure(model: Node3D) -> void:
	for player: AnimationPlayer in _players:
		var handler := _on_animation_finished.bind(player)
		if is_instance_valid(player) and player.animation_finished.is_connected(handler):
			player.animation_finished.disconnect(handler)
		if is_instance_valid(player):
			player.stop()
	if _morph_tween:
		_morph_tween.kill()
	_clips.clear()
	_morphs.clear()
	_players.clear()
	_skeleton = null
	_active_player = null
	_action_active = false
	_current_clip = ""
	_model = model
	if not is_instance_valid(model):
		return
	_collect(model)
	for player: AnimationPlayer in _players:
		# Loop flags belong to each actor, not to the shared imported GLB resource.
		for library_name: StringName in player.get_animation_library_list():
			var library: AnimationLibrary = player.get_animation_library(library_name).duplicate(true)
			player.remove_animation_library(library_name)
			player.add_animation_library(library_name, library)
		for imported_name: StringName in player.get_animation_list():
			var canonical := _canonical_name(String(imported_name))
			if canonical == "reset":
				continue
			var animation := player.get_animation(imported_name)
			if animation.get_track_count() == 0:
				continue
			animation.loop_mode = Animation.LOOP_LINEAR if (canonical in LOOPING_CLIPS or _is_take(canonical)) else Animation.LOOP_NONE
			for track in animation.get_track_count():
				if animation.track_get_type(track) != Animation.TYPE_BLEND_SHAPE:
					continue
				var shape := _canonical_name(String(animation.track_get_path(track)))
				# Live speech amplitude and local CPR envelopes must own these weights;
				# otherwise the imported clip overwrites them with baked morph values.
				# eyes_closed (17 Nov 2026) belongs to NaretMannequin: shut until ROSC.
				if shape in ["mouth_open", "mouthopen", "breathing", "compression", "chestbreath", "chestcompression", "eyes_closed", "eyesclosed"]:
					animation.track_set_enabled(track, false)
			if not _clips.has(canonical):
				_clips[canonical] = {"player": player, "name": imported_name}
		player.animation_finished.connect(_on_animation_finished.bind(player))
	process_priority = 100 # Apply live mouth amplitude after ordinary actor updates.
	_talk_takes.clear()
	for key: String in _clips:
		if _is_take(key):
			_talk_takes.append(key)
	_talk_takes.sort()
	_head_bone = _skeleton.find_bone("head") if has_skeleton() else -1
	_setup_gaze(model)
	_apply_mouth(0.0)
	_play_baseline()


func _setup_gaze(model: Node3D) -> void:
	## MakeHuman's game_engine rig has no eye bones; the generator adds eye_l/eye_r
	## and rebinds the eyeballs to them. Older models without those bones stay still.
	_gaze.clear()
	_gaze_target = null
	if not has_skeleton():
		return
	for side: String in ["l", "r"]:
		var bone := _skeleton.find_bone("eye_" + side)
		if bone < 0:
			continue
		if _gaze_target == null:
			_gaze_target = Node3D.new()
			_gaze_target.name = "GazeTarget"
			_skeleton.add_child(_gaze_target)
		var modifier := LookAtModifier3D.new()
		modifier.name = "Gaze" + side.to_upper()
		modifier.bone_name = "eye_" + side
		modifier.forward_axis = _gaze_forward_axis(model, side)
		modifier.use_secondary_rotation = true
		modifier.use_angle_limitation = true
		modifier.symmetry_limitation = true
		# An eyeball that rotates further than this reads as a rolled-back stare.
		modifier.primary_limit_angle = deg_to_rad(38.0)
		modifier.secondary_limit_angle = deg_to_rad(26.0)
		modifier.duration = 0.22
		modifier.transition_type = Tween.TRANS_SINE
		modifier.ease_type = Tween.EASE_IN_OUT
		modifier.active = false
		_skeleton.add_child(modifier)
		modifier.target_node = modifier.get_path_to(_gaze_target)
		_gaze.append(modifier)


func _gaze_forward_axis(model: Node3D, side: String) -> int:
	## The EyeLeft/EyeRight markers sit on the cornea and are parented to the eye
	## bone, so their offset is the rest gaze direction in bone space. Reading it
	## beats assuming how the exporter mapped Blender's bone axes.
	var marker := model.find_child("Eye" + ("Left" if side == "l" else "Right"), true, false) as Node3D
	if marker == null or marker.position.length_squared() < 0.000001:
		return 2 # +Y, the bone's own length axis in Blender.
	return _axis_toward(marker.position)


func enable_head_turn(model: Node3D) -> void:
	## Bystanders turn head and upper body to whoever they look at; the patient keeps
	## eyes-only gaze. Modifiers run in child order, so these go before the eyes.
	if not has_skeleton() or _gaze_target == null:
		return
	var forward_skeleton := _skeleton.global_basis.inverse() * model.global_basis.z.normalized()
	var index := 0
	for bone_name: String in HEAD_TURN:
		var bone := _skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var modifier := LookAtModifier3D.new()
		modifier.name = "Turn_" + bone_name
		modifier.bone_name = bone_name
		modifier.forward_axis = _axis_toward(_skeleton.get_bone_global_rest(bone).basis.inverse() * forward_skeleton)
		modifier.use_angle_limitation = true
		modifier.use_secondary_rotation = true
		modifier.symmetry_limitation = true
		modifier.primary_limit_angle = deg_to_rad(HEAD_TURN[bone_name][0])
		modifier.secondary_limit_angle = deg_to_rad(HEAD_TURN[bone_name][1])
		modifier.duration = 0.45
		modifier.transition_type = Tween.TRANS_SINE
		modifier.ease_type = Tween.EASE_IN_OUT
		modifier.active = false
		_skeleton.add_child(modifier)
		_skeleton.move_child(modifier, index)
		index += 1
		modifier.target_node = modifier.get_path_to(_gaze_target)
		_gaze.insert(0, modifier)


static func _axis_toward(direction: Vector3) -> int:
	var best := 2
	var best_dot := -2.0
	for i in FORWARD_AXES.size():
		var dot: float = (FORWARD_AXES[i] as Vector3).dot(direction.normalized())
		if dot > best_dot:
			best_dot = dot
			best = i
	return best


func set_posture(posture: String, speed: float = 1.0) -> void:
	## A task pose (phone, walk, reach) outranks emotion and talking; "" releases it.
	## `speed` scales the clip, e.g. short steps while turning on the spot.
	if posture == _posture and is_equal_approx(speed, _posture_speed):
		return
	_posture = posture
	_posture_speed = speed
	if not _action_active:
		_play_baseline()


func look_at_point(world_point: Vector3) -> void:
	## Aims both eyes; the modifiers clamp and ease so the eyes never snap.
	if _gaze_target == null:
		return
	_gaze_target.global_position = world_point
	for modifier: LookAtModifier3D in _gaze:
		modifier.active = true


func clear_gaze() -> void:
	## Back to the rest stare, which is what an unresponsive patient shows.
	for modifier: LookAtModifier3D in _gaze:
		modifier.active = false


func has_gaze() -> bool:
	return not _gaze.is_empty()

func _collect(node: Node) -> void:
	if node is AnimationPlayer:
		_players.append(node)
	if node is Skeleton3D and _skeleton == null:
		_skeleton = node
	# Only ArrayMesh carries blend shapes; primitives such as the pupil overlay
	# now live inside the model tree and would break a blind call.
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		for index in node.mesh.get_blend_shape_count():
			var key := _canonical_name(String(node.mesh.get_blend_shape_name(index)))
			if key in ["chestbreath", "breath"]:
				key = "breathing"
			elif key == "chestcompression":
				key = "compression"
			elif key == "mouthopen":
				key = "mouth_open"
			if not _morphs.has(key):
				_morphs[key] = []
			_morphs[key].append({"mesh": node, "index": index})
	for child: Node in node.get_children():
		_collect(child)

func set_emotion(value: String) -> void:
	var next := value.to_lower()
	if next == _emotion:
		return
	_emotion = next
	if _speaking or _action_active:
		return
	if _emotion in ["calm", "grateful", "relief", "thankful"] and has_clip("relief"):
		play_action("relief")
	else:
		_play_baseline()

func set_speaking(active: bool) -> void:
	if active == _speaking:
		return
	_speaking = active
	if active:
		_brow = 1.0           # an eyebrow lift opens an utterance
		_level_slow = 0.0
	else:
		_external_mouth_until_ms = 0
		_bands_until_ms = 0
		_bands = Vector3.ZERO
		_beat = 0.0
		_apply_mouth(0.0)
		_set_shape("lips_round", 0.0)
		_set_shape("lips_wide", 0.0)
	# Speech can interrupt an emotional transition, not CPR/ventilation animation.
	if _action_active and _current_clip in ["breathing", "compression"]:
		return
	_action_active = false
	_play_baseline()

func set_mouth_open(amount: float) -> void:
	_external_mouth_until_ms = Time.get_ticks_msec() + 150
	_apply_mouth(amount)

## Live speech energy in three bands (low 90-400 Hz, mid 400-1500 Hz, high 1500-4000 Hz),
## each 0..1: jaw from low+mid, rounded lips from mid, wide lips from high.
func set_mouth_bands(bands: Vector3) -> void:
	_bands_raw = bands.clamp(Vector3.ZERO, Vector3.ONE)
	_bands_until_ms = Time.get_ticks_msec() + 150

func drop_takes(takes: Array) -> void:
	## Talking takes this character should not use (never the last one left).
	for take in takes:
		if _talk_takes.size() > 1: _talk_takes.erase(take)

func talk_takes() -> Array[String]:
	return _talk_takes.duplicate()

static func _is_take(key: String) -> bool:
	if key == "talk":
		return true
	return key.begins_with("talk_") and key.substr(5).is_valid_int()

func _pick_take() -> String:
	if _talk_takes.is_empty():
		return "talk"
	var choices := _talk_takes.filter(func(take: String) -> bool: return take != _last_take)
	if choices.is_empty():
		choices = _talk_takes
	var take: String = choices[randi() % choices.size()]
	_last_take = take
	var clip: Animation = _clips[take].player.get_animation(_clips[take].name)
	_take_left = maxf(clip.length, 0.5)
	return take

func set_compression_amount(weight: float) -> void:
	if _morph_tween and is_instance_valid(_morph_tween) and _morph_tween.is_running():
		_morph_tween.kill()
	_set_shape("compression", clampf(weight, 0.0, 2.2))

func play_action(action: String, max_weight: float = 1.0) -> bool:
	var key := _canonical_name(action)
	if key == "ventilation":
		key = "breathing"
	if key in LOOPING_CLIPS:
		if not has_clip(key):
			return false
		if _morph_tween:
			_morph_tween.kill()
		_set_shape("breathing", 0.0)
		_set_shape("compression", 0.0)
		_action_active = false
		return _play_clip(key, 0.15)
	if not has_clip(key) and not (key in ["breathing", "compression"] and _morphs.has(key) and is_inside_tree()):
		return false
	if _morph_tween:
		_morph_tween.kill()
	if has_clip(key):
		_action_active = true
		var clip: Animation = _clips[key].player.get_animation(_clips[key].name)
		var duration := 0.33 if key == "compression" else (1.9 if key == "breathing" else clip.length)
		_play_clip(key, 0.04 if key == "compression" else 0.12, true, clip.length / maxf(duration, 0.01))
		if key in ["breathing", "compression"] and _morphs.has(key):
			_start_action_morph(key, false, max_weight)
		return true
	# Useful for morph-only models, preserving geometry boundaries and anatomy.
	if key in ["breathing", "compression"] and _morphs.has(key) and is_inside_tree():
		_action_active = true
		_current_clip = key
		_start_action_morph(key, true, max_weight)
		return true
	return false

func _start_action_morph(key: String, return_to_idle: bool, max_weight: float = 1.0) -> void:
	# Local visual envelope also supports exporters that bake a constant morph track.
	# The imported skin animation continues in parallel at the same action duration.
	_set_shape("breathing", 0.0)
	_set_shape("compression", 0.0)
	_morph_tween = create_tween()
	var apply := func(value: float): _set_shape(key, value)
	var peak := clampf(max_weight, 0.0, 2.2)
	_morph_tween.tween_method(apply, 0.0, peak, 0.11 if key == "compression" else 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_morph_tween.tween_method(apply, peak, 0.0, 0.18 if key == "compression" else 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if return_to_idle:
		_morph_tween.finished.connect(func():
			_action_active = false
			_play_baseline())

func _play_baseline() -> void:
	var preferred := "idle"
	if not _posture.is_empty() and has_clip(_posture):
		preferred = _posture
	elif _speaking and not _talk_takes.is_empty():
		preferred = _current_clip if _current_clip in _talk_takes else _pick_take()
	elif _emotion in ["anxious", "afraid", "fear", "sad"] and has_clip("anxious"):
		preferred = "anxious"
	elif has_clip("listen"):
		preferred = "listen"
	if not _play_clip(preferred, 0.25, false, _posture_speed if preferred == _posture else 1.0) and preferred != "idle":
		_play_clip("idle", 0.18)

func _play_clip(key: String, blend: float, restart: bool = false, speed: float = 1.0) -> bool:
	if not _clips.has(key):
		return false
	var entry: Dictionary = _clips[key]
	var player: AnimationPlayer = entry.player
	if not is_instance_valid(player):
		return false
	if not restart and _current_clip == key and player.is_playing():
		player.speed_scale = speed
		return true
	if is_instance_valid(_active_player) and _active_player != player:
		_active_player.stop()
	_active_player = player
	_current_clip = key
	player.speed_scale = 1.0
	player.play(entry.name, blend, speed)
	if restart:
		player.seek(0.0, true)
	return true

func _on_animation_finished(_name: StringName, player: AnimationPlayer) -> void:
	if player != _active_player or not _action_active:
		return
	_action_active = false
	if _morph_tween:
		_morph_tween.kill()
	_set_shape("breathing", 0.0)
	_set_shape("compression", 0.0)
	_play_baseline()

func _process(delta: float) -> void:
	_clock += delta
	_chain_take(delta)
	_update_blink(delta)
	_update_brow(delta)
	var now := Time.get_ticks_msec()
	var level := 0.0
	if now < _bands_until_ms:
		# Smooth the analyser (about 80 ms) so the lips do not flicker per frame.
		_bands = _bands.lerp(_bands_raw, 1.0 - exp(-delta / 0.08))
		level = clampf(0.9 * _bands.x + 0.7 * _bands.y + 0.5 * _bands.z, 0.0, 1.0)
		_apply_mouth(level)
		_set_shape("lips_round", clampf((_bands.y - _bands.z) * 0.7, 0.0, 1.0))
		_set_shape("lips_wide", clampf(_bands.z * 1.2, 0.0, 0.8))
	elif now >= _external_mouth_until_ms:
		# Initial speech approximation. Real audio amplitude can override via set_mouth_open().
		level = (0.18 + absf(sin(_clock * 17.0)) * 0.62) if _speaking else 0.0
		_apply_mouth(level)
	_update_beat(delta, level)

func _chain_take(delta: float) -> void:
	if not _speaking or _action_active or _talk_takes.size() < 2 or _current_clip not in _talk_takes:
		return
	_take_left -= delta
	if _take_left <= 0.0:
		_play_clip(_pick_take(), TAKE_BLEND_S)

func _update_blink(delta: float) -> void:
	if not _morphs.has("blink_l") and not _morphs.has("blink_r"):
		return
	if _blink_at < 0.0:
		_blink_in -= delta
		if _blink_in > 0.0:
			return
		_blink_at = 0.0
		_blink_in = randf_range(2.0, 6.0)
	_blink_at += delta
	var weight := 0.0
	if _blink_at < BLINK_CLOSE_S:
		weight = _blink_at / BLINK_CLOSE_S
	elif _blink_at < BLINK_CLOSE_S + BLINK_HOLD_S:
		weight = 1.0
	elif _blink_at < BLINK_CLOSE_S + BLINK_HOLD_S + BLINK_OPEN_S:
		weight = 1.0 - (_blink_at - BLINK_CLOSE_S - BLINK_HOLD_S) / BLINK_OPEN_S
	else:
		_blink_at = -1.0
	_set_shape("blink_l", weight)
	_set_shape("blink_r", weight)

func _update_brow(delta: float) -> void:
	if not _morphs.has("brow_up"):
		return
	_brow = move_toward(_brow, 0.0, delta / 0.7)
	_set_shape("brow_up", 0.6 * _brow + 0.25 * _beat)

## A rising speech level is a syllable onset: nod the head a little, decaying. Kimodo
## clips key every bone each frame, so the AnimationPlayer resets the pose before this
## adds to it; the gaze modifiers run afterwards and still aim the head.
func _update_beat(delta: float, level: float) -> void:
	if not _speaking or _head_bone < 0 or not has_skeleton():
		_beat = 0.0
		return
	if level > _level_slow + 0.18 and _beat < 0.2:
		_beat = 1.0
	_level_slow = lerpf(_level_slow, level, 1.0 - exp(-delta / 0.25))
	_beat *= exp(-delta / BEAT_DECAY_S)
	if _beat < 0.01:
		_beat = 0.0
		return
	var nod := Quaternion(Vector3.RIGHT, deg_to_rad(-BEAT_NOD_DEG * _beat))
	_skeleton.set_bone_pose_rotation(_head_bone, _skeleton.get_bone_pose_rotation(_head_bone) * nod)

func _apply_mouth(amount: float) -> void:
	var weight := clampf(amount, 0.0, 1.0) if is_finite(amount) else 0.0
	weight *= clampf(speech_jaw_scale, 0.0, 1.0)
	# The speakers' generated legacy mouth_open visibly tears the face when
	# combined with the authored jawOpen unit. Prefer the native jaw unit;
	# patient/older models without it retain their existing mouth fallback.
	if has_morph("jaw_open"):
		_set_shape("mouth_open", 0.0)
		_set_shape("jaw_open", weight)
	else:
		_set_shape("mouth_open", weight)

func _set_shape(key: String, value: float) -> void:
	for target: Dictionary in _morphs.get(key, []):
		var mesh: MeshInstance3D = target.mesh
		if is_instance_valid(mesh):
			mesh.set_blend_shape_value(int(target.index), value)

func has_animations() -> bool:
	return not _clips.is_empty()

func has_clip(name: String) -> bool:
	return _clips.has(_canonical_name(name))

func has_morph(name: String) -> bool:
	return _morphs.has(_canonical_name(name))

func has_skeleton() -> bool:
	return is_instance_valid(_skeleton) and _skeleton.get_bone_count() > 0

func get_current_clip() -> String:
	return _current_clip

static func _canonical_name(value: String) -> String:
	var result := value.to_lower()
	for separator: String in ["|", "/", ":"]:
		var parts := result.split(separator)
		result = parts[parts.size() - 1]
	return result.replace(" ", "_").replace("-", "_")
