class_name NaretHandMenu
extends Node3D
## Hand-worn holographic UI, no window: scenario actions float as hex nodes above
## the fingertips, a curved diagnostic panel hugs the palm (state, live ECG, 30:2
## counters) and a cuff around the forearm carries language, mode, mic, calibrate
## and export tiles plus overflow actions. Everything is anchored to tracked hand
## joints every frame and shows while the palm faces the wearer, so both hands
## stay free for CPR the moment the hand turns away.
## A fingertip node fires when the same hand's thumb taps that fingertip, or when
## the other hand pokes it or pinches at it; NaretXRInteraction drives the latter
## through pointer_hover/pointer_press on each key.

signal menu_shown_changed(shown: bool)
signal action_requested(action: String)
signal language_requested(language: String)
signal mode_requested(mode: String)
## A setup choice from the fold-out keys: step "situation" | "breaths" | "gender".
signal setup_requested(step: String, value: String)
signal recording_requested(active: bool)
signal export_requested
signal voice_sample_requested
signal reposition_requested
signal alignment_save_requested
signal floor_calibration_requested
signal reference_scan_toggled(visible: bool)
signal hand_meshes_toggled(visible: bool)
signal chest_calibration_requested
signal chest_fit_requested(fit: String)
signal sternum_landmark_apply_requested
signal occlusion_requested(mode: String)
signal marker_gizmos_toggled(visible: bool)
## Forget floor/chest measurements and placement and begin afresh, in the app.
signal fresh_start_requested
## Debug: the LAN sensor log (NaretSensorLogger) on/off, and a recorded take.
signal sensor_log_requested(on: bool)
signal take_requested(start: bool)
var _controls: Node3D
var _reposition_key: Key3D
var _large_align: Key3D
var _floor_key: Key3D
var _scan_key: Key3D
var _sensor_key: Key3D
var _take_key: Key3D
var _sensor_on := false
var _take_on := false
var _scan_on := false
var _hands_key: Key3D
var _hands_on := false
var _chest_key: Key3D
var chest_fit := "shift"
var _occlusion_key: Key3D
var occlusion := "room"
const OCCLUSION_CYCLE := ["off", "room", "all"]
var _language_keys: Dictionary = {}
var _language_menu: Key3D
var _language_choices: Node3D
var _debug_menu: Key3D
var _debug_choices: Node3D
var _gizmos_key: Key3D
var _gizmos_on := false
var _large_start: Key3D
var _fresh_key: Key3D
var _start_action := ""
var _notice: Label3D
var _notice_until_ms := 0

func show_notice(text: String) -> void:
	if _notice:
		_notice.text = text
		_notice_until_ms = Time.get_ticks_msec() + 6000

## NaReT corporate design: NaReT-Blau and NaReT-Rot. The glow is the blue lifted
## to full value so hologram lines stay legible over passthrough; glass keeps its hue.
const BLUE := Color("1f3c7b")
const RED := Color("d11909")
const GLOW := Color("80a8ff")
const GLASS := Color("0b1630")
const INK := Color("eef3ff")
const DIM := Color("9fb3e6")
const PULSE := Color("ff6a5c")
## Palm-facing hysteresis: opening needs a deliberate turn, closing tolerates jitter.
## 0.55 -> 0.4 on headset review 2026-10-29: the menu often stayed hidden when the
## palm faced the wearer at roughly 60 degrees.
const OPEN_DOT := 0.4
const CLOSE_DOT := 0.3
## ponytail: fixed anatomical offsets, tune on a worn headset if panels crowd the hand.
const PALM_SIZE := Vector2(0.076, 0.088)
const PALM_BEND_M := 0.09
const PALM_LIFT_M := 0.012
const NODE_LIFT_M := 0.02
const NODE_R_M := 0.011
const CALLOUT_ROW_M := 0.03
const CALLOUT_SPREAD := 1.6
const CUFF_R_M := 0.043
## Three rows: main tiles, floor key under the mode key, overflow actions.
const CUFF_LEN_M := 0.092
const CUFF_ROW_Y := [-0.021, -0.050, -0.077]
const CUFF_ARC_DEG := 200.0
const DEBUG_KEY_SIZE := Vector2(0.036, 0.026)
const TAP_ON_M := 0.025
const TAP_OFF_M := 0.035
const FINGER_TIPS := [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
	XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]
const MAX_ACTIONS := 6

var hand_index := 0
var language := "de"
var mode := "own"
var ekg: NaretEKG
var palm_panel: MeshInstance3D
var _origin: XROrigin3D
var _interaction: Node
var _rig: Node3D
var _palm: Node3D
var _cuff: Node3D
var _shown := false
var _pop := 1.0
var _lang_key: Key3D
var _mode_key: Key3D
var _mic_key: Key3D
var _mic_light: MeshInstance3D
var _export_key: Key3D
var _action_keys: Array[Key3D] = []
var _leaders: Array[MeshInstance3D] = []
var _tapped := [false, false, false, false]
var _last_key := ""
var _mic_on := false
var _recording := false
## True while the virtual phone is held in this hand.
var suppressed := false


class Key3D extends Node3D:
	## One pressable target. The node origin is the hit plane at the face, which
	## stays put while the visible face sinks, so a poke keeps pressing the same key.
	## Styles: "key" (chamfered slab, text), "tile" (slab, icon over caption),
	## "node" (hex above a fingertip, label on a callout line).
	signal pressed
	const SINK_M := 0.005
	const DEPTH_M := 0.005
	var size := Vector2(0.024, 0.026)
	var accent := NaretHandMenu.GLOW
	var fill := Color.TRANSPARENT
	var label: Label3D
	var icon: Node3D
	var _face: Node3D
	var _body: MeshInstance3D
	var _frame: MeshInstance3D
	var _hover_ms := 0
	var _poke_sink := 0.0
	var _down := false
	var _offset := 0.0
	var _glow := 0.0
	var _pressed_green_until := 0
	var activate_on_press := false
	## One reach can touch a key twice (tracking jitter at the face): one action only.
	var _fired_ms := -100000

	func build(text: String, key_size: Vector2, style: String) -> void:
		size = key_size
		_face = Node3D.new()
		add_child(_face)
		_body = MeshInstance3D.new()
		_body.material_override = NaretHandMenu.glass_material()
		_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.position.z = -DEPTH_M * 0.5
		_face.add_child(_body)
		_frame = MeshInstance3D.new()
		_frame.material_override = NaretHandMenu.glow_material(NaretHandMenu.GLOW)
		_frame.material_override.render_priority = 1
		_frame.position.z = 0.0004
		_face.add_child(_frame)
		var outline: Array = NaretHandMenu.polygon(NaretHandMenu.NODE_R_M, 6) if style == "node" else NaretHandMenu.corner_cut(size, 0.003)
		_body.mesh = NaretHandMenu.extrude(outline[0], outline[1], DEPTH_M)
		_frame.mesh = NaretHandMenu.frame(outline[0], outline[1], 0.001)
		label = NaretHandMenu.make_label(text, {"key": 24, "tile": 17, "node": 22}[style], NaretHandMenu.INK)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = (0.03 if style == "node" else size.x - 0.004) / label.pixel_size
		label.position = Vector3(0, -size.y * 0.5 + 0.005 if style == "tile" else 0.0, 0.001)
		icon = Node3D.new()
		icon.position = Vector3(0, 0.0045, 0.002)
		_face.add_child(icon)
		# A node's label is a callout the menu parks in a row above the fingers.
		if style == "node":
			label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		else:
			_face.add_child(label)

	func set_text(text: String) -> void:
		label.text = text

	func set_accent(color: Color, fill_color := Color.TRANSPARENT) -> void:
		## `color` lights the frame and halo; a fill colour makes the key solid.
		accent = color
		fill = fill_color
		(_frame.material_override as StandardMaterial3D).albedo_color = color
		label.modulate = Color.WHITE if fill.a > 0.0 else NaretHandMenu.INK
		label.outline_modulate = Color(color, 0.8)

	func pointer_hover(depth_m: float) -> void:
		_hover_ms = Time.get_ticks_msec()
		# Depth is metres in front of the face; the key follows a fingertip pushing in.
		_poke_sink = clampf(-depth_m, 0.0, SINK_M)

	func pointer_press(down: bool) -> void:
		var activate := (down and not _down) if activate_on_press else (_down and not down)
		if activate and activate_on_press and Time.get_ticks_msec() - _fired_ms < 800:
			activate = false
		if activate:
			_fired_ms = Time.get_ticks_msec()
			_pressed_green_until = Time.get_ticks_msec() + 800
			print("NARET_HAND_CLICK ", label.text)
			pressed.emit()
		_down = down

	func pointer_cancel() -> void:
		## The fingertip slid off while pressed in: back up, no action.
		_down = false

	func _process(delta: float) -> void:
		var hovered := Time.get_ticks_msec() - _hover_ms < 120
		if not hovered:
			_poke_sink = 0.0
		var target := -SINK_M if _down else (-_poke_sink if _poke_sink > 0.0 else (0.002 if hovered else 0.0))
		var k := 1.0 - exp(-22.0 * delta)
		_offset = lerpf(_offset, target, k)
		_glow = lerpf(_glow, 1.0 if (hovered or _down) else 0.0, k)
		_face.position.z = _offset
		var body := _body.material_override as StandardMaterial3D
		var filled := fill.a > 0.0
		var rest := Color(fill, 0.85) if filled else Color(NaretHandMenu.GLASS, 0.62)
		if _down or Time.get_ticks_msec() < _pressed_green_until:
			rest = Color("16843c")
		body.albedo_color = rest.lerp(Color(fill.lerp(accent, 0.5) if filled else accent, 0.9), _glow)
		if _down or Time.get_ticks_msec() < _pressed_green_until:
			body.albedo_color = Color("16843c")
		body.emission = fill if filled else accent
		body.emission_energy_multiplier = (0.3 if filled else 0.0) + _glow * 0.6
		(_frame.material_override as StandardMaterial3D).albedo_color = Color(accent, 0.75 + 0.25 * _glow)
		(_frame.material_override as StandardMaterial3D).emission_energy_multiplier = 1.0 + _glow * 1.5


static func glass_material(alpha := 0.62, two_sided := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(GLASS, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	material.roughness = 0.25
	material.metallic = 0.2
	material.emission_enabled = true
	material.emission = GLOW
	material.emission_energy_multiplier = 0.0
	if two_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func glow_material(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.0
	return material


static func make_label(text: String, font_size: int, color: Color) -> Label3D:
	## Label3D ships with a fat black outline; holographic text wants a teal halo.
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0002
	label.modulate = color
	label.outline_size = 5
	label.outline_modulate = Color(GLOW, 0.6)
	label.render_priority = 2
	return label


static func corner_cut(size: Vector2, radius: float) -> Array:
	## Chamfered rectangle, counter-clockwise in XY, with outward normals.
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var half := size * 0.5 - Vector2(radius, radius)
	var corners := [Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y), Vector2(half.x, -half.y)]
	for corner in 4:
		for step in 2:
			var direction := Vector2.from_angle(deg_to_rad(corner * 90.0 + step * 90.0))
			points.append(corners[corner] + direction * radius)
			normals.append(direction)
	return [points, normals]


static func polygon(radius: float, sides: int) -> Array:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	for i in sides:
		var direction := Vector2.from_angle(deg_to_rad(30.0 + 360.0 * i / sides))
		points.append(direction * radius)
		normals.append(direction)
	return [points, normals]


static func bend(v: Vector3, radius: float) -> Vector3:
	## Wraps a flat XY shape around a cylinder along X, so a panel hugs the palm.
	if radius <= 0.0:
		return v
	var angle := v.y / radius
	return Vector3(v.x, radius * sin(angle), radius * cos(angle) - radius + v.z)


static func extrude(points: PackedVector2Array, normals: PackedVector2Array, depth: float, bend_radius := 0.0) -> ArrayMesh:
	## Outline extruded along Z with its face at +Z. Godot wants clockwise front faces.
	var count := points.size()
	var front := depth * 0.5
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := Vector2.ZERO
	for p in points:
		span = Vector2(maxf(span.x, absf(p.x) * 2), maxf(span.y, absf(p.y) * 2))
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		tool.set_normal(Vector3.BACK)
		tool.set_uv(Vector2(0.5, 0.5)); tool.add_vertex(bend(Vector3(0, 0, front), bend_radius))
		tool.set_uv(b / span + Vector2(0.5, 0.5)); tool.add_vertex(bend(Vector3(b.x, b.y, front), bend_radius))
		tool.set_uv(a / span + Vector2(0.5, 0.5)); tool.add_vertex(bend(Vector3(a.x, a.y, front), bend_radius))
		tool.set_normal(Vector3.FORWARD)
		tool.add_vertex(bend(Vector3(0, 0, -front), bend_radius))
		tool.add_vertex(bend(Vector3(a.x, a.y, -front), bend_radius))
		tool.add_vertex(bend(Vector3(b.x, b.y, -front), bend_radius))
		var na := Vector3(normals[i].x, normals[i].y, 0)
		var nb := Vector3(normals[(i + 1) % count].x, normals[(i + 1) % count].y, 0)
		tool.set_normal(na); tool.add_vertex(bend(Vector3(a.x, a.y, front), bend_radius))
		tool.set_normal(nb); tool.add_vertex(bend(Vector3(b.x, b.y, -front), bend_radius))
		tool.set_normal(na); tool.add_vertex(bend(Vector3(a.x, a.y, -front), bend_radius))
		tool.set_normal(na); tool.add_vertex(bend(Vector3(a.x, a.y, front), bend_radius))
		tool.set_normal(nb); tool.add_vertex(bend(Vector3(b.x, b.y, front), bend_radius))
		tool.set_normal(nb); tool.add_vertex(bend(Vector3(b.x, b.y, -front), bend_radius))
	return tool.commit()


static func frame(points: PackedVector2Array, normals: PackedVector2Array, thickness: float, bend_radius := 0.0) -> ArrayMesh:
	## Flat glowing rim just inside the outline, lying in the XY plane.
	var count := points.size()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.BACK)
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		var a_in := a - normals[i] * thickness
		var b_in := b - normals[(i + 1) % count] * thickness
		for p in [a, b, a_in, b, b_in, a_in]:
			tool.add_vertex(bend(Vector3(p.x, p.y, 0), bend_radius))
	return tool.commit()


static func band(radius: float, arc_deg: float, y_from: float, y_to: float, steps := 20) -> ArrayMesh:
	## Cylinder section around Y, centred on +Z, for the forearm cuff.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a0 := deg_to_rad(-arc_deg * 0.5 + arc_deg * i / steps)
		var a1 := deg_to_rad(-arc_deg * 0.5 + arc_deg * (i + 1) / steps)
		var n0 := Vector3(sin(a0), 0, cos(a0))
		var n1 := Vector3(sin(a1), 0, cos(a1))
		var quad := [[n0 * radius + Vector3(0, y_from, 0), n0], [n0 * radius + Vector3(0, y_to, 0), n0],
			[n1 * radius + Vector3(0, y_to, 0), n1], [n1 * radius + Vector3(0, y_from, 0), n1]]
		for index in [0, 1, 2, 0, 2, 3]:
			tool.set_normal(quad[index][1])
			tool.add_vertex(quad[index][0])
	return tool.commit()


static func scanlines() -> ImageTexture:
	## One brighter row in six, tiled down the panel: the hologram's raster.
	var image := Image.create(1, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.85))
	image.set_pixel(0, 0, Color(1.25, 1.35, 1.35, 1.0))
	return ImageTexture.create_from_image(image)


func configure(origin: XROrigin3D, index: int, interaction: Node = null) -> void:
	_origin = origin
	hand_index = index
	_interaction = interaction
	_rig = Node3D.new()
	_rig.visible = false
	add_child(_rig)
	# The choice pop-ups hang in the room, not on the hand (19 Nov 2026).
	_popup_root = Node3D.new()
	_popup_root.name = "ChoicePopups"
	add_child(_popup_root)
	_build_palm()
	_build_cuff()
	_build_exercise_controls()
	for i in 4:
		var node := _key("", Vector2(NODE_R_M * 2.4, NODE_R_M * 2.4), "node", Callable(), _rig)
		node.visible = false
		_palm.add_child(node.label)
		var leader := MeshInstance3D.new()
		leader.mesh = BoxMesh.new()
		(leader.mesh as BoxMesh).size = Vector3(0.001, 1.0, 0.001)
		leader.material_override = glow_material(GLOW, 0.7)
		_palm.add_child(leader)
		_leaders.append(leader)
		_action_keys.append(node)
	for i in 2:
		var key := _key("", Vector2(0.05, 0.02), "key", Callable(), _cuff)
		key.label.font_size = 20
		_place_on_cuff(key, -36.0 if i == 0 else 36.0, CUFF_ROW_Y[2])
		key.visible = false
		_action_keys.append(key)
	_refresh_mode()
	_refresh_mic()


func _build_palm() -> void:
	_palm = Node3D.new()
	_rig.add_child(_palm)
	var outline := corner_cut(PALM_SIZE, 0.012)
	palm_panel = MeshInstance3D.new()
	palm_panel.name = "PalmPanel"
	palm_panel.mesh = extrude(outline[0], outline[1], 0.003, PALM_BEND_M)
	var material := glass_material(0.6)
	material.albedo_texture = scanlines()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.uv1_scale = Vector3(1, PALM_SIZE.y / 0.0018, 1)
	material.render_priority = -1
	palm_panel.material_override = material
	palm_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_palm.add_child(palm_panel)
	var rim := MeshInstance3D.new()
	rim.mesh = frame(outline[0], outline[1], 0.001, PALM_BEND_M)
	rim.material_override = glow_material(GLOW, 0.9)
	rim.material_override.render_priority = 1
	rim.position.z = 0.0019
	_palm.add_child(rim)
	var halo_outline := corner_cut(PALM_SIZE + Vector2(0.005, 0.005), 0.014)
	var halo := MeshInstance3D.new()
	halo.mesh = frame(halo_outline[0], halo_outline[1], 0.0035, PALM_BEND_M)
	halo.material_override = glow_material(GLOW, 0.18)
	halo.position.z = 0.0017
	_palm.add_child(halo)
	# 18 Nov 2026 (user): no small brand, no training state, no counter on the palm; only
	# the large "NaReT" with "Nachbarsprache | wird | reanimiert" under it (below).
	var rule := MeshInstance3D.new()
	rule.mesh = BoxMesh.new()
	(rule.mesh as BoxMesh).size = Vector3(PALM_SIZE.x - 0.012, 0.0008, 0.0008)
	rule.material_override = glow_material(GLOW, 0.8)
	rule.position = bend(Vector3(0, PALM_SIZE.y * 0.5 - 0.017, 0.002), PALM_BEND_M)
	_palm.add_child(rule)
	var big := _palm_text("NaReT", 72, GLOW, Vector2(0.0, 0.004))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.outline_modulate = Color(GLOW, 0.35)
	var motto := _palm_text("Nachbarsprache | wird | reanimiert", 17, INK, Vector2(0.0, -0.012))
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_register(palm_panel, PALM_SIZE)


func _palm_text(text: String, font_size: int, color: Color, at: Vector2) -> Label3D:
	var label := make_label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = bend(Vector3(at.x, at.y, 0.0025), PALM_BEND_M)
	label.rotation.x = -at.y / PALM_BEND_M
	_palm.add_child(label)
	return label


func _build_cuff() -> void:
	_cuff = Node3D.new()
	_rig.add_child(_cuff)
	var sleeve := MeshInstance3D.new()
	sleeve.mesh = band(CUFF_R_M, CUFF_ARC_DEG, -CUFF_LEN_M, -0.006)
	sleeve.material_override = glass_material(0.55, true)
	sleeve.material_override.render_priority = -1
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cuff.add_child(sleeve)
	for y in [-0.0075, -CUFF_LEN_M]:
		var edge := MeshInstance3D.new()
		edge.mesh = band(CUFF_R_M + 0.0005, CUFF_ARC_DEG, y, y + 0.0015)
		edge.material_override = glow_material(GLOW, 0.9)
		_cuff.add_child(edge)
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = CUFF_R_M - (0.002 if i == 0 else 0.006)
		torus.outer_radius = CUFF_R_M + (0.002 if i == 0 else 0.006)
		ring.mesh = torus
		ring.material_override = glow_material(GLOW, 1.0 if i == 0 else 0.16)
		_cuff.add_child(ring)
	_lang_key = _key("PL", Vector2(0.024, 0.026), "key", func(): language_requested.emit(NaretLanguage.next_language(language)), _cuff)
	_place_on_cuff(_lang_key, -76.0, -0.021)
	_mode_key = _key("", Vector2(0.024, 0.026), "key", func(): mode_requested.emit("neighbour" if mode == "own" else "own"), _cuff)
	_mode_key.label.font_size = 19
	_place_on_cuff(_mode_key, -38.0, -0.021)
	_mic_key = _key("Mikrofon", Vector2(0.024, 0.026), "tile", func():
		_mic_on = not _mic_on
		_refresh_mic()
		recording_requested.emit(_mic_on), _cuff)
	_build_mic_icon(_mic_key.icon)
	_place_on_cuff(_mic_key, 0.0, -0.021)
	# Measures the real floor under a resting fingertip (NaretFloorTouch).
	_floor_key = _key(NaretLanguage.ui("Boden", "Podłoga", language), Vector2(0.024, 0.026), "tile", func(): floor_calibration_requested.emit(), _cuff)
	_build_target_icon(_floor_key.icon)
	_place_on_cuff(_floor_key, -76.0, CUFF_ROW_Y[0])
	_export_key = _key("Export", Vector2(0.024, 0.026), "tile", func(): export_requested.emit(), _cuff)
	_build_export_icon(_export_key.icon)
	_place_on_cuff(_export_key, 76.0, -0.021)
	# A flat hand on the compression point measures the real chest height.
	# Calibration tiles share the target icon: floor above, chest below it.
	_chest_key = _key("", Vector2(0.024, 0.026), "tile", func(): chest_calibration_requested.emit(), _cuff)
	_build_target_icon(_chest_key.icon)
	_place_on_cuff(_chest_key, -76.0, CUFF_ROW_Y[1])
	# One Debug key on the cuff; its testing toggles pop out to the cuff's right.
	_debug_menu = _key("Debug", Vector2(0.024, 0.026), "key", func():
		_debug_choices.visible = not _debug_choices.visible
		close_popups(), _cuff)
	_debug_menu.label.font_size = 19
	_place_on_cuff(_debug_menu, 38.0, CUFF_ROW_Y[0])
	# Headset review 2026-10-29: a wrong floor touch put everything on the ceiling with
	# no way back but reinstalling. One key resets measurements and placement.
	_fresh_key = _key(NaretLanguage.ui("Neu-
start", "Od
nowa", language), Vector2(0.024, 0.026), "key", func(): fresh_start_requested.emit(), _cuff)
	_fresh_key.label.font_size = 19
	_fresh_key.set_accent(RED, Color.TRANSPARENT)
	_place_on_cuff(_fresh_key, 0.0, CUFF_ROW_Y[1])


func _build_exercise_controls() -> void:
	# Compact controls follow the wrist, beside the original palm display.
	# Other-hand poke/pinch uses the same registered hit targets as existing keys.
	_controls = Node3D.new()
	_rig.add_child(_controls)
	# 19 Nov 2026 (user): a key opens a pop-up in front of the eyes with its options
	# (Sprache: English, Deutsch, Polski), the same for every setup key. The rows that
	# folded out beside the wrist landed far off to the side and moved with the hand.
	_language_menu = _key("Languages", Vector2(0.090, 0.035), "key", func():
		_debug_choices.visible = false
		_toggle_popup(_language_choices), _controls)
	_language_menu.activate_on_press = true
	_language_menu.label.font_size = 19
	# Grid of two columns (18 Nov 2026): Languages | Mode, Situation | Ventilation,
	# Start | Save calibration, Reposition | Gender.
	_language_menu.position = Vector3(-0.055, 0.045, 0)
	_language_choices = _make_popup(3)
	for i in 3:
		var code: String = ["en", "de", "pl"][i]
		var title: String = ["English", "Deutsch", "Polski"][i]
		var key := _popup_option(_language_choices, i, title, func(): language_requested.emit(code))
		_language_keys[code] = key
	_refresh_language_selection()
	_build_setup_menus()
	_build_debug_controls()
	_large_start = _key("Start training", Vector2(0.075, 0.045), "key", func():
		close_popups()
		# 19 Nov 2026 (headset log: six restarts in 3 s, one 0.16 s after an answer, each
		# replaying "What do you do first?"): a running training restarts only on a second
		# press within RESTART_CONFIRM_MS.
		if _start_action == "restart" and Time.get_ticks_msec() > _restart_armed_until:
			_restart_armed_until = Time.get_ticks_msec() + RESTART_CONFIRM_MS
			_large_start.set_text(NaretLanguage.ui("Nochmal drücken: Neustart", "Naciśnij ponownie: restart", language))
			_large_start.set_accent(RED.lightened(0.3), RED)
			print("NARET_RESTART armed: press again to restart")
			return
		_restart_armed_until = 0
		show_notice("Restarting training" if _start_action == "restart" else "Starting training")
		if not _start_action.is_empty(): action_requested.emit(_start_action), _controls)
	# Rows 2-2.5 cm apart, columns 2 cm (19 Nov 2026: 5 mm let one reach press three keys).
	_large_start.position = Vector3(-0.055, -0.075, 0)
	_large_start.activate_on_press = true
	# Hands-only replacement for the right controller's A button: saves the
	# current marker placement as the patient alignment, which Start requires.
	_large_align = _key(NaretLanguage.ui("Kalibrierung speichern", "Zapisz kalibrację", language), Vector2(0.075, 0.035), "key", func():
		alignment_save_requested.emit(), _controls)
	_large_align.position = Vector3(0.055, -0.075, 0)
	_large_align.label.font_size = 20
	_reposition_key = _key("Reposition", Vector2(0.090, 0.035), "key", func(): reposition_requested.emit(), _controls)
	_reposition_key.position = Vector3(-0.055, -0.140, 0)
	_reposition_key.label.font_size = 20
	_refresh_reposition_text()
	# The language row above replaces the cuff's language key; mode, mic and
	# floor calibration live on the cuff.
	_lang_key.visible = false
	# The mode is chosen with the Mode key above Languages (18 Nov 2026): no second key.
	_mode_key.visible = false
	_notice = make_label("", 21, INK)
	_notice.position = Vector3(0.0, -0.180, 0.002)
	_controls.add_child(_notice)

func _build_debug_controls() -> void:
	# Testing aids, opened by the cuff's Debug key into a flat 2×2 grid just past
	# the cuff's right edge. Unlike the languages they stay open while switching,
	# until Debug is pressed again.
	_debug_choices = Node3D.new()
	_cuff.add_child(_debug_choices)
	_debug_choices.visible = false
	# Raw detected marker poses as axis gizmos, before the patient offsets.
	_gizmos_key = _key("", DEBUG_KEY_SIZE, "key", func():
		_gizmos_on = not _gizmos_on
		_refresh_scan()
		marker_gizmos_toggled.emit(_gizmos_on), _debug_choices)
	# Meta's tracked hand meshes over the passthrough hands.
	_hands_key = _key("", DEBUG_KEY_SIZE, "key", func():
		_hands_on = not _hands_on
		_refresh_scan()
		hand_meshes_toggled.emit(_hands_on), _debug_choices)
	# Swaps the full-body patient for the 1:1 mannequin scan, to check the fit.
	_scan_key = _key("", DEBUG_KEY_SIZE, "key", func():
		_scan_on = not _scan_on
		_refresh_scan()
		reference_scan_toggled.emit(_scan_on), _debug_choices)
	# Real-world occlusion: off → room (patient excluded) → all.
	_occlusion_key = _key("", DEBUG_KEY_SIZE, "key", func():
		occlusion_requested.emit(OCCLUSION_CYCLE[(OCCLUSION_CYCLE.find(occlusion) + 1) % OCCLUSION_CYCLE.size()]), _debug_choices)
	# Sensor log over Wi-Fi (17 Nov 2026): the address and PIN appear as a notice.
	_sensor_key = _key("", DEBUG_KEY_SIZE, "key", func(): sensor_log_requested.emit(not _sensor_on), _debug_choices)
	_take_key = _key("", DEBUG_KEY_SIZE, "key", func(): take_requested.emit(not _take_on), _debug_choices)
	var keys: Array[Key3D] = [_gizmos_key, _hands_key, _scan_key, _occlusion_key, _sensor_key, _take_key]
	# The cuff's +X is the wearer's right; the grid faces out like the cuff's front
	# and starts 1 cm past the Export key at 76°, so a poke cannot hit both. The two
	# sensor-log keys are a third column.
	for i in keys.size():
		var column := 2 if i >= 4 else i % 2
		var row := (i - 4) if i >= 4 else (0 if i < 2 else 1)
		keys[i].position = Vector3(0.078 + column * 0.042, CUFF_ROW_Y[row], CUFF_R_M * 0.3)
		keys[i].label.font_size = 18
	_refresh_scan()

func _place_on_cuff(key: Key3D, angle_deg: float, y: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(angle_deg))
	key.transform = Transform3D(basis, basis.z * (CUFF_R_M + Key3D.DEPTH_M) + Vector3(0, y, 0))


func _key(text: String, size: Vector2, style: String, on_pressed: Callable, parent: Node3D) -> Key3D:
	var key := Key3D.new()
	key.build(text, size, style)
	key.set_accent(GLOW)
	if on_pressed.is_valid():
		key.pressed.connect(on_pressed)
	parent.add_child(key)
	_register(key, size)
	return key


func _icon_part(parent: Node3D, mesh: Mesh, position: Vector3, rotation := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = glow_material(INK)
	part.position = position
	part.rotation_degrees = rotation
	parent.add_child(part)
	return part


func _build_mic_icon(parent: Node3D) -> void:
	var head := CapsuleMesh.new()
	head.radius = 0.0022
	head.height = 0.0085
	_icon_part(parent, head, Vector3(0, 0.0015, 0))
	var stand := CylinderMesh.new()
	stand.top_radius = 0.0006
	stand.bottom_radius = 0.0006
	stand.height = 0.004
	_icon_part(parent, stand, Vector3(0, -0.0045, 0))
	var base := BoxMesh.new()
	base.size = Vector3(0.005, 0.001, 0.001)
	_icon_part(parent, base, Vector3(0, -0.007, 0))
	_mic_light = _icon_part(parent, SphereMesh.new(), Vector3(0.006, 0.004, 0))
	(_mic_light.mesh as SphereMesh).radius = 0.0015
	(_mic_light.mesh as SphereMesh).height = 0.003


func _build_target_icon(parent: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0035
	ring.outer_radius = 0.0046
	_icon_part(parent, ring, Vector3.ZERO, Vector3(90, 0, 0))
	var dot := SphereMesh.new()
	dot.radius = 0.001
	dot.height = 0.002
	_icon_part(parent, dot, Vector3.ZERO)
	for i in 4:
		var tick := BoxMesh.new()
		tick.size = Vector3(0.0008, 0.0028, 0.0008)
		_icon_part(parent, tick, Vector3(0, 0.0058, 0).rotated(Vector3.BACK, i * PI * 0.5), Vector3(0, 0, i * 90.0))


func _build_export_icon(parent: Node3D) -> void:
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.0012, 0.007, 0.0012)
	_icon_part(parent, shaft, Vector3(0, 0.0005, 0))
	var head := PrismMesh.new()
	head.size = Vector3(0.005, 0.0035, 0.0012)
	_icon_part(parent, head, Vector3(0, 0.005, 0))
	var tray := BoxMesh.new()
	tray.size = Vector3(0.0095, 0.0012, 0.0012)
	_icon_part(parent, tray, Vector3(0, -0.005, 0))


func _register(node: Node3D, size: Vector2) -> void:
	if _interaction != null and _interaction.has_method("register_ui_panel"):
		_interaction.call("register_ui_panel", node, null, size)


func _joint(hand: XRHandTracker, joint: int, need_orientation := false) -> Variant:
	var local: Variant = NaretXRInteraction.tracked_joint(hand, joint, need_orientation)
	return null if local == null else _origin.global_transform * (local as Transform3D)


func _process(delta: float) -> void:
	if _notice and Time.get_ticks_msec() > _notice_until_ms:
		_notice.text = ""
	if _rig == null or _origin == null:
		return
	# The phone is in the left hand (step 4, Situation A): the menu stays closed.
	if suppressed:
		_set_shown(false)
		if popup_open(): close_popups()
		return
	var camera := get_viewport().get_camera_3d()
	var hand := NaretXRInteraction.hand_tracker(hand_index)
	var pose: Variant = _joint(hand, XRHandTracker.HAND_JOINT_PALM, true) if hand != null else null
	var wrist: Variant = _joint(hand, XRHandTracker.HAND_JOINT_WRIST) if hand != null else null
	# The wrist is the first joint Quest stops tracking (edge of view, under the other
	# hand). It only supplies the forearm direction, so a tracked palm is enough (2026-10-29).
	if camera == null or pose == null:
		_show_control_fallback(camera)
		return
	var palm: Transform3D = pose
	# Godot's OpenXR humanoid conversion puts -Z out the back of the hand, so +Z is
	# the palm surface for both hands; the CPR zone relies on the same convention.
	var normal := palm.basis.z.normalized()
	var to_head := (camera.global_position - palm.origin).normalized()
	var pressing: bool = _interaction != null and _interaction.has_method("has_active_menu_press") and bool(_interaction.call("has_active_menu_press"))
	_set_shown(pressing or normal.dot(to_head) > (CLOSE_DOT if _shown else OPEN_DOT))
	if not _shown:
		return
	_palm.visible = true
	_cuff.visible = true
	_pop = minf(_pop + delta / 0.18, 1.0)
	var pop: float = Tween.interpolate_value(0.7, 0.3, _pop, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	# Frames come from geometry, not joint conventions: fingers up, palm normal out.
	# +Y runs along the fingers in Godot's OpenXR hand convention, so the forearm is -Y
	# when the wrist joint is only estimated; the cuff then sits 7 cm down the palm.
	var forearm := ((wrist as Transform3D).origin - palm.origin).normalized() if wrist != null else -palm.basis.y.normalized()
	var wrist_origin: Vector3 = (wrist as Transform3D).origin if wrist != null else palm.origin + forearm * 0.07
	var fingers := (-forearm - normal * (-forearm).dot(normal)).normalized()
	var palm_basis := Basis(fingers.cross(normal), fingers, normal)
	_palm.global_transform = Transform3D(palm_basis.scaled(Vector3.ONE * pop), palm.origin + normal * PALM_LIFT_M)
	if not pressing:
		# 19 Nov 2026 (user: "the options appear off to the left"): the grid sat 21 cm down
		# the forearm, out towards the elbow. It now stands upright beside the palm, on the
		# side towards the middle of the view, and faces the eyes; it follows the hand
		# smoothly, so tracking jitter does not shake the keys under a fingertip.
		var target := _grid_transform(camera, palm.origin, pop)
		var follow := 1.0 if _grid_snap else 1.0 - exp(-14.0 * delta)
		_grid_snap = false
		_controls.global_transform = _controls.global_transform.interpolate_with(target, follow)
	var cuff_out := (normal - forearm * normal.dot(forearm)).normalized()
	_cuff.global_transform = Transform3D(Basis((-forearm).cross(cuff_out), -forearm, cuff_out).scaled(Vector3.ONE * pop), wrist_origin)
	var thumb: Variant = _joint(hand, XRHandTracker.HAND_JOINT_THUMB_TIP)
	var to_palm := _palm.global_transform.affine_inverse()
	var row_y := 0.0
	for i in 4:
		var node := _action_keys[i]
		var tip: Variant = _joint(hand, FINGER_TIPS[i])
		node.visible = tip != null and not node.label.text.is_empty()
		node.label.visible = node.visible
		_leaders[i].visible = node.visible
		if not node.visible:
			continue
		var at := (tip as Transform3D).origin + normal * NODE_LIFT_M
		node.global_transform = Transform3D(Basis.looking_at(at - camera.global_position, fingers).scaled(Vector3.ONE * pop), at)
		row_y = maxf(row_y, (to_palm * at).y)
	for i in 4:
		var node := _action_keys[i]
		if not node.visible:
			continue
		# Callouts fan out into one row above the tallest finger, leader lines
		# running from each node to its label like a labelled diagram.
		var from := to_palm * node.global_position
		var slot := Vector3(clampf(from.x * CALLOUT_SPREAD, -0.065, 0.065), row_y + CALLOUT_ROW_M, from.z)
		node.label.position = slot + Vector3(0, 0.003, 0)
		var run := slot - from
		var along := run.normalized()
		var leader_basis := Basis.looking_at(along, Vector3.BACK) * Basis(Vector3.RIGHT, -PI * 0.5)
		_leaders[i].transform = Transform3D(leader_basis.scaled_local(Vector3(1, run.length() - NODE_R_M, 1)), from + run * 0.5 + along * NODE_R_M * 0.5)
	for i in 4:
		var node := _action_keys[i]
		if not node.visible:
			continue
		var tip: Variant = _joint(hand, FINGER_TIPS[i])
		# Thumb on that fingertip presses its node; the release fires the action.
		var gap := (thumb as Transform3D).origin.distance_to((tip as Transform3D).origin) if thumb != null else 1.0
		if not _tapped[i] and gap < TAP_ON_M:
			_tapped[i] = true
			node.pointer_press(true)
		elif _tapped[i] and gap > TAP_OFF_M:
			_tapped[i] = false
			node.pointer_press(false)
	# The heartbeat trace on the palm was removed (18 Nov 2026).


func _show_control_fallback(camera: Camera3D) -> void:
	# When holding controllers, use the same compact controls on the left wrist.
	# Without a tracked hand or controller the menu hides: it never floats in space.
	var left := _origin.get_node_or_null("LeftHand") as XRController3D
	if camera == null or left == null or not left.get_has_tracking_data():
		_set_shown(false)
		return
	_set_shown(true)
	_palm.visible = false
	_cuff.visible = false
	for node in _action_keys: node.visible = false
	for leader in _leaders: leader.visible = false
	# Moving the left controller while squeezing the right trigger must not
	# drag the captured button away before release.
	if _interaction != null and _interaction.has_method("has_active_menu_press") and _interaction.call("has_active_menu_press"):
		return
	_controls.global_transform = Transform3D(camera.global_basis, left.global_position + camera.global_basis.y * 0.10)

func _set_shown(value: bool) -> void:
	if value == _shown:
		return
	_shown = value
	_rig.visible = value
	if value:
		_pop = 0.0
		_grid_snap = true
	else:
		for i in 4:
			_tapped[i] = false
	menu_shown_changed.emit(value)


## --- Grid placement and choice pop-ups (19 Nov 2026) ---------------------------------------
## The grid stands beside the palm, towards the middle of the view (right of the left hand),
## upright and facing the eyes. GRID_SIDE_M from the palm centre to the grid centre; the
## grid's rows run from +0.022 to -0.112, so GRID_LIFT_M centres them on the palm.
const GRID_SIDE_M := 0.16
const GRID_LIFT_M := 0.050
## A pop-up opens in front of the eyes, a little below them, and stays where it opened
## (it does not follow the hand), until an option or "close" is touched.
const POPUP_DISTANCE_M := 0.42
const POPUP_DROP_M := 0.06
const POPUP_KEY := Vector2(0.20, 0.048)
const POPUP_GAP_M := 0.058
const POPUP_TITLE_M := 0.05
const POPUP_CLOSE := Vector2(0.12, 0.04)
const CLOSE_TEXT := {"de": "Schließen", "pl": "Zamknij", "en": "Close"}
## A running training restarts only on a second press within this time (19 Nov 2026).
const RESTART_CONFIRM_MS := 3000
var _restart_armed_until := 0
## While the training runs the grid shows only Restart: the setup keys sat where the other
## hand works and fired by accident (headset log 19 Nov 2026: "Situation" 8 times in 5 s).
var _training_active := false
var _popup_root: Node3D
var _popups: Array[Node3D] = []
var _grid_snap := true

func _grid_transform(camera: Camera3D, palm_origin: Vector3, pop: float) -> Transform3D:
	var side := 1.0 if hand_index == 0 else -1.0
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var at := palm_origin + right * GRID_SIDE_M * side + Vector3.UP * GRID_LIFT_M
	var toward_eyes := camera.global_position - at
	toward_eyes.y = 0.0
	if toward_eyes.length() < 0.01: toward_eyes = camera.global_basis.z
	return Transform3D(Basis.looking_at(-toward_eyes.normalized(), Vector3.UP).scaled(Vector3.ONE * pop), at)

func _make_popup(option_count: int) -> Node3D:
	## A glass panel with a title row, `option_count` option rows and a close key.
	var popup := Node3D.new()
	popup.visible = false
	_popup_root.add_child(popup)
	_popups.append(popup)
	var size := Vector2(POPUP_KEY.x + 0.03, POPUP_TITLE_M + option_count * POPUP_GAP_M + POPUP_CLOSE.y + 0.025)
	var outline := corner_cut(size, 0.01)
	var back := MeshInstance3D.new()
	back.mesh = extrude(outline[0], outline[1], 0.003)
	back.material_override = glass_material(0.85)
	back.material_override.render_priority = -1
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.position.z = -0.008
	popup.add_child(back)
	var rim := MeshInstance3D.new()
	rim.mesh = frame(outline[0], outline[1], 0.0012)
	rim.material_override = glow_material(GLOW, 0.9)
	rim.position.z = -0.0064
	popup.add_child(rim)
	# The panel stops a far pinch ray; it has no action of its own.
	_register(back, size)
	var title := make_label("", 38, GLOW)
	title.position = Vector3(0, size.y * 0.5 - POPUP_TITLE_M * 0.5, 0.001)
	popup.add_child(title)
	popup.set_meta("title", title)
	popup.set_meta("top", size.y * 0.5 - POPUP_TITLE_M)
	var close := _key(str(CLOSE_TEXT.get(language, CLOSE_TEXT.en)), POPUP_CLOSE, "key", close_popups, popup)
	close.activate_on_press = true
	close.label.font_size = 24
	close.position = Vector3(0, _popup_row_y(popup, option_count) + (POPUP_KEY.y - POPUP_CLOSE.y) * 0.5, 0)
	popup.set_meta("close", close)
	return popup

func _popup_row_y(popup: Node3D, row: int) -> float:
	return float(popup.get_meta("top")) - POPUP_KEY.y * 0.5 - row * POPUP_GAP_M

func _popup_option(popup: Node3D, row: int, text: String, on_pressed: Callable) -> Key3D:
	## An option fires on touch; the pop-up closes and the choice shows on the grid key.
	var key := _key(text, POPUP_KEY, "key", func():
		close_popups()
		on_pressed.call(), popup)
	key.activate_on_press = true
	key.label.font_size = 26
	key.position = Vector3(0, _popup_row_y(popup, row), 0)
	return key

func popup_open() -> bool:
	for popup in _popups:
		if popup.visible: return true
	return false

func close_popups() -> void:
	for popup in _popups: popup.visible = false
	if _controls: _controls.visible = true

func _toggle_popup(popup: Node3D) -> void:
	var was_open := popup.visible
	close_popups()
	if was_open: return
	_place_popup(popup)
	popup.visible = true
	# The grid steps aside while a pop-up is open: one target at a time for the fingertip.
	_controls.visible = false

func _place_popup(popup: Node3D) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or _origin == null or not _shown:
		# Tests and the desktop preview: where the grid is.
		popup.global_transform = _controls.global_transform.orthonormalized()
		return
	var ahead := -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.1 else Vector3.FORWARD
	var at := camera.global_position + ahead * POPUP_DISTANCE_M + Vector3.DOWN * POPUP_DROP_M
	popup.global_transform = Transform3D(Basis.looking_at(at - camera.global_position, Vector3.UP), at)

## --- Setup menus (18 Nov 2026) --------------------------------------------------------------
## Mode, Situation, Ventilation and Gender: keys like "Language" in the grid; each opens
## its pop-up (19 Nov 2026). The key shows its name and the current choice under it.
const SETUP_MENUS := {
	"mode": {"title": {"de": "Modus", "pl": "Tryb", "en": "Mode"}, "options": [
		["own", {"de": "Eigene Sprache", "pl": "Własny język", "en": "Own language"}],
		["neighbour", {"de": "Nachbarsprache", "pl": "Język sąsiada", "en": "Neighbouring language"}]]},
	"situation": {"title": {"de": "Situation", "pl": "Sytuacja", "en": "Situation"}, "options": [
		["A", {"de": "A – allein, kein AED", "pl": "A – sam/sama, bez AED", "en": "A – alone, no AED"}],
		["B", {"de": "B – weitere Personen, AED", "pl": "B – inne osoby, AED", "en": "B – other people, AED"}]]},
	"breaths": {"title": {"de": "Beatmung", "pl": "Oddechy", "en": "Ventilation"}, "options": [
		["yes", {"de": "Mit Beatmung (geschult, möchte, Schutzbarriere)", "pl": "Z oddechami (przeszkolenie, chęć, maska)", "en": "With ventilation (trained, willing, barrier)"}],
		["no", {"de": "Ohne Beatmung", "pl": "Bez oddechów", "en": "No ventilation"}]]},
	"gender": {"title": {"de": "Geschlecht", "pl": "Płeć", "en": "Gender"}, "options": [
		["male", {"de": "Männlich", "pl": "Mężczyzna", "en": "Male"}],
		["female", {"de": "Weiblich", "pl": "Kobieta", "en": "Female"}],
		["other", {"de": "Divers", "pl": "Inna", "en": "Other"}]]},
}
const SETUP_SPOTS := {"mode": Vector2(0.055, 0.045), "situation": Vector2(-0.055, -0.010), "breaths": Vector2(0.055, -0.010), "gender": Vector2(0.055, -0.140)}
var _setup_keys := {}
var _setup_choices := {}
var _setup_option_keys := {}
var _setup_answers := {}

func _build_setup_menus() -> void:
	for step: String in SETUP_MENUS:
		var key := _key("", Vector2(0.090, 0.035), "key", func(): _toggle_setup_menu(step), _controls)
		key.activate_on_press = true
		key.label.font_size = 19
		var spot: Vector2 = SETUP_SPOTS[step]
		key.position = Vector3(spot.x, spot.y, 0)
		_setup_keys[step] = key
		var options: Array = SETUP_MENUS[step].options
		var popup := _make_popup(options.size())
		_setup_choices[step] = popup
		var keys := {}
		for i in options.size():
			var value: String = options[i][0]
			keys[value] = _popup_option(popup, i, "", func():
				if step == "mode": mode_requested.emit(value)
				else: setup_requested.emit(step, value))
		_setup_option_keys[step] = keys
	_refresh_setup()

func _toggle_setup_menu(step: String) -> void:
	_debug_choices.visible = false
	_toggle_popup(_setup_choices[step])

## main: the current answers ({"mode", "situation", "breaths", "gender"}).
func set_setup(answers: Dictionary) -> void:
	_setup_answers = answers.duplicate()
	_refresh_setup()

func _refresh_setup() -> void:
	if _setup_keys.is_empty(): return
	var answers := _setup_answers.duplicate()
	answers["mode"] = mode
	for step: String in SETUP_MENUS:
		var menu: Dictionary = SETUP_MENUS[step]
		var title: String = menu.title.get(language, menu.title.en)
		var current := str(answers.get(step, ""))
		var chosen := ""
		for option: Array in menu.options:
			var label: String = option[1].get(language, option[1].en)
			var option_key: Key3D = _setup_option_keys[step][option[0]]
			option_key.set_text(label)
			var selected: bool = option[0] == current
			if selected: chosen = label.get_slice(" (", 0)
			option_key.set_accent(Color("32d16d") if selected else GLOW, Color("16843c") if selected else Color.TRANSPARENT)
		(((_setup_choices[step] as Node3D).get_meta("title")) as Label3D).text = title
		# 19 Nov 2026 (user: keep each selection while choosing the others): the key shows its
		# name and, under it, what is chosen; green once chosen.
		var step_key := _setup_keys[step] as Key3D
		step_key.set_text(title if chosen.is_empty() else title + "\n" + chosen)
		step_key.set_accent(GLOW if chosen.is_empty() else Color("32d16d"))
	# English has no neighbouring language here; the form only for Polish as neighbour.
	(_setup_keys["mode"] as Key3D).visible = language != "en" and not _training_active
	for step: String in ["situation", "breaths", "gender"]:
		(_setup_keys[step] as Key3D).visible = not _training_active
	for key: Key3D in [_language_menu, _large_align, _reposition_key]:
		if key: key.visible = not _training_active
	if not (_setup_keys["mode"] as Key3D).visible and (_setup_choices["mode"] as Node3D).visible: close_popups()

func update_session(scenario: NaretScenario) -> void:
	var actions := scenario.get_interface_actions()
	# Reuse existing fingertip action slots; keep the wrist/cuff layout unchanged.
	_start_action = "start" if scenario.state == NaretScenario.State.IDLE else "restart"
	var training_active := scenario.state != NaretScenario.State.IDLE and scenario.state != NaretScenario.State.RECOVERY
	# The choices belong to the setup: a pop-up left open closes once the training runs.
	if training_active and popup_open(): close_popups()
	if training_active != _training_active:
		_training_active = training_active
		_refresh_setup()
	if Time.get_ticks_msec() > _restart_armed_until:
		_large_start.set_text("Start training" if _start_action == "start" else "Restart training")
		_large_start.set_accent(Color("32d16d") if training_active else GLOW, Color("16843c") if training_active else Color.TRANSPARENT)
	if scenario.state == NaretScenario.State.RECOVERY: actions = ["restart", "briefing"]
	var key := str(actions) + language
	if key == _last_key: return
	_last_key = key
	var count := 0
	for action in actions:
		# The AED itself is worked with the hands (NaretAED.touch), not from the menu.
		if action in ["start", "restart", "reassure", "simulate_rosc", "attach_aed", "analyze_rhythm", "shock"] or count >= MAX_ACTIONS: continue
		var title := NaretLanguage.text("action." + action, language)
		if action == "start": title = NaretLanguage.ui("Training starten", "Rozpocznij trening", language)
		if action == "restart": title = NaretLanguage.ui("Neues Training", "Nowy trening", language)
		if action == "briefing": title = NaretLanguage.ui("Nachbesprechung", "Omówienie", language)
		var button := _action_keys[count]
		button.set_text(title)
		button.visible = true
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection.callable)
		button.pressed.connect(func(): action_requested.emit(action))
		# The next step leads as a solid NaReT-Blau node; 112 reads NaReT-Rot.
		if action == "call_emergency":
			button.set_accent(RED.lightened(0.3), RED)
		else:
			button.set_accent(GLOW, BLUE if count == 0 else Color.TRANSPARENT)
		count += 1
	for i in range(count, MAX_ACTIONS):
		_action_keys[i].set_text("")
		_action_keys[i].visible = false


func _refresh_reposition_text() -> void:
	if _reposition_key:
		var labels := {"en": "Reposition", "de": "Neu platzieren", "pl": "Ustaw ponownie"}
		_reposition_key.set_text(str(labels.get(language, labels.en)))


func set_language(value: String) -> void:
	language = value
	_refresh_reposition_text()
	_refresh_language_selection()
	_refresh_setup()
	_last_key = ""
	_lang_key.set_text(language.to_upper())
	_lang_key.set_accent(Color("32d16d"), Color("16843c"))
	_export_key.set_text(NaretLanguage.ui("Export", "Eksport", language))
	_large_align.set_text(NaretLanguage.ui("Kalibrierung speichern", "Zapisz kalibrację", language))
	_floor_key.set_text(NaretLanguage.ui("Boden", "Podłoga", language))
	if _fresh_key:
		_fresh_key.set_text(NaretLanguage.ui("Neu-
start", "Od
nowa", language))
	_refresh_scan()
	_refresh_mode()
	_refresh_mic()


func set_mode(value: String) -> void:
	mode = value
	_last_key = ""
	_refresh_mode()
	_refresh_setup()


func _refresh_language_selection() -> void:
	if _language_menu:
		var title: String = {"en": "English", "de": "Deutsch", "pl": "Polski"}.get(language, language)
		var heading: String = {"de": "Sprache", "pl": "Język", "en": "Language"}.get(language, "Language")
		# The key's name and the chosen language under it (19 Nov 2026); green inside too.
		_language_menu.set_text(heading + "\n" + title)
		_language_menu.set_accent(Color("32d16d"))
		(_language_choices.get_meta("title") as Label3D).text = heading
	for popup in _popups:
		(popup.get_meta("close") as Key3D).set_text(str(CLOSE_TEXT.get(language, CLOSE_TEXT.en)))
	for code: String in _language_keys:
		var selected := code == language
		_language_keys[code].set_accent(Color("32d16d") if selected else GLOW, Color("16843c") if selected else Color.TRANSPARENT)

func _refresh_scan() -> void:
	# Like the mode key: a short name over the state, green while switched on.
	_refresh_toggle(_scan_key, NaretLanguage.ui("Scan", "Skan", language), _scan_on)
	_refresh_toggle(_hands_key, NaretLanguage.ui("Hände", "Dłonie", language), _hands_on)
	_refresh_toggle(_gizmos_key, NaretLanguage.ui("Gizmos", "Gizmo", language), _gizmos_on)
	_refresh_toggle(_sensor_key, NaretLanguage.ui("Sensor-Log", "Log czujn.", language), _sensor_on)
	if _take_key:
		_take_key.set_text(("● REC" if _take_on else NaretLanguage.ui("Aufnahme", "Nagraj", language)))
		_take_key.set_accent(RED if _take_on else GLOW, Color(RED, 0.55) if _take_on else Color.TRANSPARENT)
	if _occlusion_key:
		var state: String = {"off": NaretLanguage.ui("aus", "wył.", language), "room": NaretLanguage.ui("Umgeb.", "otocz.", language), "all": NaretLanguage.ui("alle", "wszystko", language)}[occlusion]
		_occlusion_key.set_text(NaretLanguage.ui("Tiefe", "Głębia", language) + "\n" + state)
		_occlusion_key.set_accent(GLOW if occlusion == "off" else Color("32d16d"), Color.TRANSPARENT if occlusion == "off" else Color("16843c"))
	if _chest_key:
		_chest_key.set_text(NaretLanguage.ui("Brust", "Klatka", language))

func set_gizmos_on(on: bool) -> void:
	## Reflects a gizmo state set by main (e.g. on by default while reviewing placement).
	_gizmos_on = on
	_refresh_scan()

## The logger's address while it runs (empty when off), shown as a notice.
func set_sensor_log(url: String) -> void:
	_sensor_on = not url.is_empty()
	_refresh_scan()
	if _sensor_on:
		show_notice(url.trim_prefix("http://").replace("/?pin=", "  PIN "))

func set_take(recording: bool) -> void:
	_take_on = recording
	_refresh_scan()

func set_occlusion(value: String) -> void:
	occlusion = value
	_refresh_scan()

func set_chest_fit(value: String) -> void:
	chest_fit = value
	_refresh_scan()

func set_floor_calibrating(active: bool) -> void:
	## Green from the press until the fingertip measurement succeeds or fails.
	_set_lit(_floor_key, active)

func set_chest_calibrating(active: bool) -> void:
	_set_lit(_chest_key, active)

func _set_lit(key: Key3D, on: bool) -> void:
	key.set_accent(Color("32d16d") if on else GLOW, Color("16843c") if on else Color.TRANSPARENT)

func _refresh_toggle(key: Key3D, title: String, on: bool) -> void:
	if key == null:
		return
	var state := NaretLanguage.ui("an", "wł.", language) if on else NaretLanguage.ui("aus", "wył.", language)
	key.set_text(title + "\n" + state)
	_set_lit(key, on)

func _refresh_mode() -> void:
	# The key offers the other mode, so its label is what pressing it switches to.
	var other := (NaretLanguage.ui("Nachbar", "Sąsiad", language)) if mode == "own" else (NaretLanguage.ui("Eigene", "Własny", language))
	_mode_key.set_text(other)


func set_recording(active: bool) -> void:
	_recording = active
	_refresh_mic()


func set_listening(active: bool) -> void:
	_mic_on = active
	_refresh_mic()


func _refresh_mic() -> void:
	# Green while listening, like the scan key; the icon's light turns red while recording.
	_mic_key.set_accent(Color("32d16d") if _mic_on else GLOW, Color("16843c") if _mic_on else Color.TRANSPARENT)
	var material := _mic_light.material_override as StandardMaterial3D
	var color := RED if _recording else (GLOW if _mic_on else Color("3a4766"))
	material.albedo_color = color
	material.emission = color
	material.emission_energy_multiplier = 1.5 if (_recording or _mic_on) else 0.0
	_mic_key.set_text((NaretLanguage.ui("Aufnahme", "Nagrywanie", language)) if _recording else ("Microphone" if language == "en" else "Mikrofon"))

