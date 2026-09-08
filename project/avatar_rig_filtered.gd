extends Node3D
# Fine-tuned avatar placement = the same "average + nudge" logic, plus:
#   - One Euro filtering of position AND rotation (adaptive: smooth when still, no lag when moving)
#   - eye_offset: a nudge in the HEAD/view frame to cancel the passthrough-camera-vs-eye float
#   - outlier rejection: ignore a rotation that jumps implausibly far in one frame (marker flip)
#   - semi-transparent + optional tint, stays visible through dropouts (holds last pose)
#
# Uses the reusable OneEuroFilter (one_euro_filter.gd). Keeps avatar_rig_6dof.gd untouched.

# Drag aruco_patch0 / 1 / 2 in here. Any number works -- the anchor is their centroid.
# Chest markers: id0 left infraclavicular, id1 lower chest, id2 right infraclavicular.
@export var markers: Array[Node3D] = []
# The XRCamera3D (your eye). Needed to apply eye_offset in the view frame. Optional.
@export var xr_camera: Node3D

@export_group("Placement")
# Nudge from the markers' centroid, in the avatar's own frame (slides it onto the body).
@export var position_offset := Vector3.ZERO
# Fixed twist so the model's axes line up with the markers.
@export var extra_rotation_degrees := Vector3(-90, 0, 0)
# Nudge in the HEAD/view frame (metres) to cancel the camera-vs-eye float. Avatar floats up -> set
# y negative; floats toward/away -> adjust z; left/right -> x. Applied only if xr_camera is set.
@export var eye_offset := Vector3.ZERO

@export_group("One Euro filter")
# Position: lower min_cutoff = smoother when still; higher beta = less lag when moving.
@export var pos_min_cutoff := 1.0
@export var pos_beta := 0.5
# Rotation: same idea, for orientation.
@export var rot_min_cutoff := 1.0
@export var rot_beta := 0.5
# Ignore a rotation that jumps more than this in one frame (a planar-marker flip, not real motion).
@export var max_jump_degrees := 45.0

@export_group("Look")
@export_range(0.0, 0.95, 0.05) var avatar_transparency := 0.6
@export var avatar_tint := Color.WHITE

# Per-marker "have I ever seen this one move" latch, parallel to `markers`.
var _seen: Array[bool] = []
var _last_pos: Array[Vector3] = []
var _placed := false
var _last_rot := Quaternion.IDENTITY

var _pos_filter: OneEuroFilter.Vec3
var _rot_filter: OneEuroFilter.Rotation

func _ready() -> void:
	_pos_filter = OneEuroFilter.Vec3.new(pos_min_cutoff, pos_beta)
	_rot_filter = OneEuroFilter.Rotation.new(rot_min_cutoff, rot_beta)
	_seen.resize(markers.size())
	_last_pos.resize(markers.size())
	_last_pos.fill(Vector3.INF)
	_apply_look(self)

func _apply_look(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(i)
					if mat is BaseMaterial3D:
						var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
						m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						m.albedo_color = Color(avatar_tint.r, avatar_tint.g, avatar_tint.b,
								clampf(1.0 - avatar_transparency, 0.05, 1.0))
						mi.set_surface_override_material(i, m)
		_apply_look(child)

func _process(delta: float) -> void:
	if markers.is_empty():
		return

	# Show once every marker has been seen, then stay visible (hold last pose through dropouts).
	var centre := Vector3.ZERO
	var acc := Quaternion(0, 0, 0, 0)
	var ref: Quaternion = markers[0].global_basis.get_rotation_quaternion()
	var all_seen := true
	for i in markers.size():
		var m := markers[i]
		var p := m.global_position
		if not p.is_equal_approx(_last_pos[i]):
			_seen[i] = true
		_last_pos[i] = p
		if not _seen[i]:
			all_seen = false
		centre += p
		var q: Quaternion = m.global_basis.get_rotation_quaternion()
		# q and -q are the SAME rotation. Without this they would cancel instead of averaging.
		if ref.dot(q) < 0.0:
			q = -q
		acc = Quaternion(acc.x + q.x, acc.y + q.y, acc.z + q.z, acc.w + q.w)
	if not all_seen:
		visible = false
		return
	visible = true
	centre /= float(markers.size())

	# --- target rotation: quaternion mean of all markers + fixed twist ---
	# Sum-then-normalise is the cheap quaternion mean. slerp can't do it: it only takes two, and
	# chaining it isn't associative (the result would depend on marker order).
	var rot_q := (Basis(acc.normalized()) * Basis.from_euler(extra_rotation_degrees * (PI / 180.0))).get_rotation_quaternion()

	# --- outlier rejection: a real body can't swing this far in one frame -> skip (marker flip) ---
	if _placed and rad_to_deg(_last_rot.angle_to(rot_q)) > max_jump_degrees:
		return
	_last_rot = rot_q
	_placed = true

	# --- adaptive filtering (One Euro) ---
	var rot := _rot_filter.filter(rot_q, delta)          # smoothed rotation
	var anchor := _pos_filter.filter(centre, delta)      # smoothed centroid

	# --- place: centroid + body-frame nudge, then the view-frame eye offset ---
	var basis := Basis(rot)
	var pos := anchor + basis * position_offset
	if xr_camera != null:
		pos += xr_camera.global_transform.basis * eye_offset
	global_transform = Transform3D(basis, pos)
