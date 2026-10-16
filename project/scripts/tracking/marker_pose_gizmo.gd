extends RefCounted
## Visualises a detected marker pose, before layout or patient offsets.
## Axes are five centimetres long: X red, Y green, Z blue.

static func attach_to(marker: Node3D, marker_id: int) -> void:
	var colours := [Color.RED, Color.GREEN, Color.BLUE]
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i in range(3):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.003, 0.003, 0.003) + axes[i] * 0.05
		var line := MeshInstance3D.new()
		line.mesh = mesh
		line.position = axes[i] * 0.025
		line.material_override = _material(colours[i])
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(line)
	var centre := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.004
	sphere.height = 0.008
	centre.mesh = sphere
	centre.material_override = _material(Color.WHITE)
	centre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(centre)
	var label := Label3D.new()
	label.text = "Marker %d" % marker_id
	label.position = Vector3(0, 0.065, 0)
	label.font_size = 32
	label.pixel_size = 0.0005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	marker.add_child(label)
	marker.visible = false # Never show an identity pose before the first detection.

static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Diagnostic overlay stays readable through the patient model.
	material.no_depth_test = true
	material.render_priority = 100
	return material
