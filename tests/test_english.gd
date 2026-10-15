extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	for key in NaretLanguage.STRINGS.de:
		check(NaretLanguage.STRINGS.en.has(key), "English translation exists: " + key)
	check(NaretLanguage.next_language("pl") == "en", "headset language button reaches English")
	check(NaretLanguage.next_language("en") == "de", "language cycle wraps")
	check(NaretLanguage.infer_action("Please call 112") == "call_emergency", "English emergency-call intent")
	check(NaretLanguage.infer_action("Do not call 112") == "", "English negation is respected")
	check(NaretLLMOrchestrator.fallback_reply("Thank you", "en").language == "en", "English reply remains English")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	var english := {}
	for item in manifest.clips:
		if item.language == "en":
			english[item.key] = true
			check(ResourceLoader.exists("res://assets/audio/" + item.file), "English audio exists: " + item.key)
	for key in ["start", "check_patient", "call_help", "cpr", "recovery", "calm", "help", "thanks", "anna_arrive", "anna_urge", "anna_name"]:
		check(english.has(key), "active script has English audio: " + key)
	return failures
