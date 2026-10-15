extends "res://tests/suite.gd"
const Convert = preload("res://scripts/tracking/colored_marker_image.gd")
func run() -> Array[String]:
	failures.clear()
	var rgb := Image.create_from_data(2, 1, false, Image.FORMAT_RGB8, PackedByteArray([255, 128, 0, 0, 0, 255]))
	var output := Convert.convert(rgb)
	check(output.get_data() == PackedByteArray([0, 255]), "Orange black, blue white")
	check(rgb.get_format() == Image.FORMAT_RGB8, "Original camera image preserved")
	var luminance := Image.create_from_data(2, 1, false, Image.FORMAT_R8, PackedByteArray([210, 40]))
	check(Convert.convert(luminance).get_data() == PackedByteArray([45, 215]), "Quest luminance polarity reversed")
	check(output.get_width() == 2 and output.get_height() == 1, "Geometry preserved")
	return failures
