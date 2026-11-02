extends RefCounted
## Visualises a detected marker pose, before layout or patient offsets.
## Sized to read at arm's length through passthrough: axes 15 cm long, X red, Y green, Z blue.

const AXIS_M := 0.15
const THICKNESS_M := 0.008

static func attach_to(marker: Node3D, marker_id: int) -> void:
	var colours := [Color.RED, Color.GREEN, Color.BLUE]
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i in range(3):
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * THICKNESS_M + axes[i] * AXIS_M
		var line := MeshInstance3D.new()
		line.mesh = mesh
		line.position = axes[i] * AXIS_M * 0.5
		line.material_override = _material(colours[i])
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(line)
	var centre := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.012
	sphere.height = 0.024
	centre.mesh = sphere
	centre.material_override = _material(Color.WHITE)
	centre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(centre)
	var label := Label3D.new()
	label.text = "Marker %d" % marker_id
	label.name = "Label"
	label.position = Vector3(0, AXIS_M + 0.03, 0)
	label.font_size = 64
	label.pixel_size = 0.0006
	label.render_priority = 100
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	marker.add_child(label)
	marker.visible = false # Never show an identity pose before the first detection.

static func attach_fused(point: Node3D) -> void:
	## The fused point: a yellow ball, labelled above the marker gizmos' labels.
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.05
	ball.mesh = sphere
	ball.material_override = _material(Color.YELLOW)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	point.add_child(ball)
	var label := Label3D.new()
	label.text = "FUSED"
	label.modulate = Color.YELLOW
	label.position = Vector3(0, AXIS_M + 0.09, 0)
	label.font_size = 64
	label.pixel_size = 0.0008
	label.render_priority = 100
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	point.add_child(label)

static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Diagnostic overlay stays readable through the patient model.
	material.no_depth_test = true
	material.render_priority = 100
	return material
