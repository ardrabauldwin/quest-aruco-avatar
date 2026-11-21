extends "res://tests/suite.gd"
## The status lines and the spoken "cannot hear you" replies live in data/ui_texts.json
## (11 Nov 2026), one entry per status with all three languages.

func run() -> Array[String]:
	failures.clear()
	check(not NaretLanguage.STATUS.is_empty(), "status texts loaded from ui_texts.json")
	for key: String in NaretLanguage.STATUS:
		for lang in ["en", "de", "pl"]:
			check(not NaretLanguage.status(key, lang).is_empty(), "status %s has a %s text" % [key, lang])
	for key in ["microphone_silent", "speech_not_understood", "recording", "transcribing", "offline", "marker_tracked"]:
		check(NaretLanguage.STATUS.has(key), "known status has a text: " + key)
	check(NaretLanguage.status("microphone_silent", "de") != NaretLanguage.status("microphone_silent", "pl"), "spoken reply is translated, not copied")
	check(NaretLanguage.status("no_such_status", "de") == "no_such_status", "unknown status shows its key")
	for key in ["notice.waiting_placement", "anna.calling_112"]:
		for lang in ["en", "de", "pl"]:
			check(NaretLanguage.text(key, lang) != key, "moved notice exists in %s: %s" % [lang, key])
	return failures
