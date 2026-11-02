extends "res://tests/suite.gd"

class Endpoint extends NaretAudioManager:
	var endings := 0
	func begin_recording() -> void:
		recording = true
		_speech_seen = true
	func end_recording() -> void:
		recording = false
		endings += 1

func run() -> Array[String]:
	failures.clear()
	var endpoint := Endpoint.new()
	endpoint.update_voice_activity(0.03, 0)
	check(endpoint.recording, "above-threshold sound activates recording")
	endpoint.update_voice_activity(0.0, 100)
	endpoint.update_voice_activity(0.0, 500)
	check(endpoint.endings == 0, "short pause does not end a report")
	endpoint.update_voice_activity(0.0, 1300)
	check(endpoint.endings == 0, "full 1200 ms silence boundary is preserved")
	endpoint.update_voice_activity(0.0, 1301)
	check(endpoint.endings == 1, "over 1200 ms trailing silence ends once")
	endpoint.free()
	endpoint = Endpoint.new()
	endpoint.update_voice_activity(0.03, 0)
	endpoint.update_voice_activity(0.0, 100)
	endpoint.update_voice_activity(0.03, 1000)
	endpoint.update_voice_activity(0.0, 1100)
	endpoint.update_voice_activity(0.0, 1500)
	check(endpoint.endings == 0, "resumed speech resets the silence timer")
	endpoint.update_voice_activity(0.0, 2301)
	check(endpoint.endings == 1, "new silence interval completes normally")
	endpoint.free()
	return failures
