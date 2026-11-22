class_name NaretSpeechBubble
extends Node3D
## Speech bubble in the line of sight (team to-do, issue #1, "0. App-Start"): only for the
## welcome at the start (decision 17 Nov 2026); during the training the texts stay on the
## wrist. It floats DISTANCE_M in front of the eyes, slightly below, and follows the view
## smoothly instead of being nailed to the head.

const DISTANCE_M := 1.1
const BELOW_M := 0.08
const FOLLOW := 3.0
const PIXEL_M := 0.0011

var camera: Node3D
var _label: Label3D
var _panel: MeshInstance3D
var _until_ms := 0

func _ready() -> void:
	_panel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.2)
	_panel.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.03, 0.09, 0.16, 0.86)
	material.no_depth_test = true
	material.render_priority = 10
	_panel.material_override = material
	add_child(_panel)
	_label = Label3D.new()
	_label.pixel_size = PIXEL_M
	_label.font_size = 34
	_label.outline_size = 6
	_label.width = 600.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.no_depth_test = true
	_label.render_priority = 11
	_label.position = Vector3(0, 0, 0.002)
	add_child(_label)
	visible = false

func say(text: String, seconds: float) -> void:
	_label.text = text
	# The panel grows with the text: about 40 characters per line at this size.
	var lines := ceili(float(text.length()) / 40.0)
	(_panel.mesh as QuadMesh).size = Vector2(0.72, 0.07 + 0.045 * lines)
	_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	visible = true
	_place(1.0)

func hide_now() -> void:
	visible = false
	_until_ms = 0

func _process(delta: float) -> void:
	if not visible: return
	if Time.get_ticks_msec() > _until_ms:
		visible = false
		return
	_place(1.0 - exp(-FOLLOW * delta))

func _place(weight: float) -> void:
	if camera == null: return
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001: forward = Vector3.FORWARD
	forward = forward.normalized()
	var target := camera.global_position + forward * DISTANCE_M + Vector3.DOWN * BELOW_M
	global_position = global_position.lerp(target, weight) if weight < 1.0 else target
	look_at(global_position + (global_position - camera.global_position), Vector3.UP)
