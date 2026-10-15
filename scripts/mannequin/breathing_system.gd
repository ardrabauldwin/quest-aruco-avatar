class_name NaretBreathing
extends Node

var chest: Node3D
var _rest_position := Vector3.ZERO
var _tween: Tween
var _mesh: MeshInstance3D
var _breath_index := -1
var _compression_index := -1

func configure(target: Node3D) -> void:
	chest = target
	_rest_position = target.position
	if target is MeshInstance3D:
		_mesh = target
		_breath_index = _mesh.find_blend_shape_by_name("ChestBreath")
		if _breath_index < 0: _breath_index = _mesh.find_blend_shape_by_name("breathing")
		_compression_index = _mesh.find_blend_shape_by_name("ChestCompression")
		if _compression_index < 0: _compression_index = _mesh.find_blend_shape_by_name("compression")

func ventilate() -> void:
	if not is_instance_valid(chest): return
	if _tween: _tween.kill()
	_tween = create_tween()
	if _breath_index >= 0:
		_mesh.set_blend_shape_value(_compression_index, 0.0)
		_tween.tween_method(func(value: float): _mesh.set_blend_shape_value(_breath_index, value), 0.0, 1.0, 0.8)
		_tween.tween_method(func(value: float): _mesh.set_blend_shape_value(_breath_index, value), 1.0, 0.0, 1.1)
		return
	_tween.tween_property(chest, "position:y", _rest_position.y + 0.012, 0.8)
	_tween.tween_property(chest, "position:y", _rest_position.y, 1.1)

func compress(depth: float) -> void:
	if not is_instance_valid(chest): return
	if _tween: _tween.kill()
	_tween = create_tween()
	if _compression_index >= 0:
		_mesh.set_blend_shape_value(_breath_index, 0.0)
		var weight := clampf(depth / 0.05, 0.0, 1.0)
		_tween.tween_method(func(value: float): _mesh.set_blend_shape_value(_compression_index, value), 0.0, weight, 0.13)
		_tween.tween_method(func(value: float): _mesh.set_blend_shape_value(_compression_index, value), weight, 0.0, 0.2)
		return
	_tween.tween_property(chest, "position:y", _rest_position.y - clampf(depth, 0.0, 0.06), 0.13)
	_tween.tween_property(chest, "position:y", _rest_position.y, 0.2)
