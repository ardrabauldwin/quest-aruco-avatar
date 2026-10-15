extends SceneTree
## Live window on the Mac showing the chest cave in and recoil, driven the same way
## the hands drive it in XR (`set_compression_depth`), so the deformation can be
## watched in real time instead of in a recorded video:
##   godot --path . --xr-mode off --script tools/live_cpr.gd
## Keys: SPACE pause/resume, UP/DOWN rate, LEFT/RIGHT depth, H hands, ESC quit.

const DEPTH_M := 0.052
const RATE_MIN := 60.0
const RATE_MAX := 150.0

var _mannequin: NaretMannequin
var _camera: Camera3D
var _label: Label
var _hands: Node3D
var _sternum: Vector3
var _phase := 0.0
var _rate := 110.0
var _depth := DEPTH_M
var _running := true
var _depth_now := 0.0

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	_mannequin = scene.get_node_or_null("SpatialAnchor/Mannequin")
	if _mannequin == null:
		push_error("LIVE_CPR: mannequin not found")
		quit(1)
		return
	_sternum = _mannequin.sternum.global_position
	_mannequin.heart.visible = false
	_mannequin.pupils.visible = false
	# The app renders for passthrough (transparent background); a desktop window
	# needs its own lit environment or everything reads as black.
	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.near = 0.02
	_camera.environment = preload("res://tools/review_env.tres")
	root.add_child(_camera)
	# Side angle: the sternum profile is where the cave-in is visible.
	_camera.global_position = _sternum + Vector3(0.40, 0.30, 0.16)
	_camera.look_at(_sternum + Vector3(-0.02, -0.02, 0.0), Vector3.UP)
	_camera.make_current()
	_hands = _build_hands()
	root.add_child(_hands)
	_label = Label.new()
	_label.position = Vector2(28, 22)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color("b7f581"))
	root.add_child(_label)
	print("LIVE_CPR window open: SPACE pause · UP/DOWN rate · LEFT/RIGHT depth · H hands · ESC quit")

func _build_hands() -> Node3D:
	## Two stacked heels of hand, so the deformation is read against something.
	var rig := Node3D.new()
	for i in 2:
		var hand := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.085, 0.022, 0.105)
		hand.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("2f6fb8") if i == 0 else Color("3f86d6")
		material.roughness = 0.6
		hand.material_override = material
		hand.position = Vector3(0, 0.011 + i * 0.023, 0)
		rig.add_child(hand)
	return rig

func _process(delta: float) -> bool:
	if _mannequin == null:
		return true
	if Input.is_key_pressed(KEY_ESCAPE):
		return true
	_read_keys()
	if _running:
		_phase = fmod(_phase + delta * _rate / 60.0, 1.0)
	# One stroke per beat: fast push down, slower elastic recoil, like a real hand.
	var t := _phase / 0.42 if _phase < 0.42 else 1.0 - (_phase - 0.42) / 0.58
	_depth_now = _depth * smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	_mannequin.set_compression_depth(_depth_now)
	_hands.global_position = _sternum + Vector3(0, -_depth_now, 0)
	_label.text = "%.1f cm   ·   %d /min   ·   %s\nZiel 5–6 cm (ERC)   ·   SPACE Pause, ↑↓ Frequenz, ←→ Tiefe, H Hände, ESC Ende" % [
		_depth_now * 100.0, int(_rate), "läuft" if _running else "pausiert"]
	return false

var _held := {}

func _read_keys() -> void:
	## Edge-triggered: a held key must not run the value to its limit in one frame.
	for key in [KEY_SPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_H]:
		var down := Input.is_key_pressed(key)
		var was: bool = _held.get(key, false)
		_held[key] = down
		if not down or was:
			continue
		match key:
			KEY_SPACE: _running = not _running
			KEY_UP: _rate = minf(_rate + 5.0, RATE_MAX)
			KEY_DOWN: _rate = maxf(_rate - 5.0, RATE_MIN)
			KEY_RIGHT: _depth = minf(_depth + 0.005, 0.065)
			KEY_LEFT: _depth = maxf(_depth - 0.005, 0.0)
			KEY_H: _hands.visible = not _hands.visible
