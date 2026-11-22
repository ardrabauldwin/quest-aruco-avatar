extends Node3D
## Camera-attached practice UI; no claim to measure chest depth or actual breaths.
##
## Layout (headset review 2026-09-15):
##   TOP banner   : phase title + the count out of 30 (always drawn on top of everything).
##   LEFT box     : SPEED - half dial red / green (100-120 per minute) / red, needle + number.
##                  Reads "--" until two press intervals exist.
##   RIGHT box    : DEPTH - the last press as a big neutral number (not judged: hand travel is
##                  not chest depth) with a grey bar and the 5-6 cm target marked; "--" while
##                  hand tracking is unreliable.
##   BOTTOM line  : one instruction about the last press.
## The two boxes are the same size. The 30:2 cycle: after 30 presses the banner counts down the
## two-breath pause. All feedback is visual; the metronome beep is the only sound.
## Wording in the trainee's language (17 Nov 2026, taken from the sensor-log branch's
## HUD): HANDS ON BREASTBONE -> HANDS PLACED -> PUSH, pace hints only, no depth hints.
@export var zone: Node3D
## NaretXRInteraction: in counter_mode "detector" the HUD shows Dennis's detector.
var interaction: Node

## The trainee's language, set by NaretXRInteraction.set_hud_language for every HUD.
static var language := "en"

const TEXT := {
	"en": {"place": "HANDS ON BREASTBONE", "place_hint": "Both hands on the middle of the breastbone (green target)",
		"placed": "HANDS PLACED", "push": "PUSH", "breaths": "2 BREATHS", "breaths_hint": "30 compressions done: now 2 breaths",
		"faster": "Push faster", "slower": "Push slower", "good": "Good rate", "show_hands": "Keep hands in view",
		"waiting": "waiting for rhythm", "rhythm": "rhythm detected",
		"rate": "RATE", "rate_band": "Target 100–120 per minute", "per_min": "%d per minute",
		"depth": "DEPTH (ESTIMATED)", "depth_name": "wrist travel", "depth_band": "Target 5–6 cm"},
	"de": {"place": "HÄNDE AUFS BRUSTBEIN", "place_hint": "Beide Hände mittig aufs Brustbein (grünes Ziel)",
		"placed": "HÄNDE PLATZIERT", "push": "DRÜCKEN", "breaths": "2 BEATMUNGEN", "breaths_hint": "30 Kompressionen geschafft: jetzt 2 Beatmungen",
		"faster": "Schneller drücken", "slower": "Langsamer drücken", "good": "Gutes Tempo", "show_hands": "Hände im Blick behalten",
		"waiting": "warte auf Rhythmus", "rhythm": "Rhythmus erkannt",
		"rate": "TEMPO", "rate_band": "Ziel 100–120 pro Minute", "per_min": "%d pro Minute",
		"depth": "TIEFE (GESCHÄTZT)", "depth_name": "Weg der Handgelenke", "depth_band": "Ziel 5–6 cm"},
	"pl": {"place": "RĘCE NA MOSTEK", "place_hint": "Obie dłonie na środek mostka (zielony cel)",
		"placed": "RĘCE UŁOŻONE", "push": "UCISKAJ", "breaths": "2 WDECHY", "breaths_hint": "30 uciśnięć: teraz 2 wdechy",
		"faster": "Uciskaj szybciej", "slower": "Uciskaj wolniej", "good": "Dobre tempo", "show_hands": "Trzymaj dłonie w polu widzenia",
		"waiting": "czekam na rytm", "rhythm": "rytm rozpoznany",
		"rate": "TEMPO", "rate_band": "Cel 100–120 na minutę", "per_min": "%d na minutę",
		"depth": "GŁĘBOKOŚĆ (SZACUNEK)", "depth_name": "ruch nadgarstków", "depth_band": "Cel 5–6 cm"},
}

static func text(key: String, lang: String = "") -> String:
	var table: Dictionary = TEXT.get(language if lang.is_empty() else lang, TEXT.en)
	return str(table.get(key, TEXT.en.get(key, key)))

const DEPTH_RANGE_CM := Vector2(0.0, 8.0)
const DEPTH_GOOD_CM := Vector2(5.0, 6.0)   # adult BLS band
const BPM_RANGE := Vector2(60.0, 160.0)
const BPM_GOOD := Vector2(100.0, 120.0)    # adult BLS band
const BPM_SAMPLES_NEEDED := 2
const BOX := Vector2(0.22, 0.20)
const BOX_Y := -0.055
const LEFT_X := -0.12
const RIGHT_X := 0.12
const GAUGE_W := 0.18
const DIAL_R := 0.06
const DIAL_SEGMENTS := 30
const COLOR_GOOD := Color(0.20, 0.95, 0.40)
const COLOR_BAD := Color(0.95, 0.25, 0.20)
const COLOR_WARN := Color(1.0, 0.72, 0.18)
const COLOR_TEXT := Color(0.88, 0.98, 1.0)
const COLOR_DIM := Color(0.55, 0.68, 0.72)
const COLOR_PANEL := Color(0.015, 0.045, 0.06, 0.92)
const COLOR_TRACK_RED := Color(0.55, 0.12, 0.10)
const COLOR_TRACK_GREEN := Color(0.10, 0.50, 0.22)
# Labels must always win the draw order against the panels behind them (they sit only 2 mm in
# front, and alpha sorting put the count behind its panel on the headset).
const PRIORITY_PANEL := 0
const PRIORITY_MARK := 1
const PRIORITY_TEXT := 2

var _title: Label3D
var _counter: Label3D
var _coach: Label3D
var _status: Label3D
var _depth := {}
var _dial := {}
## Fixed labels, rewritten when the language changes: [label, key].
var _fixed: Array = []
var _shown_language := ""


## The single instruction shown while pressing: pace only (17 Nov 2026: no depth hints;
## hand travel is not chest depth). Returns text and colour.
static func coach_message(pace_feedback: String, tracking: bool, lang: String = "") -> Dictionary:
	if not tracking:
		return {"text": text("show_hands", lang), "colour": COLOR_WARN}
	match pace_feedback:
		"Press faster":
			return {"text": text("faster", lang), "colour": COLOR_WARN}
		"Press slower":
			return {"text": text("slower", lang), "colour": COLOR_WARN}
	return {"text": text("good", lang), "colour": COLOR_GOOD}


## Mean of the counter's rolling press intervals as presses per minute, or 0 with too few.
static func measured_bpm(intervals: Array) -> float:
	if intervals.size() < BPM_SAMPLES_NEEDED:
		return 0.0
	var total := 0.0
	for interval in intervals:
		total += float(interval)
	return 60.0 * intervals.size() / total if total > 0.0 else 0.0


## The last press's hand travel, shown neutrally (17 Nov 2026, as on the sensor-log
## branch): hand tracking cannot measure chest depth, only a QCPR manikin can, so the
## number is not judged red/green. Decimal comma in German and Polish.
static func depth_text(depth_cm: float, lang: String = "") -> String:
	var shown := "≈ %.1f cm" % depth_cm
	return shown if (language if lang.is_empty() else lang) == "en" else shown.replace(".", ",")


func _ready() -> void:
	# Top banner: title + count
	_panel(Vector2(0.46, 0.105), Vector3(0, 0.115, 0), COLOR_PANEL)
	_title = _label(Vector3(0, 0.148, 0.002), 22)
	_counter = _label(Vector3(0, 0.100, 0.002), 54)
	# Left box: speed dial
	_panel(BOX, Vector3(LEFT_X, BOX_Y, 0), COLOR_PANEL)
	var speed_title := _label(Vector3(LEFT_X, BOX_Y + 0.082, 0.002), 20)
	_fixed.append([speed_title, "rate"])
	_dial = _build_dial(Vector3(LEFT_X, BOX_Y - 0.005, 0.002))
	# Right box: depth number + bar
	_panel(BOX, Vector3(RIGHT_X, BOX_Y, 0), COLOR_PANEL)
	var depth_title := _label(Vector3(RIGHT_X, BOX_Y + 0.082, 0.002), 20)
	_fixed.append([depth_title, "depth"])
	_depth = _build_depth(Vector3(RIGHT_X, BOX_Y, 0.002))
	# Bottom: instruction + hand status
	_coach = _label(Vector3(0, -0.185, 0.002), 30)
	_status = _label(Vector3(0, -0.218, 0.002), 18)
	_status.modulate = COLOR_DIM
	visible = false


func _label(at: Vector3, font: int) -> Label3D:
	var label := Label3D.new()
	label.position = at
	label.font_size = font
	label.pixel_size = 0.00045
	label.outline_size = 4
	label.no_depth_test = true
	label.render_priority = PRIORITY_TEXT
	label.modulate = COLOR_TEXT
	add_child(label)
	return label


func _panel(size_value: Vector2, at: Vector3, colour: Color, priority: int = PRIORITY_PANEL) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size_value
	panel.mesh = mesh
	panel.position = at
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = priority
	material.albedo_color = colour
	panel.material_override = material
	add_child(panel)
	return panel


## Half dial from 60 (left) to 160 (right) presses per minute: red - green (100-120) - red,
## a needle pivoting at the centre, the number below it and the target band under that.
func _build_dial(centre: Vector3) -> Dictionary:
	var arc_len := PI * DIAL_R / DIAL_SEGMENTS
	for i in DIAL_SEGMENTS:
		var fraction := (float(i) + 0.5) / DIAL_SEGMENTS
		var value := BPM_RANGE.x + (BPM_RANGE.y - BPM_RANGE.x) * fraction
		var angle := PI * (1.0 - fraction)
		var seg := _panel(Vector2(arc_len * 1.05, 0.014), centre + Vector3(cos(angle), sin(angle), 0) * DIAL_R,
			COLOR_TRACK_GREEN if value >= BPM_GOOD.x and value <= BPM_GOOD.y else COLOR_TRACK_RED, PRIORITY_MARK)
		seg.rotation.z = angle + PI * 0.5
	var needle := _panel(Vector2(DIAL_R * 0.9, 0.005), centre + Vector3(0, 0, 0.002), Color.WHITE, PRIORITY_MARK)
	needle.visible = false
	_panel(Vector2(0.012, 0.012), centre + Vector3(0, 0, 0.003), COLOR_DIM, PRIORITY_MARK)
	var value_label := _label(centre + Vector3(0, -0.030, 0.002), 30)
	value_label.text = "--"
	var band_label := _label(centre + Vector3(0, -0.058, 0.002), 18)
	_fixed.append([band_label, "rate_band"])
	band_label.modulate = COLOR_DIM
	return {"centre": centre, "needle": needle, "value": value_label}


## Needle at the measured rate, or hidden with "--" when there is no reliable measurement.
func _set_dial(bpm: float, available: bool) -> void:
	var needle: MeshInstance3D = _dial["needle"]
	var value_label: Label3D = _dial["value"]
	if not available or bpm <= 0.0:
		needle.visible = false
		value_label.text = "--"
		value_label.modulate = COLOR_DIM
		return
	var fraction := clampf((bpm - BPM_RANGE.x) / (BPM_RANGE.y - BPM_RANGE.x), 0.0, 1.0)
	var angle := PI * (1.0 - fraction)
	var centre: Vector3 = _dial["centre"]
	needle.visible = true
	needle.rotation.z = angle
	needle.position = centre + Vector3(cos(angle), sin(angle), 0) * DIAL_R * 0.45 + Vector3(0, 0, 0.002)
	var in_band := bpm >= BPM_GOOD.x and bpm <= BPM_GOOD.y
	needle.material_override.albedo_color = COLOR_GOOD if in_band else Color.WHITE
	value_label.text = text("per_min") % int(round(bpm))
	value_label.modulate = COLOR_GOOD if in_band else COLOR_BAD


## Depth box: a big coloured number for the last press, the target under it, and a small bar
## (grey track, lighter 5-6 cm target band, white marker for the last press).
func _build_depth(centre: Vector3) -> Dictionary:
	var value_label := _label(centre + Vector3(0, 0.030, 0), 46)
	value_label.text = "--"
	value_label.modulate = COLOR_DIM
	var name_label := _label(centre + Vector3(0, -0.008, 0), 16)
	_fixed.append([name_label, "depth_name"])
	name_label.modulate = COLOR_DIM
	var band_label := _label(centre + Vector3(0, -0.028, 0), 18)
	_fixed.append([band_label, "depth_band"])
	band_label.modulate = COLOR_DIM
	var bar_centre := centre + Vector3(0, -0.062, 0)
	var span := DEPTH_RANGE_CM.y - DEPTH_RANGE_CM.x
	_panel(Vector2(GAUGE_W, 0.012), bar_centre, COLOR_PANEL.lightened(0.15), PRIORITY_MARK)
	var band_w := GAUGE_W * (DEPTH_GOOD_CM.y - DEPTH_GOOD_CM.x) / span
	var band_x := -GAUGE_W * 0.5 + GAUGE_W * ((DEPTH_GOOD_CM.x + DEPTH_GOOD_CM.y) * 0.5 - DEPTH_RANGE_CM.x) / span
	_panel(Vector2(band_w, 0.012), bar_centre + Vector3(band_x, 0, 0.0005), COLOR_DIM, PRIORITY_MARK)
	var marker := _panel(Vector2(0.006, 0.024), bar_centre + Vector3(0, 0, 0.002), Color.WHITE, PRIORITY_MARK)
	marker.visible = false
	return {"bar_centre": bar_centre, "marker": marker, "value": value_label, "name": name_label}


## Big number + marker for a completed press; "--" and no marker while unavailable.
func _set_depth(depth_cm: float, available: bool) -> void:
	var marker: MeshInstance3D = _depth["marker"]
	var value_label: Label3D = _depth["value"]
	if not available:
		marker.visible = false
		value_label.text = "--"
		value_label.modulate = COLOR_DIM
		return
	value_label.text = depth_text(depth_cm)
	value_label.modulate = COLOR_TEXT
	var fraction := clampf((depth_cm - DEPTH_RANGE_CM.x) / (DEPTH_RANGE_CM.y - DEPTH_RANGE_CM.x), 0.0, 1.0)
	var bar_centre: Vector3 = _depth["bar_centre"]
	marker.visible = true
	marker.position.x = bar_centre.x - GAUGE_W * 0.5 + GAUGE_W * fraction
	marker.material_override.albedo_color = Color.WHITE


func _process(_delta: float) -> void:
	visible = zone != null and zone.is_visible_in_tree() and not zone.get("_paused")
	if not visible:
		return
	var session = zone.get("motion_session")
	var tracking: bool = session.tracking_available
	var travel_cm: float = session.last_stroke_travel_m * 100.0
	var bpm := measured_bpm(session._bpm_samples)
	if _shown_language != language:
		_shown_language = language
		for item in _fixed:
			(item[0] as Label3D).text = text(item[1])
	if interaction != null and interaction.get("counter_mode") == "detector" and session.phase != "breathing":
		_show_detector()
		return
	# The rate counts as found once the dial has a measured pace (two press intervals).
	var rhythm := text("rhythm") if bpm > 0.0 else text("waiting")

	if session.phase == "breathing":
		_title.text = text("breaths")
		_counter.text = "%.1f s" % session.breathing_remaining_s
		_coach.text = text("breaths_hint")
		_coach.modulate = COLOR_TEXT
		_status.text = ""
		_set_depth(0.0, false)
		_set_dial(0.0, false)
	elif zone.get("placed_counting") and _placed_state() != "placed":
		# Placed counting (cpr_hand_zone.gd): counting only starts once the hands rest in
		# the green area, also after the hands were lifted.
		_title.text = text("place")
		_counter.text = "%d / 30" % session.count
		_coach.text = text("place_hint") if tracking else text("show_hands")
		_coach.modulate = COLOR_GOOD if tracking else COLOR_WARN
		_status.text = rhythm if session.total_count > 0 else ""
		_set_depth(0.0, false)
		_set_dial(bpm, session.total_count > 0)
	elif not session.active:
		# "HANDS PLACED" only for both hands (13 Nov 2026), the same rule as the green box
		# (cpr_hand_zone.gd: both hands stacked, or one visible and the other last seen
		# at the chest).
		var both: bool = zone.get("correct_placement")
		_title.text = text("placed") if both else text("place")
		_counter.text = "0 / 30"
		_coach.text = text("push") if both else text("place_hint")
		_coach.modulate = COLOR_GOOD
		_status.text = text("waiting") if both else ""
		_set_depth(0.0, false)
		_set_dial(0.0, false)
	else:
		_title.text = text("push")
		_counter.text = "%d / 30" % session.count
		var cue := coach_message(session.feedback, tracking)
		_coach.text = cue["text"]
		_coach.modulate = cue["colour"]
		_status.text = rhythm
		# The last completed press stays readable through short tracking dropouts; only the
		# live marker needs current tracking.
		_set_depth(travel_cm, session.total_count > 0)
		_set_dial(bpm, session.total_count > 0)


## The same panel and wording, fed by NaretCprDetector (build with "detector_counter").
## Its count is the cycle's (reset with the cycle), its rhythm the detector's own check.
func _show_detector() -> void:
	var det = interaction.get("detector")
	var counting: bool = det.count > 0
	_counter.text = "%d / 30" % det.count
	_status.text = text("rhythm") if det.confirmed() else text("waiting")
	if not interaction.get("hands_seen"):
		_title.text = text("push") if counting else text("place")
		_coach.text = text("show_hands")
		_coach.modulate = COLOR_WARN
	elif not interaction.get("chest_contact"):
		_title.text = text("place")
		_coach.text = text("place_hint")
		_coach.modulate = COLOR_GOOD
	elif not counting:
		_title.text = text("placed")
		_coach.text = text("push")
		_coach.modulate = COLOR_GOOD
	else:
		_title.text = text("push")
		var pace := "Press faster" if det.rate_bpm > 0.0 and det.rate_bpm < BPM_GOOD.x else ("Press slower" if det.rate_bpm > BPM_GOOD.y else "")
		var cue := coach_message(pace, true)
		_coach.text = cue["text"]
		_coach.modulate = cue["colour"]
	_set_dial(det.rate_bpm, counting)
	_set_depth(det.last_depth_m * 100.0, counting)


func _placed_state() -> String:
	var counter = zone.get("_placed_counter")
	return counter.state if counter != null else "waiting"
