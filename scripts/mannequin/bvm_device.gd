extends Node3D
## Bag-valve-mask (12 Nov 2026): the virtual device for the rescue breaths, handled like
## the AED. It is offered on a spot beside the patient's head when the breaths are due,
## grabbed with the whole hand, snapped onto the mouth when released over the target,
## and squeezed with the free hand while the other palm holds the mask. Each squeeze is
## one breath; two complete the pair. The step is proven by these hand actions, never by
## a sentence. Child of the patient, so every pose below is mannequin-local metres:
## sternum at the origin, +Y up, -Z toward the head. The model's own long axis is +Y
## (mask rim at the origin, bag toward +Y).
## Loaded by preload (no class_name): the headless test runner has no global class cache.

signal grabbed
signal placed
signal breath_given
signal squeeze_without_seal
signal put_back

const MODEL_PATH := "res://assets/models/bag_valve_mask.glb"
## Where the device waits unless main gives it a place (set_spot: on the stool).
const SPOT_LOCAL := Vector3(0.45, -0.19, -0.30)
var _spot := Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), SPOT_LOCAL)
## The yellow frame on the waiting spot; off when the spot is a visible stool.
var spot_frame_shown := true

func set_spot(local: Transform3D, show_frame: bool) -> void:
	## `local`: the lying device's pose, mannequin-local.
	_spot = local
	spot_frame_shown = show_frame
	if _spot_frame:
		_spot_frame.position = _spot.origin + Vector3(0.0, 0.01, 0.0)
		if not show_frame: _spot_frame.visible = false
	if state == State.OFFERED: transform = _spot
## Grab reach from the palm to the device origin while it waits on the spot.
const GRAB_REACH_M := 0.20
## Release over the target snaps the mask on: mask rim relative to the mouth landmark.
## Tighter since 14 Nov 2026 ("I place it correctly, then only it sits"): the mask has
## to be brought onto the face, within 6 cm sideways and along it and no more than 8 cm
## above. It used to seat from 15 cm up in the air.
const TARGET_HALF_X_M := 0.06
const TARGET_HALF_Z_M := 0.06
const TARGET_BELOW_M := 0.04
const TARGET_ABOVE_M := 0.08
## The whole handling is the trainee's (same day, after an automatic return to the stool
## was rejected): take it from the stool, seat it on the face, squeeze, take it off the
## face again and put it back on the stool. Taking it off: a closed hand on the bag that
## moves LIFT_OFF_M away. Putting it back: the mask brought within STOOL_SEAT_M of its
## place on the stool. A place it was just taken from accepts it again only after it has
## been LEAVE_M away, or it would drop straight back.
const LIFT_OFF_M := 0.15
const STOOL_SEAT_M := 0.12
const LEAVE_M := 0.25
const AUTO_RETURN := false
## Bag axis when placed: up and 35 degrees toward the crown.
const PLACED_TILT_RAD := 0.611
## 14 Nov 2026 (headset: "the mask does not sit on the mouth"). The model is straight:
## mask, valve and bag on one axis. Tilting the whole device 35 degrees toward the crown,
## as above, lifted the mask's rim off the face and left it over the nose and eyes, its
## long side across the face. Now the mask lies flat over mouth and nose, long side from
## nose to chin, and the bag is bent back at the valve toward the crown, as the angled
## connector of a real bag-valve-mask does.
## Later the same day ("don't you want to place mask and bag vertical"): no bend. The
## device stands straight, as the model is built: mask flat on the face (or on the
## stool), valve and bag straight up above it. The mask still lies flat, which was the
## point of the bend, and the device no longer leans over the head. The bend code is
## kept; BAG_BEND_RAD 0 leaves the model as it is.
const BAG_PIVOT_Y_M := 0.075
const BAG_BEND_RAD := 0.0
## Middle of the bag in the device's frame: straight up over the mask's middle. (With
## the 55 degree bend it was (-0.135, 0.170, 0).)
const BAG_OFFSET := Vector3(0.0, 0.24, 0.0)
## Where the mask's middle goes, from the patient's "Mouth" landmark. That landmark lies
## at the nose, 3 cm toward the crown from the drawn lips and 2 cm above them (side
## render build/tmp/bvm_side.png), so the mask goes toward the chin and down from it:
## its cushion then rests round mouth and nose, the nose inside the clear dome.
const MASK_TOWARD_NOSE_M := -0.015
const MASK_ABOVE_MOUTH_M := -0.022
## A hand that carries the device and is not seen for this long loses it.
const HELD_LOST_S := 3.0
const SEAL_HAND_REQUIRED := false
## After the two breaths the device goes back to its place on the stool by itself
## (14 Nov 2026: it stayed on the mouth through the next compressions, and for the next
## breaths it was simply still there). This long after the second breath, and the move
## itself takes RETURN_MOVE_S. The chest is free again and every cycle begins with
## taking the bag, as the first one does.
const BREATHS_PER_PLACEMENT := 2
const RETURN_AFTER_S := 0.8
const RETURN_MOVE_S := 0.6
## Hands while placed: the seal palm at the mask, the squeezing palm at the bag.
const SEAL_REACH_M := 0.10
const BAG_CENTRE_M := 0.24
const SQUEEZE_REACH_M := 0.20
const SQUEEZE_MIN_S := 0.3
## Longer since the bridged gaps count as squeezing (a slow, held breath is still one).
const SQUEEZE_MAX_S := 6.0
## How long the hand has to stay open before a squeeze counts as finished.
const RELEASE_S := 0.5
var _open_s := 0.0
const BREATH_GAP_S := 0.8
const EVIDENCE_S := 15.0
const FRAME_GREEN_S := 1.5
const YELLOW := Color(1.0, 0.82, 0.20)
const GREEN := Color(0.25, 0.95, 0.40)

enum State { HIDDEN, OFFERED, HELD, PLACED }
var state := State.HIDDEN
var holder := ""
var _mannequin: Node3D
var _model: Node3D
var _bag: MeshInstance3D
var _squeeze_index := -1
var _squeeze_value := 0.0
var _spot_frame: Node3D
var _mouth_frame: Node3D
var _mouth_material: ShaderMaterial
var _placed_at_ms := -1
var _clock := 0.0
var _hands: Dictionary = {}  # pointer_id -> {"palm": Vector3, "grabbing": bool}
var _hold_s := 0.0
var _hold_sealed := false
var _last_breath_s := -1.0e9
var _last_no_seal_s := -1.0e9
var _breaths: Array[float] = []
var _held_seen_s := 0.0
var _placed_breaths := 0
var _return_at_s := INF
var _return_move: Tween
var _taken_from := ""
var _left_origin := false
var _grab_from: Dictionary = {}  # pointer_id -> palm (mannequin-local) where it closed on the bag

func configure(mannequin: Node3D) -> void:
	_mannequin = mannequin
	name = "BagValveMask"
	if ResourceLoader.exists(MODEL_PATH):
		_model = (load(MODEL_PATH) as PackedScene).instantiate()
		add_child(_model)
		_bag = _model.find_child("Bag", true, false) as MeshInstance3D
		_bend_bag()
		if _bag and _bag.mesh:
			_squeeze_index = _bag.find_blend_shape_by_name("squeeze")
	_spot_frame = _frame("SpotFrame", Vector2(0.22, 0.34))
	_spot_frame.position = SPOT_LOCAL + Vector3(0.0, 0.01, 0.0)
	mannequin.add_child(_spot_frame)
	_mouth_frame = _ghost_mask("MouthFrame")
	_mouth_material = (_mouth_frame.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	mannequin.add_child(_mouth_frame)
	reset()

## The breathing target is a ghost of the mask (14 Nov 2026, after the headset test:
## "I feel a ghost mask is better" than the dashed outline, which replaced a square that
## floated over the nose). The mask's own parts (cushion, clear dome, port) copied once
## from the model into one translucent yellow material and shown exactly where the real
## mask will sit (placed_transform), so the trainee sees the mask's place and its way
## round on the face. It turns green for a moment when the real mask is seated. All
## parts share one material, so setting its "tint" colours the whole ghost.
## Very light and see-through (same evening: "it can be transparent, a very light
## yellow"), and then a ghost rather than a second mask ("now it looks like a mask
## already"): a hologram. Only the mask's edges glow, where the surface turns away from
## the viewer; the middle stays nearly clear, so the face shows through; and it pulses
## slowly. Pale yellow while it waits, green for a moment when the mask is seated.
## A clear light yellow (headset, same evening: "white is not good, make the ghost a
## very light yellow"; the paler tint read as white over the real face).
const GHOST_YELLOW := Color(1.0, 0.88, 0.25)
const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;
uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.62);
uniform float core = 0.10;
uniform float edge = 0.80;
void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.0);
	float pulse = 0.7 + 0.3 * sin(TIME * 2.5);
	ALBEDO = tint;
	ALPHA = clamp((core + edge * rim) * pulse, 0.0, 1.0);
}
"""
const GHOST_PARTS := ["MaskCushion", "MaskDome", "MaskPort", "MaskPortRing"]

func _ghost_mask(frame_name: String) -> Node3D:
	var frame := Node3D.new()
	frame.name = frame_name
	var shader := Shader.new()
	shader.code = GHOST_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", GHOST_YELLOW)
	if _model:
		for part_name in GHOST_PARTS:
			var part := _model.find_child(part_name, true, false) as MeshInstance3D
			if part == null or part.mesh == null: continue
			var ghost := MeshInstance3D.new()
			ghost.name = "Ghost" + part_name
			ghost.mesh = part.mesh
			ghost.material_override = material
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost.transform = _in_device(part)
			frame.add_child(ghost)
	if frame.get_child_count() == 0:
		# No model (tests without assets): a small disc, so the material is still there.
		var disc := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = OUTLINE_WIDE_M * 0.5
		cylinder.bottom_radius = OUTLINE_WIDE_M * 0.5
		cylinder.height = 0.01
		disc.mesh = cylinder
		disc.material_override = material
		frame.add_child(disc)
	frame.visible = false
	return frame

const OUTLINE_WIDE_M := 0.10

func _in_device(node: Node3D) -> Transform3D:
	## The node's transform in the device's own frame, walking up the model's parents.
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent is Node3D: result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result

## Opaque unshaded frame drawn before the depth pass, like the shoulder zones: the
## real-world occlusion cannot hide it on the real manikin.
func _frame(frame_name: String, size: Vector2) -> Node3D:
	var frame := Node3D.new()
	frame.name = frame_name
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = YELLOW
	material.emission_enabled = true
	material.emission = YELLOW
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = -60
	const BAR := 0.012
	for bar in [[Vector3(size.x, 0.004, BAR), Vector3(0.0, 0.0, size.y * 0.5)], [Vector3(size.x, 0.004, BAR), Vector3(0.0, 0.0, -size.y * 0.5)],
			[Vector3(BAR, 0.004, size.y), Vector3(size.x * 0.5, 0.0, 0.0)], [Vector3(BAR, 0.004, size.y), Vector3(-size.x * 0.5, 0.0, 0.0)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = bar[0]
		mesh.mesh = box
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.position = bar[1]
		frame.add_child(mesh)
	frame.visible = false
	return frame

static func _frame_material(frame: Node3D) -> StandardMaterial3D:
	return (frame.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D

func _bend_bag() -> void:
	## Everything above the mask turns about the valve, toward the model's -X.
	var pivot := Node3D.new()
	pivot.name = "BagBend"
	var at := Vector3(0.0, BAG_PIVOT_Y_M, 0.0)
	pivot.transform = Transform3D(Basis(Vector3(0, 0, 1), BAG_BEND_RAD), at) * Transform3D(Basis(), -at)
	var parts: Array[Node] = []
	for part in _model.find_children("*", "MeshInstance3D", true, false):
		if not String(part.name).begins_with("Mask") and part.get_parent() != null:
			parts.append(part)
	if parts.is_empty(): return
	var home := parts[0].get_parent()
	for part in parts:
		if part.get_parent() != home: return # an unexpected hierarchy: leave it straight
	home.add_child(pivot)
	for part in parts:
		part.reparent(pivot, false)

## How the device sits in the hand that carries it. It keeps the turn it had at the
## moment the hand closed on it, as a real object does, and its bag's middle settles
## GRIP_OUT_M in front of the palm (OpenXR palm joint: -Y is the side the palm faces).
## (14 Nov 2026, evening: "the way my hand goes is not the way the mask is grabbed, it
## looks unnatural". The device used to be snapped into one fixed hold, bag across the
## palm with the mask past the thumb: a bag standing on the stool and taken like a
## bottle, thumb up, turned upside down in the hand. And with the bag straight since
## the same evening, that fixed hold no longer defined which way the mask faced.)
const GRIP_OUT_M := 0.05
var _hold_offset := Transform3D.IDENTITY

func _take_hold(palm_world: Transform3D) -> void:
	var turn := (palm_world.affine_inverse() * global_transform).basis.orthonormalized()
	_hold_offset = Transform3D(turn, Vector3(0.0, -GRIP_OUT_M, 0.0) - turn * BAG_OFFSET)

func mouth_local() -> Vector3:
	var mouth := _mannequin.get_node_or_null("MouthZone") as Node3D if _mannequin else null
	return mouth.position if mouth else Vector3(0.0, 0.0, -0.33)

func spot_transform() -> Transform3D:
	## Lying on its spot.
	return _spot

func placed_transform() -> Transform3D:
	## Rim flat on the face; the model's long side (X) from nose to chin, so the bent
	## bag (toward the model's -X) points to the crown.
	return Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)),
		mouth_local() + Vector3(0.0, MASK_ABOVE_MOUTH_M, -MASK_TOWARD_NOSE_M))

static func mask_on_target(rim_offset: Vector3) -> bool:
	## `rim_offset`: mask rim relative to the mouth landmark, mannequin-local.
	return absf(rim_offset.x) <= TARGET_HALF_X_M and absf(rim_offset.z) <= TARGET_HALF_Z_M \
		and rim_offset.y >= -TARGET_BELOW_M and rim_offset.y <= TARGET_ABOVE_M

func reset() -> void:
	state = State.HIDDEN
	holder = ""
	visible = false
	_hands.clear()
	_hold_s = 0.0
	_open_s = 0.0
	_hold_sealed = false
	_breaths.clear()
	_last_breath_s = -1.0e9
	_last_no_seal_s = -1.0e9
	_placed_at_ms = -1
	_placed_breaths = 0
	_return_at_s = INF
	_taken_from = ""
	_left_origin = false
	_grab_from.clear()
	if _return_move and _return_move.is_valid(): _return_move.kill()
	_set_squeeze(0.0)
	if _spot_frame: _spot_frame.visible = false
	if _mouth_frame: _mouth_frame.visible = false

func offer() -> void:
	## The breaths are due: show the device on its spot and the target over the mouth.
	if state == State.PLACED:
		return
	state = State.OFFERED
	holder = ""
	transform = spot_transform()
	visible = _model != null
	_spot_frame.visible = spot_frame_shown
	# The frame marks where the mask will sit, not the landmark it is measured from.
	# 14 Nov 2026 ("the breath box is so far above the mouth; place it near mouth and
	# nose"): it hung 6 cm over the mask's seat, about 3 cm over the tip of the nose (side
	# render build/tmp/mouthbox_side.png). Now it lies just over the nose tip, its middle
	# between nose and mouth.
	# Mask-shaped since the same evening, and since the headset test that followed a
	# ghost of the mask itself, exactly where the real one will sit.
	_mouth_frame.transform = placed_transform()
	_mouth_material.set_shader_parameter("tint", GHOST_YELLOW)
	_mouth_frame.visible = true

func is_placed() -> bool:
	return state == State.PLACED

func breaths_recent() -> int:
	var count := 0
	for at in _breaths:
		if _clock - at <= EVIDENCE_S:
			count += 1
	return count

## Per hand, every frame from the interaction loop, before the patient grab. Returns true
## while this hand is busy with the device (holding or squeezing), so the caller yields.
func touch(pointer_id: String, palm_world: Transform3D, grabbing: bool, was_grabbing: bool) -> bool:
	if state == State.HIDDEN or _mannequin == null:
		return false
	var palm_local: Vector3 = _mannequin.global_transform.affine_inverse() * palm_world.origin
	_hands[pointer_id] = {"palm": palm_local, "grabbing": grabbing}
	match state:
		State.OFFERED:
			# At the bag, where a hand takes it, or at the mask.
			if grabbing and not was_grabbing and minf(palm_local.distance_to(_spot * BAG_OFFSET), palm_local.distance_to(_spot.origin)) <= GRAB_REACH_M:
				state = State.HELD
				holder = pointer_id
				_held_seen_s = _clock
				_taken_from = "spot"
				_left_origin = false
				if _return_move and _return_move.is_valid(): _return_move.kill()
				_take_hold(palm_world)
				_spot_frame.visible = false
				grabbed.emit()
				return true
		State.HELD:
			if pointer_id != holder:
				return false
			# It stays with the hand that took it, open or closed (as the AED pads do: a
			# fist held all the way to the face was what hand tracking kept losing). The
			# bag's middle sits in the palm; the device turns with the hand.
			_held_seen_s = _clock
			global_transform = palm_world * _hold_offset
			var rim: Vector3 = _mannequin.global_transform.affine_inverse() * global_transform.origin
			var origin: Vector3 = _spot.origin if _taken_from == "spot" else placed_transform().origin
			if rim.distance_to(origin) > LEAVE_M: _left_origin = true
			# Brought back to its place on the stool it is put down there.
			if (_taken_from != "spot" or _left_origin) and rim.distance_to(_spot.origin) <= STOOL_SEAT_M:
				holder = ""
				state = State.OFFERED
				transform = spot_transform()
				_spot_frame.visible = spot_frame_shown
				_mouth_frame.visible = false
				print("NARET_BVM put back on its spot")
				put_back.emit()
				return true
			# Brought to the face it seats itself: no letting go over a target.
			var rim_offset: Vector3 = rim - placed_transform().origin
			if (_taken_from != "face" or _left_origin) and mask_on_target(rim_offset):
				holder = ""
				state = State.PLACED
				_placed_breaths = 0
				_return_at_s = INF
				transform = placed_transform()
				_placed_at_ms = Time.get_ticks_msec()
				_mouth_material.set_shader_parameter("tint", GREEN)
				print("NARET_BVM placed rim_offset=", rim_offset)
				placed.emit()
			return true
		State.PLACED:
			var bag_centre: Vector3 = transform * BAG_OFFSET
			if not grabbing:
				_grab_from.erase(pointer_id)
				return false
			var at_bag := palm_local.distance_to(bag_centre) <= SQUEEZE_REACH_M
			if at_bag and not _grab_from.has(pointer_id):
				_grab_from[pointer_id] = palm_local
			# A hand that closed on the bag and carries on away from it takes the device
			# off the face; one that stays is squeezing.
			if _grab_from.has(pointer_id) and palm_local.distance_to(_grab_from[pointer_id]) > LIFT_OFF_M:
				_grab_from.clear()
				state = State.HELD
				holder = pointer_id
				_held_seen_s = _clock
				_taken_from = "face"
				_left_origin = false
				_take_hold(palm_world)
				_hold_s = 0.0
				_open_s = 0.0
				_hold_sealed = false
				_mouth_frame.visible = false
				print("NARET_BVM taken off the face hand=", pointer_id)
				grabbed.emit()
				return true
			return at_bag
	return false

## Once per frame after the hands: squeeze detection and the bag animation.
func tick(delta: float) -> void:
	_clock += delta
	if state == State.PLACED and _placed_at_ms >= 0 and _mouth_frame.visible \
			and Time.get_ticks_msec() - _placed_at_ms > int(FRAME_GREEN_S * 1000.0):
		_mouth_frame.visible = false
	if state == State.HELD and _clock - _held_seen_s > HELD_LOST_S:
		# The carrying hand is gone from tracking: back onto its spot.
		holder = ""
		state = State.OFFERED
		transform = spot_transform()
		_spot_frame.visible = spot_frame_shown
	if state == State.PLACED and _clock >= _return_at_s:
		_back_to_spot()
	if state != State.PLACED:
		_set_squeeze(0.0)
		return
	var mask_centre: Vector3 = transform * Vector3(0.0, 0.03, 0.0)
	var bag_centre: Vector3 = transform * BAG_OFFSET
	var seal := ""
	var squeezer := ""
	for id in _hands:
		var hand: Dictionary = _hands[id]
		if (hand.palm as Vector3).distance_to(mask_centre) <= SEAL_REACH_M and seal.is_empty():
			seal = id
	for id in _hands:
		var hand: Dictionary = _hands[id]
		if id != seal and bool(hand.grabbing) and (hand.palm as Vector3).distance_to(bag_centre) <= SQUEEZE_REACH_M:
			squeezer = id
	_hands.clear()
	_set_squeeze(_squeeze_value + ((1.0 if not squeezer.is_empty() else 0.0) - _squeeze_value) * minf(1.0, delta * 8.0))
	if not squeezer.is_empty():
		# A short "open" inside the squeeze was a tracking glitch: it belongs to the squeeze.
		_hold_s += delta + _open_s
		_open_s = 0.0
		_hold_sealed = _hold_sealed or not seal.is_empty()
		return
	if _hold_s > 0.0:
		# The squeeze is over only once the hand has stayed open for RELEASE_S (14 Nov 2026:
		# one squeeze was counted as two breaths, 0.56 s and 0.32 s about 3 s apart; the
		# tracked hand had opened for a moment in the middle of the squeeze).
		_open_s += delta
		if _open_s < RELEASE_S: return
		_open_s = 0.0
		var held := _hold_s
		var sealed := _hold_sealed
		_hold_s = 0.0
		_hold_sealed = false
		if held >= SQUEEZE_MIN_S and held <= SQUEEZE_MAX_S and _clock - _last_breath_s >= BREATH_GAP_S:
			# With the mask on the face a squeeze of the bag is a breath (14 Nov 2026). A
			# second hand on the mask used to be required as well; in the headset the first
			# squeeze was then refused ("squeeze without seal") although the mask was seated.
			if sealed or not SEAL_HAND_REQUIRED:
				_last_breath_s = _clock
				_breaths.append(_clock)
				print("NARET_BVM breath held_s=%.2f recent=%d" % [held, breaths_recent()])
				_placed_breaths += 1
				if AUTO_RETURN and _placed_breaths >= BREATHS_PER_PLACEMENT and _return_at_s == INF:
					_return_at_s = _clock + RETURN_AFTER_S
				breath_given.emit()
			elif _clock - _last_no_seal_s >= EVIDENCE_S:
				_last_no_seal_s = _clock
				print("NARET_BVM squeeze_without_seal held_s=%.2f" % held)
				squeeze_without_seal.emit()

func _back_to_spot() -> void:
	## Off the face and onto the stool, waiting to be taken again.
	print("NARET_BVM back on its spot after %d breaths" % _placed_breaths)
	_placed_breaths = 0
	_return_at_s = INF
	state = State.OFFERED
	holder = ""
	_hands.clear()
	_hold_s = 0.0
	_open_s = 0.0
	_mouth_frame.visible = false
	_spot_frame.visible = false
	if _return_move and _return_move.is_valid(): _return_move.kill()
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		_return_move = create_tween()
		_return_move.tween_property(self, "transform", spot_transform(), RETURN_MOVE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		transform = spot_transform()

func _set_squeeze(value: float) -> void:
	_squeeze_value = clampf(value, 0.0, 1.0)
	if _bag and _squeeze_index >= 0:
		_bag.set_blend_shape_value(_squeeze_index, _squeeze_value)

## Test hook: the same squeeze logic driven without tracked hands.
func feed(seal_palm: Variant, squeeze_palm: Variant, squeezing: bool, delta: float) -> void:
	_hands.clear()
	if seal_palm is Vector3:
		_hands["seal"] = {"palm": seal_palm, "grabbing": false}
	if squeeze_palm is Vector3:
		_hands["squeeze"] = {"palm": squeeze_palm, "grabbing": squeezing}
	tick(delta)
