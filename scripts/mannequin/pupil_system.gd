class_name NaretPupils
extends Node3D
## Pupil dilation overlay. The spheres are reparented onto the eye bones by the
## mannequin, so they follow gaze; this node keeps driving their size.

var dilation := 1.0
var _target := 1.0
var _pupils: Array[Node3D] = []

func _ready() -> void:
	for child in get_children():
		if child is Node3D:
			_pupils.append(child)

func set_dilation(value: float) -> void:
	_target = clampf(value, 0.25, 1.0)

func _process(delta: float) -> void:
	dilation = move_toward(dilation, _target, delta * 0.4)
	for pupil: Node3D in _pupils:
		if is_instance_valid(pupil):
			# Uniform: once parented to a rotating eye, no axis is reliably "flat".
			pupil.scale = Vector3.ONE * dilation
