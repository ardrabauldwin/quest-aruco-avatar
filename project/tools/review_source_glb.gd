extends SceneTree
func _initialize() -> void:
    run.call_deferred()
func bounds(node: Node, parent: Transform3D, points: Array[Vector3]) -> void:
    var t := parent
    if node is Node3D: t = parent * node.transform
    if node is MeshInstance3D:
        for surface in node.mesh.get_surface_count():
            for v in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
                points.append(t * v)
    for child in node.get_children(): bounds(child, t, points)
func measure(path: String, placement: Transform3D) -> Dictionary:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    assert(document.append_from_file(path, state) == OK)
    var model := document.generate_scene(state)
    var points: Array[Vector3] = []
    bounds(model, placement, points)
    var lo := Vector3(INF, INF, INF)
    var hi := Vector3(-INF, -INF, -INF)
    for v in points:
        lo = lo.min(v)
        hi = hi.max(v)
    model.free()
    return {"size": [hi.x-lo.x, hi.y-lo.y, hi.z-lo.z], "min": [lo.x,lo.y,lo.z], "max": [hi.x,hi.y,hi.z], "vertices": points.size()}
func run() -> void:
    var old := Transform3D(Basis(Vector3(0.6872449, 0, 0), Vector3(0, -3.082737e-08, 0.7052474), Vector3(0, -0.6681291, -2.920488e-08)), Vector3(0.065894, -0.023727, 0.530701))
    var result := {"source_in_old_scene": measure("C:/Users/bauld/Overlay/quest-aruco-avatar/project/assets/avatar/mannequin.glb", old), "denis_scan": measure("res://assets/models/mannequin_scan.glb", Transform3D.IDENTITY)}
    var out := FileAccess.open("res://build/glb_review.json", FileAccess.WRITE)
    out.store_string(JSON.stringify(result, "  "))
    print(JSON.stringify(result))
    quit()
