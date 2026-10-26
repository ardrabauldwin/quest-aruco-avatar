extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var actor: NaretBystander = load("res://scenes/bystander_male.tscn").instantiate()
	var patient := Node3D.new()
	tree.root.add_child(patient)
	tree.root.add_child(actor)
	actor.patient = patient
	actor.set_emotion("calm")
	actor.speaking = true
	actor._face_scene(Vector3(3, 1, 0), 0.016)
	check(actor._turning, "first instruction can begin while instructor turns toward trainee")
	check(actor._rig.get_current_clip() == "talk", "standing turn does not replace talking with walking")
	var skeleton: Skeleton3D = actor.get_node("Model").find_children("*", "Skeleton3D", true, false)[0]
	await tree.process_frame
	var rotations: Array[Quaternion] = []
	for bone in skeleton.get_bone_count(): rotations.append(skeleton.get_bone_pose_rotation(bone))
	await tree.create_timer(0.6).timeout
	var moved := false
	for bone in skeleton.get_bone_count():
		moved = moved or not rotations[bone].is_equal_approx(skeleton.get_bone_pose_rotation(bone))
	check(moved, "first talking clip advances naturally without manually advancing AnimationPlayer")
	actor.speaking = false
	actor._face_scene(Vector3(3, 1, 0), 0.016)
	check(actor._rig.get_current_clip() == "walk", "silent turns retain the original stepping animation")
	actor.set_posture("phone")
	actor.speaking = true
	actor._face_scene(Vector3(3, 1, 0), 0.016)
	check(actor._rig.get_current_clip() == "phone", "intentional task posture still takes precedence")
	actor.queue_free()
	patient.queue_free()
	await tree.process_frame
	return failures
