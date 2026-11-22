extends "res://tests/suite.gd"
## Two builds from one source: the normal app counts with the placed palm counter; only a
## build with the feature tag "detector_counter" counts with Dennis's NaretCprDetector.

func run() -> Array[String]:
	failures.clear()
	var interaction := NaretXRInteraction.new()
	check(not OS.has_feature("detector_counter") and interaction.counter_mode == "zone", "the normal build counts with the palm counter")
	check(interaction.detector is NaretCprDetector, "the detector runs alongside for the sensor log")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check("detector_counter" in str(presets.get_value("preset.1", "custom_features", "")) and not "detector_counter" in str(presets.get_value("preset.0", "custom_features", "")), "only the detector preset carries the tag")
	check(presets.get_value("preset.1.options", "package/unique_name", "") != presets.get_value("preset.0.options", "package/unique_name", ""), "the detector build installs beside the app")
	interaction.free()
	return failures
