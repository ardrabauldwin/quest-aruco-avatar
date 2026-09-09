extends SceneTree

func _init() -> void:
	call_deferred("run")

func bounds(node: Node3D, basis_transform := Transform3D.IDENTITY) -> AABB:
	var first := true
	var result := AABB()
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null:
			continue
		var transform: Transform3D = basis_transform * node.global_transform.affine_inverse() * child.global_transform
		for surface in child.mesh.get_surface_count():
			var vertices = child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var p: Vector3 = transform * vertex
				if first:
					result = AABB(p, Vector3.ZERO)
					first = false
				else:
					result = result.expand(p)
	return result

func run() -> void:
	var model = load("res://assets/avatar/mannequin.glb").instantiate()
	root.add_child(model)
	var raw := bounds(model)
	print("MODEL root scale: ", model.scale)
	print("MODEL local bounds: ", raw, "; dimensions m: ", raw.size)
	print("MODEL dimensions at 0.77: ", raw.size * 0.77)
	print("MODEL local centre: ", raw.get_center())
	model.free()
	quit()
