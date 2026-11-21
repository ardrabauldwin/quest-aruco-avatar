extends "res://tests/suite.gd"
## Near-silent recordings warn about the microphone; quiet speech and short thanks still pass.

const Check = preload("res://scripts/ai/recording_check.gd")
const RATE := 16000


## PCM16 with a sine burst of the given RMS for `speech_s` seconds, then `silence_s` of hiss.
func _pcm(speech_rms: float, speech_s: float, hiss_rms: float, silence_s: float, stereo := false) -> PackedByteArray:
	var channels := 2 if stereo else 1
	var frames := int((speech_s + silence_s) * RATE)
	var data := PackedByteArray()
	data.resize(frames * channels * 2)
	var speech_frames := int(speech_s * RATE)
	for f in frames:
		var value: float
		if f < speech_frames:
			value = speech_rms * sqrt(2.0) * sin(f * TAU * 220.0 / RATE)
		else:
			value = hiss_rms * sqrt(2.0) * sin(f * TAU * 3700.0 / RATE)   # steady noise of that RMS
		var sample := int(clampf(value, -1.0, 1.0) * 32767.0)
		for c in channels:
			data.encode_s16((f * channels + c) * 2, sample)
	return data


func run() -> Array[String]:
	failures.clear()
	# Levels: the headset recordings of 2026-11-05 never rose clearly above the VAD trigger.
	var silence := Check.level_stats(_pcm(0.0, 0.0, 0.0, 9.0), false, RATE)
	check(Check.near_silent(silence) and absf(float(silence.seconds) - 9.0) < 0.01, "9 s of silence is near-silent: " + str(silence))
	var hiss := Check.level_stats(_pcm(0.0, 0.0, 0.025, 9.0), false, RATE)
	check(Check.near_silent(hiss), "9 s of hiss just above the VAD trigger is near-silent: " + str(hiss))
	var quiet := Check.level_stats(_pcm(0.045, 2.5, 0.01, 1.5), false, RATE)
	check(not Check.near_silent(quiet), "quiet speech (RMS 0.045) is kept: " + str(quiet))
	check(float(quiet.peak_rms) > 0.04 and float(quiet.peak_rms) < 0.05, "peak RMS is measured per 50 ms window: " + str(quiet.peak_rms))
	check(float(quiet.voiced_fraction) > 0.5 and float(quiet.voiced_fraction) < 0.7, "voiced fraction counts the speech windows: " + str(quiet.voiced_fraction))
	var normal := Check.level_stats(_pcm(0.2, 1.0, 0.0, 1.2, true), true, RATE)
	check(not Check.near_silent(normal) and absf(float(normal.seconds) - 2.2) < 0.01, "stereo capture is read frame by frame: " + str(normal))
	var short_quiet := Check.level_stats(_pcm(0.035, 0.6, 0.0, 1.2), false, RATE)
	check(not Check.near_silent(short_quiet), "a short, quiet 'yes' is kept: " + str(short_quiet))

	# Transcripts: Whisper's silence inventions versus real reports, short thanks included.
	check(Check.invented("Thank you.", "en", 8.7) == "silence_phrase", "'Thank you.' from a 9 s recording is invented")
	check(Check.invented("Thank you.", "en", 2.1) == "", "'Thank you.' from a 2 s recording may be real thanks to Anna")
	check(Check.invented("Thank you, Anna.", "en", 8.7) == "", "thanks with a name is real speech")
	check(Check.invented("Thank you.", "en", 2.1, true) == "silence_phrase", "a short silence phrase from a near-silent recording is invented")
	check(Check.invented("Terima kasih.", "en", 11.8) == "silence_phrase", "a foreign thank-you is invented")
	check(Check.invented("Terima kasih.", "en", 1.5) == "silence_phrase", "a foreign thank-you is invented even when short")
	check(Check.invented("آل سيشير كاينة كفار", "de", 3.0) == "foreign_script", "Arabic script is not a German report")
	check(Check.invented("ಎರ್ರಿಗಾಯರ್ಯಾಗಿಯರೆ ನಿಷ್ಟ್.", "de", 3.0) == "foreign_script", "Kannada script is not a German report")
	check(Check.invented("Редактор субтитров А.Семкин Корректор А.Егорова", "de", 3.0) == "foreign_script", "Cyrillic subtitle credits are invented")
	check(Check.invented("Danke.", "de", 9.0) == "silence_phrase", "'Danke.' from a 9 s recording is invented")
	check(Check.invented("Danke, Anna.", "de", 2.0) == "", "short thanks in German are real")
	check(Check.invented("Dziękuję.", "pl", 9.0) == "silence_phrase", "'Dziękuję.' from a 9 s recording is invented")
	for case in [["He is not responding.", "en", 3.0], ["Yes.", "en", 1.4], ["The scene is safe.", "en", 2.4],
			["Die Umgebung ist sicher.", "de", 2.6], ["Ja.", "de", 6.0], ["Er atmet nicht normal, nur Schnappatmung.", "de", 4.5],
			["Miejsce jest bezpieczne.", "pl", 2.5], ["Pacjent nie oddycha prawidłowo.", "pl", 3.2], ["Anno, zadzwoń po karetkę!", "pl", 2.8],
			["Can't I call 112 myself?", "en", 2.9]]:
		check(Check.invented(case[0], case[1], case[2]) == "", "real speech is kept: " + case[0])
	return failures
