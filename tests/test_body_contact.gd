extends "res://tests/suite.gd"
## Step-back gate (issue #1, 8.): hands count as on the patient when they touch the avatar's
## body shape (capsules between its bones), not only a strip along the middle.

func run() -> Array[String]:
	failures.clear()
	var mannequin: Node3D = load("res://scenes/mannequin.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(mannequin)
	var skeleton := mannequin.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("spine_03")).origin
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_l")).origin
	var foot := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_r")).origin
	check(mannequin.body_contains(chest + Vector3.UP * 0.12), "a palm on the middle of the chest touches the body")
	check(mannequin.body_contains(hand + Vector3.UP * 0.05), "a hand on his hand touches the body")
	check(mannequin.body_contains(foot), "the foot is part of the body")
	check(not mannequin.body_contains(chest + Vector3.UP * 0.45), "45 cm above the chest is off the body")
	var side := (hand - chest)
	side.y = 0.0
	check(not mannequin.body_contains(chest + side.normalized() * 0.9), "90 cm to the side is off the body")
	mannequin.free()
	return failures
