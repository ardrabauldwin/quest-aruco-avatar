class_name NaretSpeechBubble
extends Node3D
## Card in the line of sight (team to-do, issue #1, "0. App-Start"): the welcome at the
## start (decision 17 Nov 2026) and the instructor's subtitles in the first steps; during
## the training the texts stay on the wrist. It floats DISTANCE_M in front of the eyes,
## slightly below, and follows the view smoothly instead of being nailed to the head.
##
## 20 Nov 2026 (user: "a more professional font and a clean, polished layout ... red and
## navy blue as the main colours, with clear headings, readable text and consistent
## spacing"): a navy card with rounded corners and a red bar down its left edge; a bold
## heading with a short red rule under it, then the text, left-aligned, in Inter. One
## padding (PAD_M) on every side, and the card is as tall as its text really is. Before:
## a dark rectangle with centred default-font text, sized by counting characters.

const DISTANCE_M := 1.1
## 20 Nov 2026 (user: "it should be lower"): the card is a caption under the speaker, like
## subtitles in a film. 0.08 put it over the face of the instructor, who stands 1.6 m in
## front during the welcome. At 0.40 its top edge is about 13 degrees under the line of
## sight: his head, shoulders and chest stay free above it.
const BELOW_M := 0.40
const FOLLOW := 3.0
const PIXEL_M := 0.0011
## Wide and low rather than tall: three lines for the welcome instead of four.
const WIDTH_M := 1.0
const PAD_M := 0.038
## The red bar down the left edge, and the rule under the heading.
const STRIPE_M := 0.012
const RULE_M := Vector2(0.09, 0.006)
const RADIUS_M := 0.022
const HEADING_SIZE := 38
const TEXT_SIZE := 31
const HEADING_GAP_M := 0.012
const RULE_GAP_M := 0.018
const LINE_SPACING := 6.0
const DEFAULT_HEADING := "NaReT"

const CARD_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;
uniform vec2 size = vec2(0.8, 0.2);
uniform float radius = 0.02;
uniform float stripe = 0.012;
uniform vec4 fill : source_color = vec4(0.07, 0.13, 0.30, 0.95);
uniform vec4 fill_low : source_color = vec4(0.04, 0.09, 0.21, 0.95);
uniform vec4 accent : source_color = vec4(0.82, 0.10, 0.04, 1.0);
uniform vec4 edge : source_color = vec4(0.45, 0.56, 0.86, 1.0);
void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 q = abs(p) - size * 0.5 + radius;
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float aa = 0.0012;
	float inside = 1.0 - smoothstep(-aa, aa, d);
	// Navy, a little deeper towards the bottom; a fine lighter line along the edge.
	vec3 colour = mix(fill.rgb, fill_low.rgb, UV.y);
	colour = mix(colour, edge.rgb, smoothstep(-0.0030, -0.0018, d) * 0.55);
	// The red bar down the left edge.
	colour = mix(colour, accent.rgb, 1.0 - smoothstep(stripe - aa, stripe + aa, p.x + size.x * 0.5));
	ALBEDO = colour;
	ALPHA = inside * fill.a;
}
"""

var camera: Node3D
var _heading: Label3D
var _label: Label3D
var _panel: MeshInstance3D
var _rule: MeshInstance3D
var _until_ms := 0
var _shown_text := ""
var _shown_heading := ""

func _ready() -> void:
	_panel = MeshInstance3D.new()
	_panel.mesh = QuadMesh.new()
	var shader := Shader.new()
	shader.code = CARD_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = 10
	material.set_shader_parameter("radius", RADIUS_M)
	material.set_shader_parameter("stripe", STRIPE_M)
	material.set_shader_parameter("fill", Color(NaretFont.NAVY, 0.95))
	material.set_shader_parameter("fill_low", Color(NaretFont.NAVY_DEEP, 0.95))
	material.set_shader_parameter("accent", NaretFont.RED)
	_panel.material_override = material
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_panel)
	_rule = MeshInstance3D.new()
	var rule_mesh := QuadMesh.new()
	rule_mesh.size = RULE_M
	_rule.mesh = rule_mesh
	var rule_material := StandardMaterial3D.new()
	rule_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rule_material.albedo_color = NaretFont.RED
	rule_material.no_depth_test = true
	rule_material.render_priority = 11
	_rule.material_override = rule_material
	add_child(_rule)
	_heading = _text_label(HEADING_SIZE, NaretFont.bold(), Color.WHITE)
	_label = _text_label(TEXT_SIZE, NaretFont.regular(), Color(0.93, 0.95, 1.0))
	_label.line_spacing = LINE_SPACING
	visible = false

func _text_label(font_size: int, font: Font, colour: Color) -> Label3D:
	var label := Label3D.new()
	label.pixel_size = PIXEL_M
	label.font_size = font_size
	if font != null: label.font = font
	label.modulate = colour
	# A thin dark edge keeps the letters crisp over passthrough; no heavy outline.
	label.outline_size = 3
	label.outline_modulate = Color(NaretFont.NAVY_DEEP, 0.9)
	label.width = _text_width_m() / PIXEL_M
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.no_depth_test = true
	label.render_priority = 12
	add_child(label)
	return label

static func _text_width_m() -> float:
	return WIDTH_M - STRIPE_M - PAD_M * 2.0

func _height_m(label: Label3D) -> float:
	## The wrapped text's real height.
	if label.text.is_empty(): return 0.0
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var paragraph := TextParagraph.new()
	paragraph.width = label.width
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	paragraph.add_string(label.text, font, label.font_size)
	var lines := paragraph.get_line_count()
	return (paragraph.get_size().y + maxf(lines - 1, 0) * label.line_spacing) * PIXEL_M

## `heading`: the card's title; empty for the default ("NaReT").
func say(text: String, seconds: float, heading: String = "") -> void:
	_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	if heading.is_empty(): heading = DEFAULT_HEADING
	# The running subtitles call this several times a second with the same text.
	if text != _shown_text or heading != _shown_heading:
		_shown_text = text
		_shown_heading = heading
		_heading.text = heading
		_label.text = text
		_layout()
	if not visible:
		visible = true
		_place(1.0)

func _layout() -> void:
	## Top to bottom: padding, heading, rule, text, padding; all from the same left edge.
	var heading_h := _height_m(_heading)
	var text_h := _height_m(_label)
	var height := PAD_M + heading_h + HEADING_GAP_M + RULE_M.y + RULE_GAP_M + text_h + PAD_M
	(_panel.mesh as QuadMesh).size = Vector2(WIDTH_M, height)
	(_panel.material_override as ShaderMaterial).set_shader_parameter("size", Vector2(WIDTH_M, height))
	# A left-aligned, top-aligned Label3D starts at its origin and runs right and down.
	var left := -WIDTH_M * 0.5 + STRIPE_M + PAD_M
	var y := height * 0.5 - PAD_M
	_heading.position = Vector3(left, y, 0.002)
	y -= heading_h + HEADING_GAP_M
	_rule.position = Vector3(left + RULE_M.x * 0.5, y - RULE_M.y * 0.5, 0.001)
	y -= RULE_M.y + RULE_GAP_M
	_label.position = Vector3(left, y, 0.002)

## What the card shows right now; empty while it is hidden.
func shown_text() -> String:
	return _shown_text if visible else ""

func card_size() -> Vector2:
	return (_panel.mesh as QuadMesh).size

func hide_now() -> void:
	visible = false
	_until_ms = 0

func _process(delta: float) -> void:
	if not visible: return
	if Time.get_ticks_msec() > _until_ms:
		visible = false
		return
	_place(1.0 - exp(-FOLLOW * delta))

func _place(weight: float) -> void:
	if camera == null: return
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001: forward = Vector3.FORWARD
	forward = forward.normalized()
	var target := camera.global_position + forward * DISTANCE_M + Vector3.DOWN * BELOW_M
	global_position = global_position.lerp(target, weight) if weight < 1.0 else target
	# Upright like a sign, turned to the viewer only around the vertical: leaning back to
	# the eyes skewed the card and its letters when seen from above (20 Nov 2026).
	look_at(global_position + forward, Vector3.UP)
