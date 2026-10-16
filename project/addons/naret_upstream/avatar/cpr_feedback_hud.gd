extends Node3D
## Camera-attached practice UI; no claim to measure chest depth or actual breaths.
##
## Layout (headset review 2026-09-15):
##   TOP banner   : phase title + the count out of 30 (always drawn on top of everything).
##   LEFT box     : SPEED - half dial red / green (100-120 per minute) / red, needle + number.
##                  Reads "--" until two press intervals exist.
##   RIGHT box    : DEPTH - the last press as a big number, red below 5 cm, green at 5-6 cm,
##                  amber above 6 cm, with a small bar; "--" while hand tracking is unreliable.
##   BOTTOM line  : one instruction about the last press.
## The two boxes are the same size. The 30:2 cycle: after 30 presses the banner counts down the
## two-breath pause. All feedback is visual; the metronome beep is the only sound.
@export var zone: Node3D

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


## The single instruction shown for the last completed press. Depth beats pace: a shallow press
## does no good however well timed. Returns text and colour.
static func coach_message(quality: String, pace_feedback: String, tracking: bool) -> Dictionary:
	if not tracking:
		return {"text": "Keep your hands in view", "colour": COLOR_WARN}
	match quality:
		"shallow":
			return {"text": "Press deeper", "colour": COLOR_BAD}
		"deep":
			return {"text": "Too deep, ease off", "colour": COLOR_WARN}
	match pace_feedback:
		"Press faster":
			return {"text": "Good depth, press faster", "colour": COLOR_WARN}
		"Press slower":
			return {"text": "Good depth, press slower", "colour": COLOR_WARN}
	return {"text": "Good press", "colour": COLOR_GOOD}


## Mean of the counter's rolling press intervals as presses per minute, or 0 with too few.
static func measured_bpm(intervals: Array) -> float:
	if intervals.size() < BPM_SAMPLES_NEEDED:
		return 0.0
	var total := 0.0
	for interval in intervals:
		total += float(interval)
	return 60.0 * intervals.size() / total if total > 0.0 else 0.0


## Colour for a completed press depth: red below the band, green inside, amber above.
static func depth_colour(depth_cm: float) -> Color:
	if depth_cm < DEPTH_GOOD_CM.x:
		return COLOR_BAD
	if depth_cm > DEPTH_GOOD_CM.y:
		return COLOR_WARN
	return COLOR_GOOD


func _ready() -> void:
	# Top banner: title + count
	_panel(Vector2(0.46, 0.105), Vector3(0, 0.115, 0), COLOR_PANEL)
	_title = _label(Vector3(0, 0.148, 0.002), 22)
	_counter = _label(Vector3(0, 0.100, 0.002), 54)
	# Left box: speed dial
	_panel(BOX, Vector3(LEFT_X, BOX_Y, 0), COLOR_PANEL)
	var speed_title := _label(Vector3(LEFT_X, BOX_Y + 0.082, 0.002), 20)
	speed_title.text = "SPEED"
	_dial = _build_dial(Vector3(LEFT_X, BOX_Y - 0.005, 0.002))
	# Right box: depth number + bar
	_panel(BOX, Vector3(RIGHT_X, BOX_Y, 0), COLOR_PANEL)
	var depth_title := _label(Vector3(RIGHT_X, BOX_Y + 0.082, 0.002), 20)
	depth_title.text = "DEPTH"
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
	band_label.text = "target %d-%d per minute" % [int(BPM_GOOD.x), int(BPM_GOOD.y)]
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
	value_label.text = "%d per minute" % int(round(bpm))
	value_label.modulate = COLOR_GOOD if in_band else COLOR_BAD


## Depth box: a big coloured number for the last press, the target under it, and a small bar
## (red track, green 5-6 cm band, white marker for the last press).
func _build_depth(centre: Vector3) -> Dictionary:
	var value_label := _label(centre + Vector3(0, 0.030, 0), 46)
	value_label.text = "--"
	value_label.modulate = COLOR_DIM
	var name_label := _label(centre + Vector3(0, -0.008, 0), 16)
	name_label.text = "Estimated hand travel"
	name_label.modulate = COLOR_DIM
	var band_label := _label(centre + Vector3(0, -0.028, 0), 18)
	band_label.text = "target %d-%d cm" % [int(DEPTH_GOOD_CM.x), int(DEPTH_GOOD_CM.y)]
	band_label.modulate = COLOR_DIM
	var bar_centre := centre + Vector3(0, -0.062, 0)
	var span := DEPTH_RANGE_CM.y - DEPTH_RANGE_CM.x
	_panel(Vector2(GAUGE_W, 0.012), bar_centre, COLOR_TRACK_RED, PRIORITY_MARK)
	var band_w := GAUGE_W * (DEPTH_GOOD_CM.y - DEPTH_GOOD_CM.x) / span
	var band_x := -GAUGE_W * 0.5 + GAUGE_W * ((DEPTH_GOOD_CM.x + DEPTH_GOOD_CM.y) * 0.5 - DEPTH_RANGE_CM.x) / span
	_panel(Vector2(band_w, 0.012), bar_centre + Vector3(band_x, 0, 0.0005), COLOR_TRACK_GREEN, PRIORITY_MARK)
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
	var colour := depth_colour(depth_cm)
	value_label.text = "%.1f cm" % depth_cm
	value_label.modulate = colour
	var fraction := clampf((depth_cm - DEPTH_RANGE_CM.x) / (DEPTH_RANGE_CM.y - DEPTH_RANGE_CM.x), 0.0, 1.0)
	var bar_centre: Vector3 = _depth["bar_centre"]
	marker.visible = true
	marker.position.x = bar_centre.x - GAUGE_W * 0.5 + GAUGE_W * fraction
	marker.material_override.albedo_color = colour


func _process(_delta: float) -> void:
	visible = zone != null and zone.is_visible_in_tree() and not zone.get("_paused")
	if not visible:
		return
	var session = zone.get("motion_session")
	var tracking: bool = session.tracking_available
	var travel_cm: float = session.last_stroke_travel_m * 100.0
	var bpm := measured_bpm(session._bpm_samples)

	if session.phase == "breathing":
		_title.text = "GIVE 2 BREATHS"
		_counter.text = "%.1f s" % session.breathing_remaining_s
		_coach.text = "30 compressions done - give 2 breaths"
		_coach.modulate = COLOR_TEXT
		_status.text = "then continue pressing with the beep"
		_set_depth(0.0, false)
		_set_dial(0.0, false)
	elif not session.active:
		var placed: bool = zone.get("correct_placement")
		_title.text = "PRESS WITH THE BEEP" if placed else "PLACE HANDS"
		_counter.text = "0 / 30"
		_coach.text = "Follow the beep" if placed else "Put both hands on the green target"
		_coach.modulate = COLOR_TEXT if placed else COLOR_GOOD
		_status.text = zone.hand_tracking_status
		_set_depth(0.0, false)
		_set_dial(0.0, false)
	else:
		_title.text = "COMPRESS"
		_counter.text = "%d / 30" % session.count
		var cue := coach_message(session.last_stroke_quality, session.feedback, tracking)
		_coach.text = cue["text"]
		_coach.modulate = cue["colour"]
		_status.text = zone.hand_tracking_status
		# The last completed press stays readable through short tracking dropouts; only the
		# live marker needs current tracking.
		_set_depth(travel_cm, session.total_count > 0)
		_set_dial(bpm, session.total_count > 0)
