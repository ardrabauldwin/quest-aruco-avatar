extends Node3D
## Records when this marker node receives a detected pose.
##
## main_3d.gd already assigns global_transform whenever OpenCV returns this
## marker. 
var _armed := false


func _ready() -> void:
	set_notify_transform(true)
	# Ignore transforms caused by initial scene setup and reparenting.
	get_tree().process_frame.connect(_arm, CONNECT_ONE_SHOT)


func _arm() -> void:
	_armed = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _armed:
		set_meta("last_detected_ms", Time.get_ticks_msec())
