extends RefCounted
## Last pose that passed the actual body/wall checks, restored after animation
## if a gesture would leave its assigned space. Never changes actor identity.
var skeletons: Array = []
var meshes: Array = []
var root_transform := Transform3D.IDENTITY

func capture(person: Node3D) -> void:
	root_transform = person.global_transform
	skeletons.clear()
	meshes.clear()
	for skeleton: Skeleton3D in person.find_children("*", "Skeleton3D", true, false):
		var poses: Array = []
		for i in skeleton.get_bone_count(): poses.append(skeleton.get_bone_pose(i))
		skeletons.append({"node":skeleton, "poses":poses})
	for mesh: MeshInstance3D in person.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var weights: Array = []
		for i in mesh.mesh.get_blend_shape_count(): weights.append(mesh.get_blend_shape_value(i))
		meshes.append({"node":mesh, "weights":weights})

func restore(person: Node3D) -> void:
	person.global_transform = root_transform
	for entry in skeletons:
		var skeleton: Skeleton3D = entry.node
		if not is_instance_valid(skeleton): continue
		for i in entry.poses.size():
			var pose: Transform3D = entry.poses[i]
			skeleton.set_bone_pose_position(i, pose.origin)
			skeleton.set_bone_pose_rotation(i, pose.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_scale(i, pose.basis.get_scale())
		skeleton.force_update_all_bone_transforms()
	for entry in meshes:
		var mesh: MeshInstance3D = entry.node
		if not is_instance_valid(mesh): continue
		for i in entry.weights.size(): mesh.set_blend_shape_value(i, entry.weights[i])
