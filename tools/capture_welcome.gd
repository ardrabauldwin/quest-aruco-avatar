extends SceneTree
## Renders the welcome card (NaretSpeechBubble) alone, as it stands 1.1 m in front of the
## eyes, to review its look without a headset (20 Nov 2026):
##   godot --path . --xr-mode off --script tools/capture_welcome.gd -- --lang de
## The shot lands in build/welcome-card-<lang>.png.

const SIZE := Vector2i(1400, 800)
const WELCOME := {"de": "Hallo, willkommen beim NaReT-Simulator! Ich leite dich durch das Szenario. Schau zuerst von vorne auf die Marker an der Puppe.",
	"pl": "Cześć, witaj w symulatorze NaReT! Poprowadzę cię przez scenariusz. Najpierw spójrz z przodu na znaczniki na manekinie.",
	"en": "Hello, welcome to the NaReT simulator! I will guide you through the scenario. First, look at the markers on the mannequin from the front."}
const TITLE := {"de": "Willkommen bei NaReT", "pl": "Witamy w NaReT", "en": "Welcome to NaReT"}

var _frames := 0
var _lang := "de"

func _initialize() -> void:
	root.size = SIZE
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--lang" and index + 1 < args.size(): _lang = args[index + 1]
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# Mid grey-green, like a room seen through passthrough.
	environment.background_color = Color(0.46, 0.48, 0.46)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	camera.fov = 50.0
	root.add_child(camera)
	camera.make_current()
	var bubble := NaretSpeechBubble.new()
	bubble.camera = camera
	root.add_child(bubble)
	bubble.say.call_deferred(WELCOME[_lang], 600.0, TITLE[_lang])
	camera.look_at_from_position(camera.position, camera.position + Vector3(0, -NaretSpeechBubble.BELOW_M, -NaretSpeechBubble.DISTANCE_M), Vector3.UP)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_capture.call_deferred()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var path := "res://build/welcome-card-%s.png" % _lang
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE_WELCOME saved ", path)
	quit()
