extends "res://tests/suite.gd"
## Imported assets must contain usable skinning/animation, not just a skeleton name.

const Animator = preload("res://scripts/mannequin/rig_animator.gd")

func run() -> Array[String]:
	await _test_ragdoll()
	await _test_prefixed_clip()
	await _test_patient()
	await _test_mannequin_compression()
	await _test_bystander("res://assets/models/human_bystander.glb")
	await _test_bystander("res://assets/models/human_bystander_male.glb")
	return failures

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _load_actor(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		check(false, "Missing humanoid asset: " + path)
		return null
	var model: Node3D = load(path).instantiate()
	_tree().root.add_child(model)
	return model

func _configure(model: Node3D) -> Node:
	var rig := Animator.new()
	model.add_child(rig)
	rig.configure(model)
	return rig

func _skeleton(model: Node3D) -> Skeleton3D:
	var matches := model.find_children("*", "Skeleton3D", true, false)
	return matches[0] as Skeleton3D if not matches.is_empty() else null

func _player(model: Node3D) -> AnimationPlayer:
	var matches := model.find_children("*", "AnimationPlayer", true, false)
	return matches[0] as AnimationPlayer if not matches.is_empty() else null

func _verify_skin(model: Node3D) -> void:
	var skeleton := _skeleton(model)
	check(skeleton != null and skeleton.get_bone_count() >= 50, model.name + ": full human skeleton")
	var weighted_meshes := 0
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.skin == null or not node.get_node_or_null(node.skeleton) is Skeleton3D:
			continue
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_WEIGHTS] != null and not arrays[Mesh.ARRAY_WEIGHTS].is_empty():
				weighted_meshes += 1
	check(weighted_meshes > 0, model.name + ": mesh weights bind geometry to skeleton")

func _test_ragdoll() -> void:
	## A tugged shoulder has to actually move, and the torso has to stay put: it is
	## registered to the physical mannequin and may not drift under physics.
	var model := _load_actor("res://assets/models/human_patient.glb")
	if model == null:
		return
	var stage := Node3D.new()
	_tree().root.add_child(stage)
	var ragdoll := NaretRagdoll.new()
	stage.add_child(ragdoll)
	ragdoll.configure(model)
	check(ragdoll.is_active(), "patient rig builds a physical skeleton")
	check(ragdoll.limb_count() >= 8, "both arms and the head are simulated")
	# Physical bones reach their bone positions a frame after entering the tree, so
	# a baseline taken any earlier measures that snap rather than the simulation.
	# Limbs settle and fall asleep first, which is exactly the state a trainee finds
	# them in; the grab has to work from there.
	await _tree().create_timer(0.4).timeout
	var shoulder := ragdoll.limb_point("upperarm_l")
	var spine := ragdoll.limb_point("spine_03")
	check(shoulder != Vector3.ZERO, "the shoulder resolves to a physical bone")
	check(not ragdoll.grab("far", shoulder + Vector3(0, 2, 0)), "a hand out of reach grabs nothing")
	check(ragdoll.grab("hand", shoulder), "a hand at the shoulder takes hold of it")
	# The headless runner advances physics frames but does not integrate these
	# bodies, so this asserts the command NaReT issues, not Godot's solver. The
	# resulting motion is reviewed in the Meta XR Simulator (make xr-shot --tug),
	# where the same pull moves the limb about 0.11 m.
	var target := shoulder + Vector3(0.12, 0.30, 0.0)
	ragdoll.move("hand", target)
	check(ragdoll.held_target("hand").distance_to(target) < 0.001, "a limb is pulled toward the hand")
	check(ragdoll._torso_target_angle == 0.0, "a single hand on one shoulder cannot sit the person up")
	var shoulder_r := ragdoll.limb_point("upperarm_r")
	check(ragdoll.grab("hand2", shoulder_r), "second hand takes hold of right shoulder")
	ragdoll.move("hand2", shoulder_r + Vector3(0.0, 0.30, 0.0))
	check(ragdoll._torso_target_angle > 20.0, "grasping both shoulders with two hands sits the person up")
	ragdoll.release("hand2")
	check(ragdoll._torso_target_angle == 0.0, "releasing one shoulder drops the sit-up target back to zero")
	# Reach is bounded so a failed joint can never stretch the patient across the room.
	ragdoll.move("hand", shoulder + Vector3(0.0, 8.0, 0.0))
	check(ragdoll.held_target("hand").distance_to(shoulder) <= NaretRagdoll.REACH_M + 0.001, "a limb cannot be dragged past its reach")
	check(ragdoll.held_target("spine_03") == Vector3.ZERO, "the registered torso is never driven")
	ragdoll.release("hand")
	check(not ragdoll.holds("hand"), "releasing lets go of the limb")
	model.queue_free()
	stage.queue_free()
	await _tree().process_frame

func _verify_size(model: Node3D, path: String, standing: bool) -> void:
	var expected := 0.0
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/human_models.json")):
		if entry["file"] == path.get_file():
			expected = entry["adult_height_m"]
	var bounds := AABB()
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		# Rest-pose bounds in armature space; the node scale would double-count it.
		var box: AABB = node.get_aabb()
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	check(absf(longest - expected) < 0.03, path.get_file() + ": whole silhouette measures the documented height")
	if standing:
		# Clothing delete-groups remove the covered body; a body-only scale sinks legs and shoes.
		check(absf(bounds.position.y) < 0.03, path.get_file() + ": shoes rest on the floor")

func _find_morph_mesh(model: Node3D, key: String) -> MeshInstance3D:
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.find_blend_shape_by_name(key) >= 0:
			return node
	return null

func _test_prefixed_clip() -> void:
	var model := Node3D.new()
	_tree().root.add_child(model)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	skeleton.add_bone("spine")
	model.add_child(skeleton)
	var player := AnimationPlayer.new()
	model.add_child(player)
	var library := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = 1.0
	var track := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, NodePath("Skeleton3D:spine"))
	clip.track_insert_key(track, 0.0, Quaternion.IDENTITY)
	clip.track_insert_key(track, 0.5, Quaternion(Vector3.UP, 0.5))
	clip.track_insert_key(track, 1.0, Quaternion.IDENTITY)
	library.add_animation("Armature|idle", clip)
	player.add_animation_library("", library)
	var rig := _configure(model)
	check(rig.has_clip("idle") and rig.get_current_clip() == "idle", "Namespaced imported clip resolves to canonical idle")
	player.advance(0.5)
	check(not skeleton.get_bone_pose_rotation(0).is_equal_approx(Quaternion.IDENTITY), "Imported clip playback actually changes bone pose")
	check(clip.loop_mode == Animation.LOOP_NONE, "Shared source animation resource remains unchanged")
	check(player.get_animation("Armature|idle").loop_mode == Animation.LOOP_LINEAR, "Actor-local idle animation loops")
	model.queue_free()
	await _tree().process_frame

func _test_patient() -> void:
	var model := _load_actor("res://assets/models/human_patient.glb")
	if model == null:
		return
	_verify_skin(model)
	_verify_size(model, "res://assets/models/human_patient.glb", false)
	var rig := _configure(model)
	for name: String in ["idle", "breathing", "compression"]:
		check(rig.has_clip(name), "Patient has imported " + name + " clip")
	for name: String in ["Sternum", "Mouth", "Forehead", "EyeLeft", "EyeRight"]:
		check(model.find_child(name, true, false) != null, "Patient has anatomical marker " + name)
	var body := _find_morph_mesh(model, "compression")
	check(body != null, "Patient has local chest compression morph")
	if body != null:
		var index := body.find_blend_shape_by_name("compression")
		var original := model.transform
		check(rig.play_action("compression"), "Patient compression action plays")
		var maximum := 0.0
		for sample in range(22):
			await _tree().create_timer(0.02).timeout
			maximum = maxf(maximum, body.get_blend_shape_value(index))
		check(maximum > 0.2, "Compression visibly deforms skinned chest surface")
		check(body.get_blend_shape_value(index) < 0.05, "Compression releases the chest")
		check(model.transform.is_equal_approx(original), "Compression does not scale or move whole patient")
		check(rig.get_current_clip() == "idle", "Patient action returns to idle")
	check(not rig.play_action("unrecognized_action"), "Unknown action is rejected")
	model.queue_free()
	await _tree().process_frame

func _test_mannequin_compression() -> void:
	var mannequin: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	_tree().root.add_child(mannequin)
	await _tree().process_frame
	await _tree().process_frame
	var body: MeshInstance3D = mannequin.find_child("PatientBody", true, false)
	check(body != null, "Mannequin has PatientBody mesh")
	if body != null:
		mannequin.set_overlay_opacity(0.75)
		var overlay := body.get_surface_override_material(0) as ShaderMaterial
		check(overlay != null, "Patient skin uses overlay shader")
		if overlay != null:
			check(bool(overlay.get_shader_parameter("clinical_skin")), "Clinical shading targets visible body skin")
			check(bool(overlay.get_shader_parameter("pe_visual_cues")), "Mouth and calf landmarks enable clinical shading")
			var mouth: Vector3 = overlay.get_shader_parameter("mouth_world")
			var calf: Vector3 = overlay.get_shader_parameter("calf_world")
			check(mouth.is_finite() and calf.is_finite() and mouth.distance_to(calf) > 0.3, "Lip and calf shader anchors are separate valid landmarks")
		var index := body.find_blend_shape_by_name("compression")
		check(index >= 0, "PatientBody has compression blend shape")
		mannequin.set_compression_depth(0.05)
		await _tree().process_frame
		await _tree().process_frame
		var weight := body.get_blend_shape_value(index)
		check(weight >= 1.0, "set_compression_depth(0.05) caves in chest morph")
		check(mannequin.zone.position.y < mannequin._zone_rest_position.y - 0.02, "Highlight zone moves down with caved-in chest")
		mannequin.set_compression_depth(0.0)
		await _tree().create_timer(0.2).timeout
		check(body.get_blend_shape_value(index) < 0.05, "Releasing compression restores chest to rest")
		check(absf(mannequin.zone.position.y - mannequin._zone_rest_position.y) < 0.005, "Highlight zone returns to rest position")
	mannequin.queue_free()
	await _tree().process_frame

func _test_bystander(path: String) -> void:
	var model := _load_actor(path)
	if model == null:
		return
	_verify_skin(model)
	_verify_size(model, path, true)
	var rig := _configure(model)
	for name: String in ["idle", "talk", "anxious", "relief"]:
		check(rig.has_clip(name), path.get_file() + ": imported " + name + " clip")
	check(rig.has_morph("mouth_open"), "Bystander has a real facial mouth morph")
	var other := _load_actor(path)
	var other_rig := _configure(other)
	rig.set_speaking(true)
	check(rig.get_current_clip() == "talk", "Speaking activates skeletal talk animation")
	check(other_rig.get_current_clip() == "anxious", "Other actor keeps independent emotional animation")
	var skeleton := _skeleton(model)
	var player := _player(model)
	if skeleton != null and player != null:
		player.advance(0.01)
		var initial: Array[Quaternion] = []
		for bone in skeleton.get_bone_count():
			initial.append(skeleton.get_bone_pose_rotation(bone))
		player.advance(0.55)
		var changed := false
		for bone in skeleton.get_bone_count():
			if not skeleton.get_bone_pose_rotation(bone).is_equal_approx(initial[bone]):
				changed = true
		check(changed, path.get_file() + ": talk animation deforms the human rig")
		check(player.get_animation("idle") != _player(other).get_animation("idle"), "Actors own independent animation resources")
	var mouth := _find_morph_mesh(model, "mouth_open")
	if mouth != null:
		rig.set_mouth_open(0.75)
		await _tree().process_frame
		await _tree().process_frame
		check(is_equal_approx(mouth.get_blend_shape_value(mouth.find_blend_shape_by_name("mouth_open")), 0.75), "Audio amplitude drives actual mouth morph")
		rig.set_speaking(false)
		check(mouth.get_blend_shape_value(mouth.find_blend_shape_by_name("mouth_open")) == 0.0, "Speech completion closes mouth")
	rig.set_emotion("calm")
	check(rig.get_current_clip() == "relief", "Calming plays the relief transition")
	if player != null:
		player.advance(player.get_animation("relief").length + 0.1)
		check(rig.get_current_clip() == "idle", "Relief blends back to idle")
	model.queue_free()
	other.queue_free()
	await _tree().process_frame
