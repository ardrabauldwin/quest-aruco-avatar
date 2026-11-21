extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var model: Node3D = load("res://assets/models/aed.glb").instantiate()
	var device := NaretAED.new()
	for node in [patient,model,device]: tree.root.add_child(node)
	device.configure(model,patient)
	var scenario := NaretScenario.new()
	scenario.start()
	for action in ["begin_check","check_responsiveness","call_emergency","check_breathing"]: scenario.submit_action(action)
	device.sync(scenario,"en")
	check(not device._pad_guides.visible, "no guidance before device is powered")
	device._power_on()
	device.sync(scenario,"en")
	for i in 60:
		await tree.process_frame
		if device._pad_guides._built: break
	var guides: Node3D = device._pad_guides
	check(guides._built and guides.visible, "guides built on actual patient mesh while pads are being placed")
	for key in ["PadRight","PadLeft"]:
		var outline: MeshInstance3D = guides.outlines[key]
		check(outline.visible and outline.mesh != null, "both target outlines have geometry " + key)
		if outline.mesh:
			var points: PackedVector3Array = outline.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			check(points.size() >= 24, "dashed outline has multiple independent segments " + key)
			# One flat rectangle in the pad's plane, not dashes bent over the body.
			var spec: Array = device.PAD_POSES[key]
			var normal := Basis.from_euler(spec[1] * PI / 180.0).y.normalized()
			var lo := INF
			var hi := -INF
			for p in points:
				lo = minf(lo, p.dot(normal))
				hi = maxf(hi, p.dot(normal))
			check(hi - lo < 0.001, "the outline is flat, all in one plane (%.4f m) %s" % [hi - lo, key])
		var material := outline.material_override as StandardMaterial3D
		check(material.albedo_color.is_equal_approx(guides.GOLD) and not material.no_depth_test, "the yellow lines use normal depth occlusion")
	var pads: Array = device._pads.values()
	pads[0].global_transform = device._pad_target("PadRight")
	device._drop(pads[0])
	device.sync(scenario,"en")
	check(not guides.outlines.PadRight.visible and guides.outlines.PadLeft.visible, "only completed target disappears")
	patient.position += Vector3(1,0.2,-0.4)
	device.sync(scenario,"en")
	check(guides.global_transform.is_equal_approx(patient.get_body_transform()), "guides follow avatar placement, not world-fixed points")
	pads[1].global_transform = device._pad_target("PadLeft")
	device._drop(pads[1])
	device.sync(scenario,"en")
	check(not guides.outlines.PadRight.visible and not guides.outlines.PadLeft.visible, "no outlines remain once both pads are placed")
	scenario.aed_attached = true
	device.sync(scenario,"en")
	check(not guides.visible, "guides are hidden during analysis/shock/CPR after attachment")
	device.reset()
	check(not guides.visible and not guides._built, "reset hides and invalidates guide geometry")
	for node in [device,model,patient,scenario]: node.free()
	return failures
