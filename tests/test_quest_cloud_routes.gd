extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var asr := "http://127.0.0.1:8767/inference"
	var ai := "http://127.0.0.1:8768"
	var quest := NaretUniAPIClient.recognition_routes(asr, ai, true)
	check(quest.asr.is_empty() and quest.ai.is_empty(), "Quest ignores stale PC ASR, interpretation and TTS overrides")
	var desktop := NaretUniAPIClient.recognition_routes(asr, ai, false)
	check(desktop.asr == asr and desktop.ai == ai, "desktop development routes remain usable")
	var clean := NaretUniAPIClient.recognition_routes("", "", true)
	check(clean.asr.is_empty() and clean.ai.is_empty(), "cloud-only configuration remains cloud-only")
	return failures
