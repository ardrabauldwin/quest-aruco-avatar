extends "res://avatar_rig_navel.gd"
## Alternative tracking policy for AvatarRig.
##
## This inherits all calibration, persistence, appearance, and controller-tuning
## behavior from avatar_rig_navel.gd. The only difference is marker loss:
##
##   common + chest visible -> update the navel pose from both markers
##   either marker missing -> hold the avatar's last displayed pose
##
## The original avatar_rig_navel.gd remains unchanged and can still be selected
## on AvatarRig in the Inspector.

@export_group("Both-marker tracking")
## Detection runs at about 10 Hz and can miss individual frames. Give each marker
## enough time to overlap with the other marker's most recent detection.
@export_range(300, 2000, 100) var both_marker_timeout_ms := 1000


func _ready() -> void:
	super()
	_fresh.tracking_loss_timeout_ms = both_marker_timeout_ms


func _process(delta: float) -> void:
	# Sense which markers have received a recent detection.
	_visible_now = []
	for marker in _markers:
		if _fresh.age_ms(marker) <= _fresh.tracking_loss_timeout_ms:
			_visible_now.append(marker)

	var both_tracking := (
		_visible_now.has(common_marker)
		and _visible_now.has(chest_marker)
	)

	# Update only from a complete common-and-chest observation. When either
	# marker is missing, do not alter global_transform: the avatar stays
	# exactly at its last displayed pose.
	if both_tracking:
		var pose := _common_provider.get_pose([common_marker, chest_marker])
		visible = _common_provider.is_ready()
		if visible:
			global_transform = pose
	else:
		visible = _common_provider.is_ready()

	# Preserve the original optional controller tuning behavior.
	if enable_nudge and target != null:
		var nudge := _read_nudge(delta)
		if nudge != Vector3.ZERO:
			target.position += nudge
