class_name NaretEKGRenderer
extends Control

var ekg: NaretEKG
var _points := PackedVector2Array()
var _accumulator := 0.0
const SAMPLES := 320

func _ready() -> void:
	_points.resize(SAMPLES)
	custom_minimum_size = Vector2(0, 90)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator >= 1.0 / 36.0:
		_accumulator = 0.0
		queue_redraw()

func _draw() -> void:
	for x in range(0, int(size.x), 22):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.3, 0.5, 0.5, 0.065))
	for y in range(0, int(size.y), 22):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.3, 0.5, 0.5, 0.065))
	if not ekg: return
	for i in SAMPLES:
		var fraction := float(i) / float(SAMPLES - 1)
		var t := ekg.time - (1.0 - fraction) * 5.0
		_points[i] = Vector2(fraction * size.x, size.y * 0.55 - ekg.sample(t) * size.y * 0.37)
	draw_polyline(_points, Color("b7f581"), 2.1, true)
	draw_circle(_points[SAMPLES - 1], 3.8, Color("d2ffa9"))
