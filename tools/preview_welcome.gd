extends SceneTree
## The first step, the welcome, in a desktop window as the trainee sees it in the headset
## (20 Nov 2026):
##   godot --path . --xr-mode off --script tools/preview_welcome.gd -- --lang de
## After a moment the instructor appears 1.6 m in front with his name card; once he has
## been in view for a moment he greets, with the welcome card as subtitles and his voice.
## Keys: N shows the next welcome line (open the left palm; choose in the menu),
## Space plays the step again, D / E / P switch to German / English / Polish,
## Esc closes. The room, the passthrough and the hands are not shown.

const WELCOME := {"de": "Hallo, willkommen beim NaReT-Simulator! Ich leite dich durch das Szenario. Schau zuerst von vorne auf die Marker an der Puppe.",
	"pl": "Cześć, witaj w symulatorze NaReT! Poprowadzę cię przez scenariusz. Najpierw spójrz z przodu na znaczniki na manekinie.",
	"en": "Hello, welcome to the NaReT simulator! I will guide you through the scenario. First, look at the markers on the mannequin from the front."}
const TITLE := {"de": "Willkommen bei NaReT", "pl": "Witamy w NaReT", "en": "Welcome to NaReT"}
const PALM := {"de": "Die Person liegt jetzt richtig. Bitte öffne deine linke Handfläche, um das Menü zu öffnen.",
	"pl": "Pacjent jest na miejscu. Otwórz lewą dłoń, aby otworzyć menu.",
	"en": "The patient is in place. Please open your left palm to access the menu."}
const MENU := {"de": "Wähle Sprache, Modus, Situation und Beatmung aus und drück dann auf Start training.",
	"pl": "Wybierz język, tryb, sytuację i oddechy, a potem naciśnij Start training.",
	"en": "Choose your language, mode, situation and ventilation, then press Start training."}
const INSTRUCTOR_M := 1.6
const APPEAR_S := 1.5
const SEEN_S := 0.4

var _lang := "de"
var _camera: Camera3D
var _instructor: Node3D
var _bubble: NaretSpeechBubble
var _audio: NaretAudioManager
var _hint: Label
var _clock := 0.0
var _greeted := false
var _line := 0
var _frames := 0

class Keys extends Node:
	var owner_tree: SceneTree
	func _unhandled_input(event: InputEvent) -> void:
		owner_tree.call("_on_input", event)

func _initialize() -> void:
	root.title = "NaReT welcome preview 3 (N = next line)"
	root.size = Vector2i(1280, 800)
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--lang" and index + 1 < args.size(): _lang = args[index + 1]
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.50, 0.52, 0.50)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.82, 0.85)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 25, 0)
	light.light_energy = 1.3
	root.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.36, 0.37, 0.36)
	floor_mesh.material_override = floor_material
	root.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.62, 0)
	_camera.fov = 62.0
	root.add_child(_camera)
	_camera.make_current()
	_instructor = (load("res://scenes/bystander_male.tscn") as PackedScene).instantiate()
	_instructor.name = "Instructor"
	_instructor.set("speech_jaw_scale", 0.3)
	root.add_child(_instructor)
	if _instructor.has_method("set_emotion"): _instructor.call("set_emotion", "calm")
	_instructor.visible = false
	var tag := NaretNameTag.new()
	_instructor.add_child(tag)
	tag.position = Vector3(0, 1.75 + 0.22, 0)
	tag.set_text("NARET Instructor", "")
	_bubble = NaretSpeechBubble.new()
	_bubble.camera = _camera
	root.add_child(_bubble)
	_audio = NaretAudioManager.new()
	root.add_child(_audio)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_hint = Label.new()
	_hint.position = Vector2(18, 14)
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.text = "N: next line    Space: play again    D / E / P: Deutsch / English / Polski    Esc: close"
	layer.add_child(_hint)
	var keys := Keys.new()
	keys.owner_tree = self
	root.add_child(keys)

func _restart() -> void:
	_clock = 0.0
	_line = 0
	_greeted = false
	_instructor.visible = false
	_bubble.hide_now()
	_audio.stop_speech()

func _on_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo): return
	match event.keycode:
		KEY_ESCAPE: quit()
		KEY_SPACE: _restart()
		KEY_N:
			if _greeted:
				_line = (_line + 1) % 3
				var text: String = [WELCOME, PALM, MENU][_line][_lang]
				_bubble.say(text, 600.0, TITLE[_lang])
				_audio.speak(text, _lang, "", "instructor")
		KEY_D:
			_lang = "de"
			_restart()
		KEY_E:
			_lang = "en"
			_restart()
		KEY_P:
			_lang = "pl"
			_restart()

func _process(delta: float) -> bool:
	if _instructor == null: return false
	_clock += delta
	if not _instructor.visible and _clock >= APPEAR_S:
		# As in the app: in front of the eyes, on the floor, facing the trainee.
		var spot := Vector3(0, 0, -INSTRUCTOR_M)
		var facing := _camera.position - spot
		facing.y = 0.0
		_instructor.call("place_on_floor", Transform3D(Basis.looking_at(-facing, Vector3.UP), spot))
		_instructor.visible = true
		print("PREVIEW_WELCOME instructor in front")
	if _instructor.visible and not _greeted and _clock >= APPEAR_S + SEEN_S:
		_greeted = true
		_bubble.say(WELCOME[_lang], 600.0, TITLE[_lang])
		_audio.speak(WELCOME[_lang], _lang, "", "instructor")
		print("PREVIEW_WELCOME greeting starts (", _lang, ")")
	_instructor.set("speaking", _greeted and _audio.is_speaking())
	if "--selftest" in OS.get_cmdline_user_args():
		_frames += 1
		if _frames == 240:
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/preview-welcome.png"))
			print("PREVIEW_WELCOME saved, speaking=", _audio.is_speaking())
			quit()
	return false
