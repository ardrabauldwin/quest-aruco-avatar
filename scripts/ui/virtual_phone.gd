class_name NaretVirtualPhone
extends Node3D
## The trainee's phone in Situation A (step 4, agreed 18 Nov 2026): there is no real phone,
## so one appears in the left hand. Tap the green 112 (gate 1, it rings), then Speaker
## (gate 2, the dispatcher is heard); then the trainee lays it on the ground (ERC: on
## speaker, put it down next to you, hands free). Saying "I'm calling 112" does both taps.
## The keys are the wrist menu's (NaretHandMenu.Key3D), pressed by the other hand's poke.

signal dialed
signal speaker_on

const GREEN := Color(0.18, 0.78, 0.36)
const SIZE := Vector2(0.075, 0.15)
const TEXTS := {
	"title": {"de": "Notruf", "pl": "Numer alarmowy", "en": "Emergency call"},
	"calling": {"de": "Wähle 112 …", "pl": "Łączenie z 112 …", "en": "Calling 112 …"},
	"speaker": {"de": "Lautsprecher", "pl": "Głośnik", "en": "Speaker"},
	"on_speaker": {"de": "112 · Lautsprecher an", "pl": "112 · głośnik włączony", "en": "112 · speaker on"},
}

## hidden → dial (in the hand, 112 key) → calling (Speaker key) → placing (on speaker, still
## in the hand) → speaker (on the ground)
var state := "hidden"
var language := "de"
var dialed_ms := 0
var _origin: XROrigin3D
var _interaction: Node
var _screen: Node3D
var _title: Label3D
var _status: Label3D
var _dial_key: NaretHandMenu.Key3D
var _speaker_key: NaretHandMenu.Key3D
var _call_started_ms := 0

func configure(origin: XROrigin3D, interaction: Node) -> void:
	_origin = origin
	_interaction = interaction
	top_level = true
	visible = false
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE.x, SIZE.y, 0.009)
	body.mesh = box
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.07, 0.09)
	dark.roughness = 0.35
	body.material_override = dark
	body.position.z = -0.0055
	add_child(body)
	_screen = Node3D.new()
	add_child(_screen)
	var glass := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SIZE - Vector2(0.008, 0.012)
	glass.mesh = quad
	glass.material_override = NaretHandMenu.glass_material(0.9)
	_screen.add_child(glass)
	_title = NaretHandMenu.make_label("", 26, NaretHandMenu.INK)
	_title.position = Vector3(0, 0.05, 0.001)
	_screen.add_child(_title)
	_status = NaretHandMenu.make_label("", 22, NaretHandMenu.INK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.width = (SIZE.x - 0.012) / _status.pixel_size
	_status.position = Vector3(0, 0.025, 0.001)
	_screen.add_child(_status)
	_dial_key = _key("112", Vector2(0.055, 0.04), func(): _dial())
	_dial_key.label.font_size = 40
	_dial_key.set_accent(GREEN, GREEN)
	_speaker_key = _key("", Vector2(0.06, 0.03), func(): _speaker())
	_speaker_key.label.font_size = 22
	_speaker_key.set_accent(GREEN, GREEN)

func _key(text: String, size: Vector2, on_pressed: Callable) -> NaretHandMenu.Key3D:
	var key := NaretHandMenu.Key3D.new()
	key.build(text, size, "key")
	key.activate_on_press = true
	key.pressed.connect(on_pressed)
	key.position = Vector3(0, -0.03, 0.002)
	_screen.add_child(key)
	if _interaction != null and _interaction.has_method("register_ui_panel"):
		_interaction.call("register_ui_panel", key, null, size)
	return key

## The phone appears in the left hand, ready to dial.
func offer(lang: String) -> void:
	language = lang
	state = "dial"
	visible = true
	_refresh()
	print("NARET_PHONE offered")

func hide_phone() -> void:
	state = "hidden"
	visible = false

func in_hand() -> bool:
	return state in ["dial", "calling", "placing"]

func _dial() -> void:
	if state != "dial": return
	state = "calling"
	dialed_ms = Time.get_ticks_msec()
	_refresh()
	print("NARET_PHONE dialed 112")
	dialed.emit()

func _speaker() -> void:
	if state != "calling": return
	state = "placing"
	_refresh()
	print("NARET_PHONE speaker on")
	speaker_on.emit()

## Spoken call: 112 and Speaker at once; the phone is on speaker in the hand.
func hold_on_speaker(lang: String) -> void:
	language = lang
	if dialed_ms == 0: dialed_ms = Time.get_ticks_msec()
	state = "placing"
	visible = true
	_refresh()

## On the ground: screen up at `spot`, its top toward the head, the call running. `glide`
## moves it there in half a second instead of at once.
func put_down(spot: Vector3, toward_head: Vector3, glide := false) -> void:
	if dialed_ms == 0: dialed_ms = Time.get_ticks_msec()
	state = "speaker"
	visible = true
	_call_started_ms = Time.get_ticks_msec()
	# Screen up (+Z to the sky), its top toward the person's head.
	var top := Vector3(toward_head.x, 0.0, toward_head.z).normalized()
	if not top.is_normalized(): top = Vector3.FORWARD
	var target := Transform3D(Basis(top.cross(Vector3.UP), top, Vector3.UP), spot + Vector3.UP * 0.01)
	if glide and is_inside_tree():
		create_tween().tween_property(self, "global_transform", target, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		global_transform = target
	_refresh()

func _refresh() -> void:
	_title.text = TEXTS.title.get(language, TEXTS.title.en)
	_dial_key.visible = state == "dial"
	_speaker_key.visible = state == "calling"
	_speaker_key.set_text(TEXTS.speaker.get(language, TEXTS.speaker.en))
	match state:
		"dial": _status.text = ""
		"calling": _status.text = TEXTS.calling.get(language, TEXTS.calling.en)
		"placing", "speaker": _status.text = TEXTS.on_speaker.get(language, TEXTS.on_speaker.en)

func _process(_delta: float) -> void:
	if state == "speaker":
		var s := (Time.get_ticks_msec() - _call_started_ms) / 1000
		_title.text = "%s  %d:%02d" % [TEXTS.title.get(language, TEXTS.title.en), s / 60, s % 60]
		return
	if not in_hand() or _origin == null: return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	# Held over the left palm, screen to the eyes; a poke must not drag it away.
	if _interaction != null and _interaction.has_method("has_active_menu_press") and bool(_interaction.call("has_active_menu_press")): return
	var hand := NaretXRInteraction.hand_tracker(0)
	var local: Variant = NaretXRInteraction.tracked_joint(hand, XRHandTracker.HAND_JOINT_PALM, true) if hand != null else null
	var at: Vector3
	if local != null:
		var palm: Transform3D = _origin.global_transform * (local as Transform3D)
		at = palm.origin + palm.basis.z.normalized() * 0.04
	else:
		var left := _origin.get_node_or_null("LeftHand") as XRController3D
		if left != null and left.get_has_tracking_data():
			at = left.global_position + camera.global_basis.y * 0.08
		else:
			# No hand: in front of the eyes, a little low and left.
			at = camera.global_position - camera.global_basis.z * 0.38 - camera.global_basis.y * 0.12 - camera.global_basis.x * 0.08
	global_transform = Transform3D(Basis.looking_at(at - camera.global_position, camera.global_basis.y), at)
