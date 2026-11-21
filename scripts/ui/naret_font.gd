class_name NaretFont
extends RefCounted
## The app's typeface (20 Nov 2026, user: "a more professional font"): Inter, under the SIL
## Open Font License (assets/fonts/Inter-OFL.txt). One variable font file; the weights are
## variations of it. Without the file (not imported yet) Godot's default font is used.

const PATH := "res://assets/fonts/Inter.ttf"
## NaReT's two colours as used on cards and headers: navy blue and red.
const NAVY := Color("12224d")
const NAVY_DEEP := Color("0b1736")
const RED := Color("d11909")

static var _cache := {}

static func weight(value: int) -> Font:
	if _cache.has(value): return _cache[value]
	var font: Font = null
	if ResourceLoader.exists(PATH):
		var base := load(PATH) as Font
		if base != null:
			var variation := FontVariation.new()
			variation.base_font = base
			variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): value}
			font = variation
	_cache[value] = font
	return font

static func regular() -> Font: return weight(400)
static func medium() -> Font: return weight(500)
static func semibold() -> Font: return weight(600)
static func bold() -> Font: return weight(700)
