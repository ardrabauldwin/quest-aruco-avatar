extends Node3D
## Places the avatar using one fused 6DOF pose for ID0 common.
##
## Marker names:
##   aruco_patch0 = common (the final target)
##   aruco_patch1 = chest
##   aruco_patch2 = torso

@export var common_marker: Node3D # aruco_patch0
@export var chest_marker: Node3D # aruco_patch1
@export var torso_marker: Node3D # aruco_patch2

@export_group("Look")
@export_range(0.0, 0.95, 0.05) var avatar_transparency := 0.6
@export var avatar_tint := Color.WHITE

@export_group("Calibration")
@export var xr_controller_right: XRController3D
## Right B. Full recalibration: relearns every marker offset AND the body's orientation, from
## this single frame. Convenient, but one frame from one viewpoint is the worst way to learn an
## offset - on 3 August it produced an ID2 offset 16.5 mm longer than the tape. Prefer recording
## a walk and generating the file with make_calibration.py, and keep this for emergencies.
@export var calibrate_button := "by_button"
## Right thumbstick pressed in. Records only which way the body is facing, leaving the marker
## offsets alone.
##
## This is the one to use after the mannequin is turned, or after the headset view is recentred -
## both make the stored orientation stale while leaving the offsets perfectly valid. A full
## recalibration would fix the orientation too, but at the price of replacing offsets averaged
## over a whole walk with a single frame's guess.
##
## A thumbstick click, not the grip: on Touch controllers the grip is an analog squeeze that the
## runtime has to threshold into a press, whereas the thumbstick is a real switch. Pressing the
## stick in does not disturb nudging, which reads the stick's direction rather than its click.
@export var relevel_button := "primary_click"

@export_group("Live tuning")
@export var enable_nudge := true
@export var target: Node3D
@export var nudge_speed := 0.05
@export var xr_controller_left: XRController3D

@export_group("Smoothing")
@export_range(0.05, 1.0, 0.05) var smoothing := 1.0

## How much of the body's rotation to measure. Measuring an angle that cannot change adds only
## that angle's noise, and rotation noise is expensive: the avatar reaches over a metre from ID0,
## so a degree of rotation error is about 30 mm at the head and feet against 7 mm of position
## error. Measured on the 3 August recordings, with nothing moving:
##
##     0 Measure all         4.07 deg, ~120 mm at the extremities, worse the more the head moved
##     1 Hold calibrated     0    deg,    0 mm, but needs a button press after the body is turned
##     2 Hold and follow     0    deg,    0 mm, and picks up a real move by itself
##
## "Hold and follow" is the default and wants no maintenance: it hands back the held rotation, and
## only adopts a new one once the measured rotation has stayed more than 15 degrees away for 0.7
## seconds. Noise is a few degrees and laying the mannequin down or turning it is tens, so the two
## never get confused. It follows tilt as well as yaw, so sitting the mannequin up or laying it
## flat needs no button.
##
## A yaw-only setting used to sit at 1, at 1.20 deg. It is gone: one axis cannot tell what the
## mannequin is doing, because laying it down is about 90 degrees of TILT and almost no yaw.
##
## All three still FOLLOW the mannequin's position, which is always measured live. What differs is
## only whether the avatar can turn on its own.
@export_group("Body orientation")
# No comma in the last label: @export_enum splits its arguments on commas, so one inside a name
# is read as an extra argument and refuses to parse.
@export_enum("Measure all:0", "Hold calibrated:1", "Hold and follow:2")
var rotation_mode := 2

## PoseStabilizer settings. Exported so they can be changed from the inspector - including
## live over the remote debugger - instead of editing the filter and redeploying.
##
## Tuning order: window first (raise until bad jumps stop), then the dead zones (set just
## above the measured stationary p95), then smoothing time (raise until still, lower until
## motion is not laggy).
@export_group("Filter")
## Poses compared when picking the medoid. Bigger rejects longer runs of bad detections,
## but adds lag: at ~8 detections/sec a window of 5 is about 0.6 seconds of history.
@export_range(1, 15, 1) var filter_window := 5
## Position changes below this are HELD, not smoothed - the pose does not move at all until the
## change exceeds it. Left at zero deliberately. The fused pose carries about 7 mm of noise, so a
## 3 mm dead zone made it sit still, jump, and sit still again, which reads as jitter far more
## than the smooth drift it replaced. Raise it only if a real threshold is wanted, never as a
## noise cure - smoothing is what removes noise.
@export_range(0.0, 0.05, 0.001) var filter_position_dead_zone_m := 0.0
## Rotation changes below this are held. Irrelevant while the body's rotation is held anyway.
@export_range(0.0, 10.0, 0.1) var filter_rotation_dead_zone_deg := 0.0
## Seconds to ease toward a new pose. 0 snaps straight to the medoid.
##
## Set from what the mannequin actually does: it stays where it is put, so lag costs nothing and
## the only reason not to smooth harder is how quickly the avatar should catch up after the
## mannequin is nudged. Measured on the 3 August recordings, the avatar's frame-to-frame movement
## with the markers stationary was 2.46 mm at 0.15 s and 0.72 mm at 0.5 s.
@export_range(0.0, 2.0, 0.01) var filter_smoothing_time_s := 0.5

const SAVE_PATH := "user://navel_calibration.cfg"

var _common_provider := CommonPoseProvider.new()
var _filter := SimplePoseStabilizer.new()
# Last values handed to configure(), so inspector edits can be picked up while running.
var _filter_settings := []
var _fresh := MarkerFreshness.new()
var _markers: Array = []
var _visible_now: Array = []
var _placed := false
var _was_nudging := false


func _ready() -> void:
	_markers = [common_marker, chest_marker, torso_marker]
	_apply_filter_settings()
	_apply_look()
	# Connected before loading, so an old file with no stored orientation settles one from the first
	# second of detections and then WRITES it - otherwise every launch would re-learn it.
	_common_provider.orientation_settled.connect(_on_orientation_settled)
	if _common_provider.load_from(SAVE_PATH, _markers):
		print("Common pose: calibration loaded from disk.")
	if xr_controller_right != null:
		xr_controller_right.button_pressed.connect(_on_button)


func _process(delta: float) -> void:
	_apply_filter_settings()
	# Read every frame, not once in _ready, so the mode can be changed live from the inspector
	# over the remote debugger to compare the three settings against each other.
	_common_provider.rotation_mode = rotation_mode

	_visible_now = []
	for marker in _markers:
		if _fresh.age_ms(marker) <= _fresh.freeze_after_ms:
			_visible_now.append(marker)

	var raw_common_pose := _common_provider.get_pose(_visible_now)
	var common_pose := raw_common_pose
	if _common_provider.is_ready():
		# Hand the stabilizer the newest detection time so it takes ONE sample per detection.
		# The render loop runs about nine times faster than OpenCV, so without this the medoid
		# window would fill with copies of a single detection and the smoothing time would mean
		# nothing - a window of 5 would span 70 ms instead of 600.
		var newest_detection_ms := -1
		for marker in _visible_now:
			newest_detection_ms = maxi(
				newest_detection_ms,
				int(marker.get_meta("last_detected_ms", -1))
			)
		common_pose = _filter.update(raw_common_pose, delta, newest_detection_ms)

	visible = _filter.is_ready()
	if visible:
		if _placed:
			global_transform = global_transform.interpolate_with(
				common_pose,
				smoothing
			)
		else:
			global_transform = common_pose
			_placed = true

	if enable_nudge and target != null:
		var nudge := _read_nudge(delta)
		if nudge != Vector3.ZERO:
			target.position += nudge
			_was_nudging = true
		elif _was_nudging:
			print("Final mannequin offset: ", target.position)
			_was_nudging = false


## Pushes the exported values into the stabilizer, but only when one of them actually
## changed - configure() resets the filter, so calling it every frame would keep the medoid
## window permanently empty and the avatar would never appear.
func _apply_filter_settings() -> void:
	var current := [
		filter_window,
		filter_position_dead_zone_m,
		filter_rotation_dead_zone_deg,
		filter_smoothing_time_s,
	]
	if current == _filter_settings:
		return
	_filter_settings = current
	_filter.configure(
		filter_window,
		filter_position_dead_zone_m,
		filter_rotation_dead_zone_deg,
		filter_smoothing_time_s
	)
	_placed = false
	# Printed on every change, so the log always says which filter is running and with what.
	# Several stabilizers exist in this project and they are easy to confuse from the outside.
	# Ask the filter what it is rather than writing the name here: this line existed saying
	# "PoseStabilizer" for a while after the rig had been switched to a different one.
	print("FILTER: %s  window=%d  dead_zone=%.3f m / %.1f deg  smoothing=%.2f s" % [
		_filter.get_script().resource_path.get_file().get_basename(),
		filter_window,
		filter_position_dead_zone_m,
		filter_rotation_dead_zone_deg,
		filter_smoothing_time_s,
	])


func _on_button(button_name: String) -> void:
	# Printed for every press, not only the ones that do something. Without this, a button that
	# does nothing is indistinguishable from a button whose event never arrived, and the two have
	# completely different causes - a wrong action name against the app not having input focus.
	print("Right controller: ", button_name)
	if button_name != calibrate_button and button_name != relevel_button:
		return
	# Both read ID0's pose directly, so neither can run without ID0 in view.
	if not _visible_now.has(common_marker):
		print("Common pose: calibration needs ID0 common visible.")
		return

	if button_name == relevel_button:
		# Nothing is saved here: the orientation is not known yet. The provider spends the next
		# second averaging detections and then emits, and _on_orientation_settled writes it.
		_common_provider.recalibrate_orientation()
		print("Common pose: re-levelling; averaging one second of detections.")
	else:
		_common_provider.calibrate(
			_visible_now,
			common_marker.global_transform
		)
		_common_provider.save_to(SAVE_PATH)
		print("Common pose: recalibrated %d marker(s) and saved." % _visible_now.size())

	# The filter's history describes the pose as it was before this change, so keeping it would
	# make the avatar crawl from the old answer to the new one over the smoothing time.
	_filter.reset()
	_placed = false


## A held orientation finished settling - on the first detections after launch, after a re-level,
## or because the mannequin was actually turned. All three want the same two things.
func _on_orientation_settled() -> void:
	# Saved every time, including the ones nobody asked for. The launch-time case is the important
	# one: it is what upgrades a calibration file written before the orientation was stored, so the
	# second of settling happens once ever rather than on every launch.
	_common_provider.save_to(SAVE_PATH)
	# The orientation changes in one step here, so the filter's history is describing a pose that no
	# longer exists.
	_filter.reset()
	_placed = false
	print("Common pose: orientation settled and saved.")


func _read_nudge(delta: float) -> Vector3:
	var direction := Vector3.ZERO
	if xr_controller_left != null:
		var left_stick: Vector2 = xr_controller_left.get_vector2("primary")
		direction.x += left_stick.x
		direction.y += left_stick.y
	if xr_controller_right != null:
		direction.z += -xr_controller_right.get_vector2("primary").y
	return direction * nudge_speed * delta


func _apply_look() -> void:
	var alpha := clampf(1.0 - avatar_transparency, 0.05, 1.0)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_active_material(surface)
			if material is BaseMaterial3D:
				var copy := material.duplicate() as BaseMaterial3D
				copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				copy.albedo_color = Color(avatar_tint, alpha)
				mesh_instance.set_surface_override_material(surface, copy)
