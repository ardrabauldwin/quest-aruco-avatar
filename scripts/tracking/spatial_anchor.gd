class_name NaretSpatialAnchor
extends Node3D
## Floor locking changes displayed model height only, never the marker measurement.
var floor_locked := false
var floor_y := 0.0
## Patient-only floor adjustment; does not move the room or Anna.
var floor_adjustment_m := 0.0
## Explicit correction for a wrong headset floor reference. Old profiles default
## to zero; legacy alignment values must never silently become this correction.
var manual_floor_correction_m := 0.0
## Fingertip-measured floor minus the automatic floor source it was measured
## against ("room_scan" or "local_floor"); applies only while that source is used.
var floor_touch_offset_m := 0.0
var floor_touch_source := ""
## Hand-measured height of the real compression point above the floor
## (NaretChestTouch); 0 = not measured. A mannequin property, so it survives
## other rooms and recentring. Puts the patient's `Sternum` at that height:
## "flatten" scales the body's thickness and keeps its back on the floor,
## "shift" keeps the thickness and lowers the whole body into the floor.
var chest_height_m := 0.0
var chest_fit := "shift"
const CHEST_FITS := ["flatten", "shift"]
var patient_opacity := 0.75
var _floor_vertices := PackedVector3Array()
var _floor_projection := Vector3(INF, INF, INF)
var _floor_offset_y := 0.0
## Places Denis's patient model using the fused chest anchor from marker_layout.gd.
## update_pose() receives room-space anchors, not camera-space marker positions.
##
## Convention (docs/TRACKING.md, "Marker auf dem Brustbein"): the marker lies
## flat on the compression point of the mannequin's sternum, marker +Y is the
## chest normal and marker -Z points to the head. The default offset puts the
## patient's `sternum` on the anchor. Physical model alignment still needs checking.
## A saved calibration (calibration panel) overrides that default.
##
## The marker stays on the chest during CPR: hands cover it and it sinks with
## every compression. Startup uses the settled marker pose. With viewer_head
## configured, subsequent updates pass through the migrated viewer-motion gate.
## Desktop preview uses the same robust startup, then holds until explicit reposition.
## Save offsets, never world anchors.
# MODEL ALIGNMENT: position/rotation (and any existing scale) relative to the
# reconstructed chest anchor. The calibration panel edits this value directly.
# This is different from marker-to-common offsets in marker_layout.gd.
@export var marker_to_mannequin := Transform3D.IDENTITY
# user:// is the app's writable data directory, including on the headset.
@export var calibration_file := "user://calibration.cfg"
## Main scene uses patient-style anchors. False retains the historical API for
## stand-alone/legacy scenes; saved alignments carry their convention explicitly.
@export var patient_anchor_axes := false
# Used only for the default sternum offset, not added again to saved calibration.
@export var marker_thickness_m := 0.002
# Model-only orientation adjustment. Keep marker fusion and its gravity axes intact.
# The scene sets this to correct the observed face-down/head-to-feet reversal.
@export var default_model_rotation_degrees := Vector3.ZERO
# Latest input may be noisy. locked_pose is the accepted/filtered anchor instead.
var last_marker_pose := Transform3D.IDENTITY
var has_marker_pose := false
var calibrated := false # Saved model alignment exists; does not prove accuracy.
var locked := false # Initial placement accepted; later gate-approved updates can occur.
var locked_pose := Transform3D.IDENTITY
var viewer_head: Node3D
var full_marker_evidence := true
var viewer_gate := NaretViewerMotionGate.new()
var _viewer_filter: RefCounted
var _viewer_rest_pose := Transform3D.IDENTITY
var _viewer_last_ms := -1
var _tracking_audit_last_ms := -10000
var startup := NaretStartupPlacement.new()
var _floor_audit_s := 0.0

func _process(delta: float) -> void:
	_floor_audit_s += delta
	if locked and _floor_audit_s >= 5.0:
		_floor_audit_s = 0.0
		print("NARET_FLOOR_AUDIT locked=", floor_locked, " calibrated=", calibrated,
			" floor_y=", floor_y, " root_y=", global_position.y,
			" resting_offset=", _floor_offset_y, " resting_bottom=", global_position.y + _floor_offset_y,
			" saved_adjustment=", floor_adjustment_m, " cached_vertices=", _floor_vertices.size())
	# Rendering runs faster than marker detection. Update head-motion classification
	# every frame, but collect placement samples only when update_pose() is called.
	if viewer_head != null:
		var patient := get_node_or_null("Mannequin") as Node3D
		if patient != null:
			patient.visible = locked
		viewer_gate.head = viewer_head
		viewer_gate.tick(delta)

func _ready() -> void:
	# Saved alignment wins. Without it, start with the model's sternum-node offset.
	load_calibration()
	if not calibrated:
		marker_to_mannequin = sternum_offset()

func body_changed() -> void:
	## The patient's mesh moved inside the anchor (sternum landmark offset):
	## measure its floor contact again.
	_floor_vertices.clear()
	_floor_projection = Vector3(INF, INF, INF)
	refresh()

func sternum_offset() -> Transform3D:
	## Marker frame = patient frame moved onto the sternum surface (+ marker thickness).
	# Locate the model's sternum relative to this anchor node, then move the model
	# by the opposite amount. This places its sternum at the supplied chest anchor.
	# It is a model-based starting estimate, not a measurement of the real mannequin.
	var mannequin := get_node_or_null("Mannequin")
	var sternum: Node3D = mannequin.get("sternum") if mannequin else null
	if sternum == null:
		return Transform3D.IDENTITY
	var point: Vector3 = mannequin.transform * sternum.position
	# Current scene assumption: sternum.position is expressed in mannequin space.
	# If the model hierarchy changes, this coordinate relationship must be reviewed.
	var rotation := Basis.from_euler(default_model_rotation_degrees * (PI / 180.0))
	# Rotate about the chest landmark, not the model origin: R*point + offset
	# stays at -marker_thickness_m on the anchor's vertical axis.
	# Preserve the previous world-space 2 mm placement when changing the anchor
	# convention; the old anchor's +Y pointed down before the model's 180° flip.
	var thickness_axis := Vector3.DOWN if patient_anchor_axes else Vector3.UP
	return Transform3D(rotation, -(rotation * point + thickness_axis * marker_thickness_m))

func update_pose(pose: Transform3D, now_ms := -1) -> void:
	# Shared robust startup. Only the headset has a tracked viewer for motion gating.
	if not pose.is_finite():
		return
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	last_marker_pose = pose
	has_marker_pose = true
	if not locked:
		# Desktop may preview the incoming pose while collecting the same startup samples.
		if viewer_head == null:
			_apply(pose)
		# First placement: collect robust estimates before showing the patient.
		var initial := startup.observe(pose, now)
		if initial.is_empty():
			return
		locked_pose = initial.pose
		# Store the room-space anchor separately from the model alignment offset.
		locked = true
		_apply(locked_pose)
		if floor_locked:
			print("NARET_FLOOR reference_y=%.3f model_root_y=%.3f resting_bottom_y=%.3f" % [floor_y, global_position.y, global_position.y + _floor_offset_y])
		print("Startup placement: %d readings, fallback=%s" % [initial.samples, initial.fallback])
		return
	if viewer_head != null and locked:
		_update_headset_pose(pose, now)
		return
	# Without a tracked viewer, hold the accepted anchor until unlock() is requested.

func _update_headset_pose(pose: Transform3D, now: int) -> void:
	# Once placed: ignore repeated results, ask the gate, then smooth accepted targets.
	if now <= _viewer_last_ms:
		return
	var elapsed := clampf(float(now - _viewer_last_ms) / 1000.0, 0.001, 0.25) if _viewer_last_ms >= 0 else 0.1
	# The filter uses elapsed seconds. Clamp long detection gaps; a first update
	# uses 0.1 s because there is no previous detection time to subtract.
	_viewer_last_ms = now
	viewer_gate.head = viewer_head
	var result := viewer_gate.evaluate(pose, locked_pose, now, full_marker_evidence)
	var audit := now - _tracking_audit_last_ms >= 1000
	if audit:
		_tracking_audit_last_ms = now
		print("NARET_POSE_GATE state=", viewer_gate.gate_state,
			" full=", full_marker_evidence, " moving=", viewer_gate.moving,
			" raw_delta_m=", pose.origin.distance_to(locked_pose.origin),
			" accepted=", not result.is_empty())
	if result.is_empty():
		# HOLD: leave both the patient transform and accepted anchor unchanged.
		return
	var corrected: Transform3D = result.pose
	# Height stays at the startup anchor height; this is not snapping the mesh to floor.
	corrected.origin.y = locked_pose.origin.y
	if _viewer_filter == null:
		# Start smoothing from the current accepted placement, preventing a reset jump.
		_viewer_filter = load("res://addons/naret_upstream/avatar/simple_pose_stabilizer.gd").new()
		# Restore avatar_rig_navel.gd's tuned settings instead of generic defaults.
		_viewer_filter.call("configure", 5, 0.020, 0.3, 1.2, 2.0, 0.0015, 1.0, 3, 0.080, 8.0)
		_viewer_rest_pose = locked_pose
		_viewer_filter.call("anchor_at", locked_pose)
	corrected = _viewer_filter.call("update", corrected, elapsed, now, _viewer_rest_pose, true)
	# Adopt stable endpoints independently, matching navel_provider.gd.
	var target: Transform3D = _viewer_filter.call("measurement_target")
	if _viewer_filter.call("position_reanchor_ready"):
		_viewer_rest_pose.origin = target.origin
	if _viewer_filter.call("rotation_reanchor_ready"):
		_viewer_rest_pose.basis = target.basis
	if audit:
		print("NARET_POSE_UPDATE position_step_m=", corrected.origin.distance_to(locked_pose.origin),
			" rotation_step_deg=", rad_to_deg(corrected.basis.get_rotation_quaternion().angle_to(locked_pose.basis.get_rotation_quaternion())))
	locked_pose = corrected
	_apply(corrected)
	return

func marker_pose() -> Transform3D:
	# Despite the historical method name, this returns the reconstructed chest
	# anchor, not an individual marker's camera-space pose.
	return locked_pose if locked else last_marker_pose

func refresh() -> void:
	## Re-applies the offset, e.g. while the calibration panel edits it.
	if has_marker_pose:
		_apply(marker_pose())

func unlock() -> void:
	# Explicit reposition: collect a fresh startup pose and discard old gate bias
	# and smoothing history. Keep the model-specific calibration offset unchanged.
	startup = NaretStartupPlacement.new()
	viewer_gate = NaretViewerMotionGate.new()
	_viewer_filter = null
	_viewer_last_ms = -1
	locked = false
	refresh()

func calibrate(mannequin_world_pose: Transform3D) -> Error:
	# Convert the desired model placement into an offset relative to the anchor.
	# Saving a room position would fail when the mannequin moves or tracking recentres.
	if not has_marker_pose:
		return ERR_UNAVAILABLE
	marker_to_mannequin = marker_pose().affine_inverse() * mannequin_world_pose
	# Algebra: anchor_world * model_offset = desired_model_world.
	# Therefore model_offset = inverse(anchor_world) * desired_model_world.
	calibrated = true
	refresh()
	return save_calibration()

func save_calibration() -> Error:
	var config := ConfigFile.new()
	# Marker size/id share the profile; preserve their section on every offset save.
	config.load(calibration_file)
	config.set_value("calibration", "version", 1)
	config.set_value("calibration", "alignment_frame", "patient_y_up" if patient_anchor_axes else "legacy_anchor")
	config.set_value("calibration", "marker_to_mannequin", marker_to_mannequin)
	config.set_value("calibration", "calibrated", calibrated)
	config.set_value("calibration", "floor_adjustment_m", floor_adjustment_m)
	config.set_value("calibration", "manual_floor_correction_m", manual_floor_correction_m)
	config.set_value("calibration", "floor_touch_offset_m", floor_touch_offset_m)
	config.set_value("calibration", "floor_touch_source", floor_touch_source)
	config.set_value("calibration", "chest_height_m", chest_height_m)
	config.set_value("calibration", "chest_fit", chest_fit)
	config.set_value("calibration", "marker_height_lock", true)
	config.set_value("calibration", "patient_opacity", patient_opacity)
	var result := config.save(calibration_file)
	if result != OK:
		# Start must not accept an alignment that could not be persisted.
		calibrated = false
	return result

func load_calibration() -> Error:
	# Retain the existing version-1 keys so older saved offsets remain readable.
	# Scale is allowed here: model calibration is not restricted to rigid marker poses.
	var config := ConfigFile.new()
	var result := config.load(calibration_file)
	if result != OK:
		return result
	var pose: Variant = config.get_value("calibration", "marker_to_mannequin", Transform3D.IDENTITY)
	if not pose is Transform3D or not pose.is_finite() or absf(pose.basis.determinant()) < 0.01:
		return ERR_INVALID_DATA
	var frame := str(config.get_value("calibration", "alignment_frame", "legacy_anchor"))
	if frame not in ["legacy_anchor", "patient_y_up"]:
		return ERR_INVALID_DATA
	if (frame == "patient_y_up") != patient_anchor_axes:
		# The anchor rotates 180°; left-rotate its model offset by the inverse
		# (the same exact rotation). Their world-space product is unchanged.
		pose = NaretMarkerLayout.LEGACY_ANCHOR_FLIP * (pose as Transform3D)
	marker_to_mannequin = pose
	calibrated = bool(config.get_value("calibration", "calibrated", false))
	floor_adjustment_m = clampf(float(config.get_value("calibration", "floor_adjustment_m", 0.0)), -0.3, 0.3)
	manual_floor_correction_m = clampf(float(config.get_value("calibration", "manual_floor_correction_m", 0.0)), -1.5, 1.5)
	floor_touch_offset_m = clampf(float(config.get_value("calibration", "floor_touch_offset_m", 0.0)), -0.3, 0.3)
	floor_touch_source = str(config.get_value("calibration", "floor_touch_source", ""))
	chest_height_m = clampf(float(config.get_value("calibration", "chest_height_m", 0.0)), 0.0, 0.5)
	# Lowering looked better on the real mannequin than flattening (deformed feet).
	chest_fit = str(config.get_value("calibration", "chest_fit", "shift"))
	if chest_fit not in CHEST_FITS:
		chest_fit = "shift"	# Preserve the explicitly saved vertical adjustment in older profiles too.
	# Dropping it silently raises a patient that the user previously nudged down.
	patient_opacity = clampf(float(config.get_value("calibration", "patient_opacity", 0.75)), 0.0, 1.0)
	return OK

func reset_calibration() -> void:
	# Reset deliberately persists the default with calibrated=false. It does not
	# reset marker layout calibration, nor does it establish a new startup anchor.
	marker_to_mannequin = sternum_offset()
	calibrated = false
	refresh()
	save_calibration()

func _apply(pose: Transform3D) -> void:
	var old_pos := global_position
	# Room-space anchor multiplied by model-local alignment = patient world pose.
	global_transform = pose * marker_to_mannequin
	if floor_locked:
		if calibrated:
			global_position.y += floor_adjustment_m
		# Active floor lock determines vertical placement, including calibrated
		# models. Keep the saved X/Z, rotation and scale; do not rewrite the file.
		_snap_to_floor()
	if old_pos.distance_to(global_position) > 0.02:
		# A position change over 2 cm resets an active physics body to its skeleton.
		# This is physics cleanup, not a marker-acceptance threshold.
		var mannequin = get_node_or_null("Mannequin")
		if mannequin and mannequin.get("ragdoll") and mannequin.ragdoll.is_active():
			mannequin.ragdoll.reset_to_skeleton()

func _snap_to_floor() -> void:
	# Cache the neutral mesh vertices in anchor-local coordinates. Only the patient
	# participates: UI, hands and room geometry must never determine its height.
	if _floor_vertices.is_empty():
		var model := get_node_or_null("Mannequin/Model")
		if model == null:
			return
		for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
			var instance := mesh_node as MeshInstance3D
			if instance.mesh == null:
				continue
			var local := global_transform.affine_inverse() * instance.global_transform
			for surface in instance.mesh.get_surface_count():
				var vertices := posed_vertices(instance, surface)
				for vertex in vertices:
					_floor_vertices.append(local * vertex)
	# X/Z translation and world yaw leave this vertical projection unchanged.
	# Re-scan the cached vertices only for pitch/roll/scale edits, not every frame
	# while the controller is nudging or marker measurements are arriving.
	var projection := Vector3(global_basis.x.y, global_basis.y.y, global_basis.z.y)
	if not projection.is_equal_approx(_floor_projection):
		_floor_projection = projection
		_floor_offset_y = INF
		for vertex in _floor_vertices:
			_floor_offset_y = minf(_floor_offset_y, projection.dot(vertex))
	if not is_finite(_floor_offset_y):
		return
	var contact_y := floor_y - _floor_offset_y
	var mannequin := get_node_or_null("Mannequin")
	var sternum: Node3D = mannequin.get("sternum") if mannequin else null
	var measured := chest_height_m > 0.0 and sternum != null
	# Height of the patient's sternum above its own lowest point, as placed now.
	var sternum_y := projection.dot(mannequin.transform * sternum.position) if sternum else 0.0
	var rise := sternum_y - _floor_offset_y
	var flatten := measured and chest_fit == "flatten" and rise > 0.01
	# Lowest point and sternum scale together, so the ratio gives the thickness.
	# A changed body drops the vertex cache; the second pass measures it anew.
	var thickness := clampf(float(mannequin.get("thickness")) * chest_height_m / rise, 0.4, 1.2) if flatten else 1.0
	if _set_thickness(thickness):
		_snap_to_floor()
		return
	if not measured:
		global_position.y = contact_y + maxf(floor_adjustment_m, 0.0) + manual_floor_correction_m
	elif flatten:
		global_position.y = contact_y + manual_floor_correction_m
	else:
		global_position.y = floor_y + chest_height_m - sternum_y + manual_floor_correction_m

func _set_thickness(value: float) -> bool:
	## True when the body changed, so the cached floor vertices were dropped.
	var mannequin := get_node_or_null("Mannequin")
	if mannequin == null or not mannequin.has_method("set_thickness") or absf(float(mannequin.get("thickness")) - value) < 0.003:
		return false
	mannequin.call("set_thickness", value)
	_floor_vertices.clear()
	_floor_projection = Vector3(INF, INF, INF)
	return true

static func posed_vertices(instance: MeshInstance3D, surface: int) -> PackedVector3Array:
	# Raw GLB vertices describe the bind pose, not necessarily the visible body.
	# Apply the same weighted bone transforms as the renderer, once for the resting
	# floor-contact cache. CPU calculation also works in headless regression tests.
	var arrays := instance.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
	if instance.skin == null or skeleton == null or arrays[Mesh.ARRAY_BONES] == null:
		return vertices
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if vertices.is_empty() or weights.is_empty():
		return vertices
	var transforms: Array[Transform3D] = []
	var skeleton_to_mesh := instance.global_transform.affine_inverse() * skeleton.global_transform
	for bind in instance.skin.get_bind_count():
		var bone := instance.skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(instance.skin.get_bind_name(bind))
		transforms.append(skeleton_to_mesh * skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
	var influences := bones.size() / vertices.size()
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for i in vertices.size():
		var point := Vector3.ZERO
		for j in influences:
			var index := i * influences + j
			if weights[index] > 0.0:
				point += (transforms[bones[index]] * vertices[i]) * weights[index]
		result[i] = point
	return result

func nudge_world(displacement: Vector3, yaw_radians: float) -> void:
	# Store manual alignment relative to the measured anchor, never in room space.
	# Translation is horizontal; yaw pivots about the chest, preserving model scale.
	if not locked:
		return
	displacement.y = 0.0
	var alignment := locked_pose * marker_to_mannequin
	alignment.origin += displacement
	var rotation := Basis(Vector3.UP, yaw_radians)
	alignment.origin = locked_pose.origin + rotation * (alignment.origin - locked_pose.origin)
	alignment.basis = rotation * alignment.basis
	marker_to_mannequin = locked_pose.affine_inverse() * alignment
	refresh()


func adjust_patient_height(metres: float) -> void:
	## Preview only. Tracking, room coordinates and model alignment stay unchanged.
	if not locked:
		return
	manual_floor_correction_m = clampf(manual_floor_correction_m + metres, -1.5, 1.5)
	refresh()
