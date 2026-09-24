extends SceneTree

const Rig = preload("res://avatar_rig_navel.gd")
const SAVE_TEST_PATH := "res://../builds/test_manual_yaw.cfg"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var rig = Rig.new()
	var avatar := Node3D.new()
	avatar.name = "mannequin"
	rig.add_child(avatar)
	rig.target = avatar
	rig.enable_nudge = true
	avatar.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled_local(Vector3(0.687, 0.705, 0.668)), Vector3(0.066, -0.024, 0.531))
	var zone := Node3D.new()
	zone.name = "CPRHandZone"
	zone.position = Vector3(0, 0.127, 0.12)
	avatar.add_child(zone)
	var contact := Node3D.new()
	contact.name = "CollisionShape3D"
	contact.position = Vector3(0, -0.06817, 0)
	zone.add_child(contact)
	var pivot_local := zone.transform * contact.position
	rig._apply_manual_nudge(Vector3(0.01, -0.02, 0.03))
	var original := avatar.transform
	var pivot := original * pivot_local
	var scale_before := avatar.basis.get_scale()
	var floor_basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	var sample := Vector3(0.1, 0.2, -0.3)
	var height_before := (floor_basis * (original * sample)).y
	for i in 60:
		rig._apply_manual_yaw(deg_to_rad(0.1))
	assert((avatar.transform * pivot_local).is_equal_approx(pivot), "Yaw must keep the nudged chest fixed")
	assert(avatar.basis.get_scale().is_equal_approx(scale_before), "Yaw must preserve all three scale components")
	assert(is_equal_approx((floor_basis * (avatar.transform * sample)).y, height_before), "Yaw must not tilt or lift the model")
	assert(is_equal_approx(rig.manual_yaw_degrees(), 6.0))
	assert(rig._save_manual_yaw(SAVE_TEST_PATH) == OK)
	assert(is_equal_approx(rig._load_manual_yaw(SAVE_TEST_PATH), 6.0), "Selected angle survives restart")
	DirAccess.remove_absolute(SAVE_TEST_PATH)
	rig._apply_manual_yaw(deg_to_rad(-6.0))
	assert(avatar.transform.is_equal_approx(original), "Opposite correction must restore the original transform")
	var trackers: Array[XRControllerTracker] = []
	var controllers: Array[XRController3D] = []
	for side in ["left", "right"]:
		var tracker := XRControllerTracker.new()
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.name = StringName("yaw_test_" + side)
		XRServer.add_tracker(tracker)
		var controller := XRController3D.new()
		controller.tracker = tracker.name
		root.add_child(controller)
		trackers.append(tracker)
		controllers.append(controller)
	rig.xr_controller_left = controllers[0]
	rig.xr_controller_right = controllers[1]
	trackers[1].set_input("primary", Vector2(0.1, 0))
	assert(is_zero_approx(rig._read_yaw(0.1)), "Stick drift must not rotate")
	trackers[0].set_input("primary", Vector2(1, 1))
	trackers[1].set_input("primary", Vector2(1, 1))
	assert(rig._read_nudge(0.1).is_equal_approx(Vector3(0.005, 0.005, -0.005)), "Existing position controls must survive")
	trackers[0].set_input("primary", Vector2.ZERO)
	trackers[1].set_input("primary", Vector2(1, 0))
	rig.gate_state = "hold_moving"
	rig._update_nudge(0.1)
	assert(is_equal_approx(rig.manual_yaw_degrees(), -1.0), "Right stick rotates at 10 degrees/s even while marker pose is held")
	assert((avatar.transform * pivot_local).is_equal_approx(pivot))
	# Marker updates move the parent; the manual correction must remain on the child.
	var corrected := avatar.transform
	rig._apply_filtered_pose(Transform3D(floor_basis, Vector3(2, 0, 3)))
	assert(avatar.transform.is_equal_approx(corrected))
	for controller in controllers:
		controller.free()
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	rig.free()
	print("manual yaw tests: PASS (pivot, scale, height, persistence, controls, marker updates)")
	quit()
