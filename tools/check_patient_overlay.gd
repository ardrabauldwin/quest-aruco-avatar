extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	root.add_child(patient)
	patient.set_overlay_opacity(0.3)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 2, 2)
	camera.look_at(Vector3(0, 0.2, 0))
	camera.make_current()
	for i in 12:
		await process_frame
	print("Patient overlay rendered; materials=", patient._overlay_materials.size())
	quit()
