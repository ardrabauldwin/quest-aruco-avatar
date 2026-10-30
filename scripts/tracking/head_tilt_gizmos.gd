extends Node3D
## Debug overlay: the two spheres NaretHeadTiltGesture measures against, at their real radii.
## Forehead (palm) blue, chin (index fingertip) orange. Each lights up while its own hand
## condition holds; both turn green while the gesture is active. They always show the entry
## radius. Switched on from the hand menu's Debug row.

const FOREHEAD_COLOUR := Color(0.2, 0.55, 1.0)
const CHIN_COLOUR := Color(1.0, 0.55, 0.1)
const ACTIVE_COLOUR := Color(0.2, 1.0, 0.35)
const IDLE_ALPHA := 0.4
const LIT_ALPHA := 0.8
const LIT_LIGHTEN := 0.35

var _mannequin: Node3D
var _gesture: NaretHeadTiltGesture
var _forehead: MeshInstance3D
var _chin: MeshInstance3D

func bind(mannequin: Node3D, gesture: NaretHeadTiltGesture) -> void:
	_mannequin = mannequin
	_gesture = gesture
	_forehead = _sphere("ForeheadArea", NaretHeadTiltGesture.FOREHEAD_RADIUS_M)
	_chin = _sphere("ChinArea", NaretHeadTiltGesture.CHIN_RADIUS_M)
	_process(0.0)

func _process(_delta: float) -> void:
	if _mannequin == null or _gesture == null:
		return
	_place(_forehead, _mannequin.gesture_forehead(), _gesture.forehead_met, FOREHEAD_COLOUR)
	_place(_chin, _mannequin.gesture_chin(), _gesture.chin_met, CHIN_COLOUR)

func _place(area: MeshInstance3D, point: Vector3, met: bool, colour: Color) -> void:
	area.global_position = point
	var lit := met or _gesture.active
	var shown := ACTIVE_COLOUR if _gesture.active else colour
	if lit:
		shown = shown.lightened(LIT_LIGHTEN)
	shown.a = LIT_ALPHA if lit else IDLE_ALPHA
	(area.material_override as StandardMaterial3D).albedo_color = shown

func _sphere(area_name: String, radius: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Depth tested: the part of an area inside the patient stays hidden, so it reads against the skin.
	material.render_priority = 100
	var area := MeshInstance3D.new()
	area.name = area_name
	area.mesh = mesh
	area.material_override = material
	area.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.top_level = true    # the gesture's points are world space
	add_child(area)
	return area
