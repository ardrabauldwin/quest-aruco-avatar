class_name NaretNameTag
extends Sprite3D
## A name card over a character's head (14 Nov 2026: "above Anna place Anna's name,
## the instructor above the instructor, above Marek: Marek, assistant").
## The same style as the cards over the AED: a dark rounded panel, the name in white
## bold, an optional role in a smaller grey line under it. The panel is an ordinary 2D
## control rendered to a texture; the sprite always faces the viewer. It is redrawn
## only when its text changes.

const NAME_PX := 54
const ROLE_PX := 34
const MARGIN_X := 34
const MARGIN_Y := 12
## Letters about 9 cm tall: readable from where the trainee kneels, 1.7 m away.
const PIXEL_M := 0.0016

var _view: SubViewport
var _panel: PanelContainer
var _name: Label
var _role: Label
var _shown := ["", ""]

func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = false
	pixel_size = PIXEL_M
	render_priority = 5
	_view = SubViewport.new()
	_view.transparent_bg = true
	_view.disable_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_view)
	_panel = PanelContainer.new()
	var card := StyleBoxFlat.new()
	# 20 Nov 2026: navy with a red bar down the left edge, as the welcome card; it was a
	# dark grey panel with a white outline.
	card.bg_color = Color(NaretFont.NAVY, 0.94)
	card.border_color = NaretFont.RED
	card.border_width_left = 14
	card.set_corner_radius_all(20)
	card.content_margin_left = MARGIN_X
	card.content_margin_right = MARGIN_X
	card.content_margin_top = MARGIN_Y
	card.content_margin_bottom = MARGIN_Y
	_panel.add_theme_stylebox_override("panel", card)
	_view.add_child(_panel)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	_panel.add_child(lines)
	_name = _line(NAME_PX, Color.WHITE, 700)
	lines.add_child(_name)
	_role = _line(ROLE_PX, Color(0.78, 0.82, 0.86), 500)
	lines.add_child(_role)
	texture = _view.get_texture()

static func _line(px: int, color: Color, weight: int) -> Label:
	var label := Label.new()
	# The app's typeface (Inter, 20 Nov 2026); a system font only if its file is missing.
	var inter := NaretFont.weight(weight)
	if inter != null:
		label.add_theme_font_override("font", inter)
	else:
		var face := SystemFont.new()
		face.font_names = PackedStringArray(["Roboto", "Noto Sans", "Segoe UI", "Arial", "sans-serif"])
		face.font_weight = weight
		label.add_theme_font_override("font", face)
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func set_text(person_name: String, role: String = "") -> void:
	if _shown == [person_name, role]: return
	_shown = [person_name, role]
	_name.text = person_name
	_role.text = role
	_role.visible = not role.is_empty()
	_fit()
	# The labels are laid out in the next frame or two; fitted and drawn again after
	# that, then left alone.
	_redraw_frames = 3

var _redraw_frames := 0

func _fit() -> void:
	## As wide and as tall as the laid-out text needs, in any language. (Summed font
	## heights were too small: the role line was cut off.)
	_panel.reset_size()
	var size_px := Vector2i(_panel.get_combined_minimum_size().ceil())
	_view.size = size_px
	_panel.size = Vector2(size_px)

func _process(_delta: float) -> void:
	if _redraw_frames <= 0: return
	_redraw_frames -= 1
	_fit()
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE

func text() -> String:
	return _name.text + ("" if _role.text.is_empty() else " / " + _role.text)
