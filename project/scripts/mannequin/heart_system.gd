class_name NaretHeart
extends Node3D
## X-ray view of the heart inside the chest. It stays hidden while nobody works on
## the patient and fades in under the hands during compressions, so the trainee
## sees what the pushing does: the ventricles are squeezed with the chest depth and
## spring back on recoil. With a pulse it beats on each ECG complex instead.
## Drawn without depth test, so it shows through the skin like an overlay.

const SHOW_AFTER_S := 2.5
const SQUEEZE_AT_5CM := 0.28

var _material: StandardMaterial3D
var _depth := 0.0
var _beat := 0.0
var _alpha := 0.0
var _idle := SHOW_AFTER_S
var _rest_scale := Vector3.ONE

func _ready() -> void:
	_rest_scale = scale
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.62, 0.05, 0.09, 0.0)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = 3
	_material.roughness = 0.35
	_material.rim_enabled = true
	_material.rim = 1.0
	_material.rim_tint = 0.6
	_material.emission_enabled = true
	_material.emission = Color("ff4a4a")
	_material.emission_energy_multiplier = 0.25
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_apply_material(self)
	visible = false

func _apply_material(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _material
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_material(child)

func squeeze(depth_m: float) -> void:
	## Chest compression depth in metres; any depth counts as someone working.
	_depth = depth_m
	if depth_m > 0.002:
		_idle = 0.0

func pulse() -> void:
	## ECG complex; only visible as a beat once the heart is on screen anyway.
	_beat = 1.0

func _process(delta: float) -> void:
	_idle += delta
	var target_alpha := 0.7 if _idle < SHOW_AFTER_S else 0.0
	_alpha = move_toward(_alpha, target_alpha, delta * (2.5 if target_alpha > _alpha else 0.8))
	visible = _alpha > 0.01
	if not visible:
		return
	_beat = move_toward(_beat, 0.0, delta * 3.0)
	# Squeeze front-to-back (model Z after the chest rotation) and widen slightly,
	# like the ventricles pressed between sternum and spine.
	var squeeze := clampf(_depth / 0.05, 0.0, 1.3) * SQUEEZE_AT_5CM
	var beat := _beat * 0.08
	scale = _rest_scale * Vector3(1.0 + squeeze * 0.35 + beat, 1.0 - beat * 0.5, 1.0 - squeeze + beat)
	_material.albedo_color.a = _alpha
	_material.emission_energy_multiplier = 0.25 + squeeze * 2.0 + _beat * 0.8
