class_name NaretRigAnimator
extends Node
## Plays imported skin animations and facial morphs without moving/scaling the model root.
## Imported clips may be named idle, Armature|idle, or AnimationLibrary/idle.

const LOOPING_CLIPS := ["idle", "anxious", "talk", "phone", "walk", "reach", "cpr"]
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
			animation.loop_mode = Animation.LOOP_LINEAR if canonical in LOOPING_CLIPS else Animation.LOOP_NONE
			for track in animation.get_track_count():
				if animation.track_get_type(track) != Animation.TYPE_BLEND_SHAPE:
					continue
				var shape := _canonical_name(String(animation.track_get_path(track)))
				# Live speech amplitude and local CPR envelopes must own these weights;
				# otherwise the imported clip overwrites them with baked morph values.
				if shape in ["mouth_open", "mouthopen", "breathing", "compression", "chestbreath", "chestcompression"]:
					animation.track_set_enabled(track, false)
			if not _clips.has(canonical):
				_clips[canonical] = {"player": player, "name": imported_name}
		player.animation_finished.connect(_on_animation_finished.bind(player))
	process_priority = 100 # Apply live mouth amplitude after ordinary actor updates.
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
	if not active:
		_external_mouth_until_ms = 0
		_apply_mouth(0.0)
	# Speech can interrupt an emotional transition, not CPR/ventilation animation.
	if _action_active and _current_clip in ["breathing", "compression"]:
		return
	_action_active = false
	_play_baseline()

func set_mouth_open(amount: float) -> void:
	_external_mouth_until_ms = Time.get_ticks_msec() + 150
	_apply_mouth(amount)

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
	elif _speaking and has_clip("talk"):
		preferred = "talk"
	elif _emotion in ["anxious", "afraid", "fear", "sad"] and has_clip("anxious"):
		preferred = "anxious"
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
	if Time.get_ticks_msec() < _external_mouth_until_ms:
		return
	# Initial speech approximation. Real audio amplitude can override via set_mouth_open().
	var amount := (0.18 + absf(sin(_clock * 17.0)) * 0.62) if _speaking else 0.0
	_apply_mouth(amount)

func _apply_mouth(amount: float) -> void:
	_set_shape("mouth_open", clampf(amount, 0.0, 1.0) if is_finite(amount) else 0.0)

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
