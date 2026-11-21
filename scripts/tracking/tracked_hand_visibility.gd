extends XRNode3D
## Keep the tracked-hand root visible only while Quest reports valid hand tracking.
## The mesh child retains its separate user-controlled visibility toggle.
func _process(_delta: float) -> void:
	var hand := XRServer.get_tracker(tracker) as XRHandTracker
	visible = hand != null and hand.has_tracking_data
