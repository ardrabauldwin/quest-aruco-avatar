class_name NaretMannequin
extends Node3D

@onready var heart: NaretHeart = $Heart
@onready var pupils: NaretPupils = $Pupils
@onready var breathing: NaretBreathing = $Breathing
@onready var sternum: Marker3D = $Sternum
## Authored body-coordinate datum for footprints, AED pads and thickness. It is
## distinct from the patient pivot, which now coincides with the sternum.
@onready var body_frame: Marker3D = $BodyFrame
@onready var zone: MeshInstance3D = $Sternum/Highlight
var _rig: NaretRigAnimator
var ragdoll: NaretRagdoll
var _recovered := false
var _breath_clock := 0.0
## Chest depression of the human_patient.glb compression morph at weight 1.0
## (field re-centred on the ERC compression point, commit 294275d).
const MORPH_DEPTH_M := 0.0277
var _current_compression := 0.0
var _target_compression := 0.0
var _zone_rest_position := Vector3.ZERO
var _recoil_tween: Tween
var _skin: Array[StandardMaterial3D] = []
var _pallor := 1.0
var _metronome := 0.0
## Cardiac arrest drains colour from the skin: grey-blue, like the real thing,
## warming back up after ROSC. Multiplies the diffuse texture.
const PALLOR := Color(0.78, 0.8, 0.9)
const GLOW := Color("80a8ff")
const WRONG := Color("d11909")
## Head tilt (airway opening, ERC "head tilt – chin lift"): extension in degrees
## on neck and head, eased in and out.
# Conservative visual prototype: about 20 degrees combined, not measured technique.
const TILT := {"neck_01": 10.0, "head": 10.0}
var _tilt_modifier: HeadTilt
var _eyes: Array[Node3D] = []
var _neutral_forehead := Vector3.ZERO
var _neutral_chin := Vector3.ZERO
## Physical mannequin fit. Length means crown to waist, not full adult height.
## Zero disables fitting for another mannequin. Thickness is kept unchanged.
@export var fit_head_to_waist_m := 0.0
@export var fit_shoulder_width_m := 0.0
## Which point of the full-body model belongs on the compression point (the
## `Sternum` node, i.e. the physical mannequin), relative to the model's own
## sternum landmark, in mannequin metres: -Z toward the head, +Y up. A negative
## Z moves the body toward the feet, so the ring sits higher on its chest.
@export var sternum_landmark_offset := Vector3.ZERO
## Vertical scale of the full-body model only (1 = native chest thickness);
## NaretSpatialAnchor sets it to flatten the chest onto the measured height.
var thickness := 1.0
var _applied_landmark_offset := Vector3.ZERO
var _base_model_scale_y := 1.0
var _base_heart_y := 0.0
var _overlay_materials: Array[ShaderMaterial] = []
var _overlay_sources: Array[StandardMaterial3D] = []
var _floor_shadow: ShaderMaterial
var _occludable := true
## Hand press: the tracked hands push the chest down to their own height, so
## real hands do not sink into a static chest. Bounded and smoothed against
## tracking jumps; shown by a shader dent, not the fixed compression morph.
const PRESS_MAX_DEPTH_M := 0.065
const PRESS_RESPONSE := 30.0
var _press_active := false
var _press_target := 0.0
var _press_depth := 0.0
var _press_center := Vector3.ZERO
## Set by main for the compression steps: only then does a hand press bring up
## the x-ray heart; the chest dent itself shows in every step.
var heart_on_press := false
@export var pe_visual_cues := true

func _refresh_overlay() -> void:
	var forehead := $Model.find_child("Forehead", true, false) as Node3D
	if forehead == null:
		return
	var mouth := $Model.find_child("Mouth", true, false) as Node3D
	var calf_world := Vector3.ZERO
	var landmarks := $Model.find_children("*", "Skeleton3D", true, false)
	var calf_found := false
	if not landmarks.is_empty():
		var skeleton := landmarks[0] as Skeleton3D
		var knee := skeleton.find_bone("calf_l")
		var ankle := skeleton.find_bone("foot_l")
		if knee >= 0 and ankle >= 0:
			calf_world = skeleton.global_transform * ((skeleton.get_bone_global_pose(knee).origin + skeleton.get_bone_global_pose(ankle).origin) * 0.5)
			calf_found = true
	for i in _overlay_materials.size():
		_overlay_materials[i].set_shader_parameter("head_world", forehead.global_position)
		_overlay_materials[i].set_shader_parameter("tint", _overlay_sources[i].albedo_color)
		_overlay_materials[i].set_shader_parameter("pe_visual_cues", pe_visual_cues and mouth != null and calf_found)
		_overlay_materials[i].set_shader_parameter("mouth_world", mouth.global_position if mouth else forehead.global_position)
		_overlay_materials[i].set_shader_parameter("calf_world", calf_world)
		_overlay_materials[i].set_shader_parameter("patient_inverse", global_basis.orthonormalized().inverse())

func _fit_patient(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or fit_head_to_waist_m <= 0.0 or fit_shoulder_width_m <= 0.0:
		return
	var skeleton := skeletons[0] as Skeleton3D
	# The lowest spine joint defines the waist; shoulder joints define the
	# cross-section where we measure the OUTSIDE of the skin, excluding hands.
	var waist_id := skeleton.find_bone("spine_01")
	var shoulder_id := skeleton.find_bone("upperarm_l")
	if waist_id < 0 or shoulder_id < 0:
		return
	var to_model := model.global_transform.affine_inverse() * skeleton.global_transform
	var waist_z := (to_model * skeleton.get_bone_global_pose(waist_id)).origin.z
	var shoulder_z := (to_model * skeleton.get_bone_global_pose(shoulder_id)).origin.z
	var crown_z := INF
	var shoulder_min := INF
	var shoulder_max := -INF
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not String(mesh.name).ends_with("Body"):
			continue
		var to_local_model := model.global_transform.affine_inverse() * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			for vertex in NaretSpatialAnchor.posed_vertices(mesh, surface):
				var point: Vector3 = to_local_model * vertex
				crown_z = minf(crown_z, point.z)
				if absf(point.z - shoulder_z) <= 0.01:
					shoulder_min = minf(shoulder_min, point.x)
					shoulder_max = maxf(shoulder_max, point.x)
	var length := waist_z - crown_z
	var width := shoulder_max - shoulder_min
	if not is_finite(length) or not is_finite(width) or length <= 0.0 or width <= 0.0:
		push_warning("Patient fit: missing usable body landmarks; keeping original scale.")
		return
	model.scale.x = fit_shoulder_width_m / width
	model.scale.z = fit_head_to_waist_m / length
	print("NARET_MODEL_FIT head_to_waist=%.3f shoulders=%.3f scale=%s waist=spine_01 shoulder_band=20mm" % [fit_head_to_waist_m, fit_shoulder_width_m, model.scale])

## Left arm moved away from the body for the lateral AED pad (degrees, about the
## upper arm's own Z axis on this rig).
const ARM_OUT := 32.0

class HeadTilt extends SkeletonModifier3D:
	## Runs after the animation, so the breathing/idle clip keeps playing underneath.
	var amount := 0.0
	var target := 0.0
	var arm := 0.0
	var arm_target := 0.0
	func _process_modification() -> void:
		amount = move_toward(amount, target, get_process_delta_time() * 2.5)
		arm = move_toward(arm, arm_target, get_process_delta_time() * 1.5)
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		var upper := skeleton.find_bone("upperarm_l")
		if upper >= 0 and arm > 0.0:
			skeleton.set_bone_pose_rotation(upper, skeleton.get_bone_pose_rotation(upper) * Quaternion(Vector3.BACK, deg_to_rad(ARM_OUT * arm)))
		if amount <= 0.0:
			return
		for bone_name: String in TILT:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0:
				continue
			var pose := skeleton.get_bone_pose_rotation(bone)
			# -X extends the neck on this rig (+X flexes, as for the spine).
			skeleton.set_bone_pose_rotation(bone, pose * Quaternion(Vector3.RIGHT, deg_to_rad(-TILT[bone_name] * amount)))

func _ready() -> void:
	var model := $Model as Node3D
	_fit_patient(model)
	_zone_rest_position = zone.position
	_base_model_scale_y = model.scale.y
	_base_heart_y = heart.position.y
	var anatomical_sternum := model.find_child("Sternum", true, false) as Node3D
	if anatomical_sternum:
		# The physical mannequin defines interaction coordinates. Align the human
		# appearance to the same chest landmark without altering the 1:1 scan.
		model.position += sternum.position - (to_local(anatomical_sternum.global_position) + sternum_landmark_offset)
		_applied_landmark_offset = sternum_landmark_offset
	_sync_landmarks()
	for pair in [["EyeLeft", $Pupils/Left], ["EyeRight", $Pupils/Right]]:
		var marker := model.find_child(pair[0], true, false) as Node3D
		if marker == null:
			continue
		# The marker sits on the cornea and rides the eye bone, so the overlay
		# follows the gaze instead of floating in front of a turning eyeball.
		var pupil := pair[1] as Node3D
		pupil.reparent(marker, false)
		pupil.position = Vector3.ZERO
		_eyes.append(pupil)
	_rig = NaretRigAnimator.new()
	_rig.name = "RigAnimator"
	add_child(_rig)
	_rig.configure(model)
	ragdoll = NaretRagdoll.new()
	ragdoll.name = "Ragdoll"
	add_child(ragdoll)
	ragdoll.configure(model)
	var chest := $Model.find_child("ScanTorso", true, false) as Node3D
	if not chest: chest = $Model.find_child("Chest", true, false) as Node3D
	if chest: breathing.configure(chest)
	_collect_skin(model)
	_apply_pallor(1.0)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_tilt_modifier = HeadTilt.new()
		skeletons[0].add_child(_tilt_modifier)

func _sync_landmarks() -> void:
	# Interaction targets must follow the resized anatomy, not the old scan.
	var model := $Model as Node3D
	for pair in [["Mouth", $MouthZone], ["Forehead", $ForeheadZone]]:
		var marker := model.find_child(pair[0], true, false) as Node3D
		if marker:
			(pair[1] as Node3D).position = to_local(marker.global_position)
	# Capture neutral landmarks at rest. Animation must not move its own hit zones.
	var forehead_marker := model.find_child("Forehead", true, false) as Node3D
	var mouth_marker := model.find_child("Mouth", true, false) as Node3D
	if forehead_marker and mouth_marker:
		_neutral_forehead = to_local(forehead_marker.global_position)
		_neutral_chin = to_local(mouth_marker.global_position) + Vector3(0, -0.025, 0.04) * model.scale

func apply_sternum_landmark_offset() -> bool:
	## Hand-menu key for tuning: applies sternum_landmark_offset as last edited,
	## e.g. in the editor's Remote inspector while the app runs. The body moves
	## opposite to the change; the ring (`Sternum`, the physical compression
	## point) stays where it is. False when nothing changed.
	var change := sternum_landmark_offset - _applied_landmark_offset
	if change.is_zero_approx():
		return false
	($Model as Node3D).position -= change
	_applied_landmark_offset = sternum_landmark_offset
	_sync_landmarks()
	return true

func set_thickness(value: float) -> void:
	## Flattens (or restores) the full-body model vertically. The scan stays 1:1.
	## Ring, chest zone, mouth and forehead move onto the flattened surface; X/Z
	## and therefore the placement on the mannequin stay unchanged.
	if is_equal_approx(value, thickness):
		return
	thickness = value
	var model := $Model as Node3D
	model.scale.y = _base_model_scale_y * value
	var datum_y := body_frame.position.y
	heart.position.y = datum_y + (_base_heart_y - datum_y) * value
	var anatomical_sternum := model.find_child("Sternum", true, false) as Node3D
	if anatomical_sternum:
		sternum.position.y = to_local(anatomical_sternum.global_position).y + _applied_landmark_offset.y
	_sync_landmarks()
	_rebase_to_sternum()

func _rebase_to_sternum() -> void:
	# Thickness fitting can move the chest landmark. Keep the pivot there while
	# preserving every child's world transform and the authored body datum.
	var shift := sternum.position
	if shift.is_zero_approx():
		return
	position += basis * shift
	for child in get_children():
		if child is Node3D:
			(child as Node3D).position -= shift
	_neutral_forehead -= shift
	_neutral_chin -= shift
	_base_heart_y -= shift.y

func get_body_transform() -> Transform3D:
	return body_frame.global_transform

func _collect_skin(node: Node) -> void:
	## Own copies of the body's skin materials, so the tint never leaks into
	## the bystanders who share the imported resources.
	if node is MeshInstance3D and String(node.name).ends_with("Body"):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var copy := source.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, copy)
			_skin.append(copy)
	for child in node.get_children():
		_collect_skin(child)

func _apply_pallor(amount: float) -> void:
	_pallor = amount
	for material in _skin:
		var tint := Color.WHITE.lerp(PALLOR, amount)
		tint.a = material.albedo_color.a # Preserve overlay opacity during skin feedback.
		material.albedo_color = tint

func get_sternum_transform() -> Transform3D:
	return sternum.global_transform

func set_overlay_opacity(opacity: float) -> void:
	# Coverage transparency writes normal depth; the face remains opaque.
	if not _overlay_materials.is_empty():
		for material in _overlay_materials:
			material.set_shader_parameter("opacity", clampf(opacity, 0.0, 1.0))
		return
	for mesh: MeshInstance3D in $Model.find_children("*", "MeshInstance3D", true, false):
		mesh.transparency = 0.0
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material == null:
				continue
			var overlay := ShaderMaterial.new()
			overlay.shader = load("res://assets/patient_overlay.gdshader")
			overlay.set_shader_parameter("clinical_skin", String(mesh.name).to_lower().ends_with("body"))
			overlay.set_shader_parameter("skin_texture", material.albedo_texture)
			overlay.set_shader_parameter("has_texture", material.albedo_texture != null)
			overlay.set_shader_parameter("surface_roughness", material.roughness)
			overlay.set_shader_parameter("opacity", clampf(opacity, 0.0, 1.0))
			_overlay_materials.append(overlay)
			_overlay_sources.append(material)
			mesh.set_surface_override_material(surface, overlay)
	# New overlay materials start at render_priority 0; keep an exclusion.
	if not _occludable:
		set_occludable(false)
	_refresh_overlay()

func set_compression_depth(depth_m: float) -> void:
	var target := clampf(depth_m, 0.0, 0.065)
	if target > 0.0:
		if is_instance_valid(_recoil_tween) and _recoil_tween.is_running():
			_recoil_tween.kill()
		_apply_compression(target)
	else:
		if _current_compression > 0.005:
			if not (is_instance_valid(_recoil_tween) and _recoil_tween.is_running()):
				_recoil_tween = create_tween()
				_recoil_tween.tween_method(_apply_compression, _current_compression, 0.0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			if is_instance_valid(_recoil_tween) and _recoil_tween.is_running():
				_recoil_tween.kill()
			_apply_compression(0.0)

func _apply_compression(depth: float) -> void:
	_current_compression = depth
	# In human_patient.glb, the mesh compression target yields 0.0277m depression at weight 1.0
	# (field re-centred on the ERC compression point). 0.05m (5 cm) is weight 1.8.
	var weight := clampf(depth / MORPH_DEPTH_M, 0.0, 2.2)
	_rig.set_compression_amount(weight)
	zone.position.y = _zone_rest_position.y - depth * 0.8
	heart.squeeze(depth)

func set_hand_press(hand_bottom: Vector3) -> void:
	## World point under the lowest tracked hand. The resting chest surface is
	## the `Sternum` node, which compressions never move.
	_press_target = clampf(sternum.global_position.y - hand_bottom.y, 0.0, PRESS_MAX_DEPTH_M)
	_press_center = hand_bottom
	if not _press_active:
		if is_instance_valid(_recoil_tween) and _recoil_tween.is_running():
			_recoil_tween.kill()
		# The dent replaces the fixed morph while the hands drive the chest.
		_current_compression = 0.0
		_rig.set_compression_amount(0.0)
	_press_active = true

func release_hand_press() -> void:
	## Hands off or lost: the chest springs back through the same smoothing.
	_press_target = 0.0

func _step_press(delta: float) -> void:
	if not _press_active:
		return
	_press_depth = lerpf(_press_depth, _press_target, 1.0 - exp(-PRESS_RESPONSE * delta))
	if is_zero_approx(_press_target) and _press_depth < 0.001:
		_press_depth = 0.0
		_press_active = false
	zone.position.y = _zone_rest_position.y - _press_depth
	heart.squeeze(_press_depth if heart_on_press else 0.0)
	var point := Vector3(_press_center.x, sternum.global_position.y - _press_depth, _press_center.z)
	for material in _overlay_materials:
		material.set_shader_parameter("press_point", point)
		material.set_shader_parameter("press_depth", _press_depth)

func compress(depth: float = 0.045) -> void:
	if is_instance_valid(_recoil_tween) and _recoil_tween.is_running():
		_recoil_tween.kill()
	_current_compression = 0.0
	var weight := clampf(depth / MORPH_DEPTH_M, 0.5, 2.2)
	if not _rig.play_action("compression", weight):
		breathing.compress(depth)
	heart.squeeze(depth)
	get_tree().create_timer(0.12).timeout.connect(func(): heart.squeeze(0.0))
	var tween := create_tween()
	tween.tween_property(zone, "position:y", _zone_rest_position.y - clampf(depth * 0.8, 0.0, 0.05), 0.11)
	tween.tween_property(zone, "position:y", _zone_rest_position.y, 0.18)

func ventilate() -> void:
	if not _rig.play_action("breathing"): breathing.ventilate()

func set_head_tilt(tilted: bool) -> void:
	if _tilt_modifier:
		_tilt_modifier.target = 1.0 if tilted else 0.0

func set_arm_clear(clear: bool) -> void:
	## The left arm out of the way of the lateral electrode.
	if _tilt_modifier:
		_tilt_modifier.arm_target = 1.0 if clear else 0.0

func forehead() -> Vector3:
	## Above the eyes towards the crown (head end is -Z, the face +Y): where a hand
	## goes to tilt the head back.
	var eyes := pupils.global_position
	if not _eyes.is_empty():
		eyes = (_eyes[0].global_position + _eyes[-1].global_position) * 0.5
	return eyes + global_basis.y.normalized() * 0.02 - global_basis.z.normalized() * 0.05

func gesture_forehead() -> Vector3:
	return global_transform * _neutral_forehead

func gesture_chin() -> Vector3:
	return global_transform * _neutral_chin

func set_recovered(recovered: bool) -> void:
	_recovered = recovered
	_breath_clock = 0.0
	pupils.set_dilation(0.4 if recovered else 1.0)
	create_tween().tween_method(_apply_pallor, _pallor, 0.0 if recovered else 1.0, 6.0 if recovered else 0.5)
	if not recovered:
		_rig.clear_gaze()

func _process(delta: float) -> void:
	_refresh_overlay()
	_step_press(delta)
	# The placement ring breathes at 110/min, a silent metronome for the target rate.
	_metronome = fmod(_metronome + delta * 110.0 / 60.0, 1.0)
	var beat := pow(1.0 - _metronome, 3.0)
	zone.scale = Vector3.ONE * (1.0 + beat * 0.12)
	(zone.material_override as StandardMaterial3D).albedo_color.a = 0.55 + beat * 0.45
	if not _recovered:
		return
	# Only a patient with signs of life tracks anyone; arrest leaves eyes fixed.
	var camera := get_viewport().get_camera_3d()
	if camera:
		_rig.look_at_point(camera.global_position)
	_breath_clock += delta
	if _breath_clock >= 4.0:
		_breath_clock = 0.0
		ventilate()

func set_hand_feedback(correct: bool) -> void:
	var mat := zone.material_override as StandardMaterial3D
	mat.albedo_color = GLOW if correct else WRONG
	mat.emission = mat.albedo_color

func cast_floor_shadow(light_direction: Vector3) -> void:
	## Same flattened overlay pass as the bystanders' (bystander_controller.gd):
	## passthrough shows the real floor, which receives no shadow-map shadows.
	## Body and scan cast it; heart, pupils and the placement ring do not.
	if _floor_shadow == null:
		_floor_shadow = ShaderMaterial.new()
		_floor_shadow.shader = preload("res://assets/floor_shadow.gdshader")
		_floor_shadow.set_shader_parameter("floor_y", get_body_transform().origin.y)
		for root: Node in [$Model, get_node_or_null("ScanReference")]:
			if root == null:
				continue
			for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				mesh.material_overlay = _floor_shadow
	_floor_shadow.set_shader_parameter("light_direction", light_direction)

func set_occludable(enabled: bool) -> void:
	## The patient lies on the real mannequin, which the depth sensor also sees,
	## so it would punch holes in its own overlay. Opaque materials rendered
	## before OpenXRMetaEnvironmentDepth (render_priority -50) are not occluded.
	## Transparent ones (ring, heart x-ray) cannot be excluded this way.
	_occludable = enabled
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material is BaseMaterial3D and (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if material:
				material.render_priority = 0 if enabled else -60

func set_shadow_floor(floor_y: float) -> void:
	if _floor_shadow:
		_floor_shadow.set_shader_parameter("floor_y", floor_y)

func set_reference_visible(enabled: bool) -> void:
	var reference := get_node_or_null("ScanReference") as Node3D
	if reference:
		reference.visible = enabled
		$Model.visible = not enabled
	heart.visible = not enabled
	pupils.visible = not enabled
	zone.visible = not enabled
