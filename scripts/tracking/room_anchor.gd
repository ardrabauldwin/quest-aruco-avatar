extends Node3D
## One invisible node per scanned room anchor. OpenXRFbSceneManager skips every
## entity it has no scene for, so NaReT must hand it something even though it only
## reads the pose; drawing the room would hide the real one behind passthrough.

func setup_scene(_entity: Object) -> void:
	pass
