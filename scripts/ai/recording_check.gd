class_name NaretRecordingCheck
extends RefCounted
## Tells a near-silent recording and an invented transcript from real speech.
##
## Headset 2026-11-05: the microphone delivered 9-12 s of near-silence three times in a row;
## Whisper wrote "" , "Thank you." and "Terima kasih." (its usual inventions for silence),
## the app treated them as chat and fell silent, and the trainee thought it had frozen.
## level_stats() measures the captured PCM before upload; invented() judges the transcript
## afterwards. Both are conservative: quiet speech must still get through.

## Peak 50 ms window RMS below this (float scale, like the VAD level): the recording never got
## clearly louder than the VAD trigger (0.02), so nobody spoke into the microphone.
const SILENT_PEAK_RMS := 0.03
const WINDOW_S := 0.05
## A silence phrase from a recording at least this long is invented; shorter ones may be a real
## "thank you" to the witness.
const LONG_RECORDING_S := 4.0

## What Whisper writes for silence or noise, lower case, no punctuation.
const SILENCE_PHRASES := [
	"thank you", "thanks", "thank you very much", "thank you for watching", "thanks for watching",
	"thank you for listening", "bye", "goodbye", "you", "the end", "subscribe", "please subscribe",
	"see you in the next video", "see you next time", "subtitles by the amara org community",
	"danke", "vielen dank", "danke schön", "dankeschön", "danke fürs zuschauen", "danke fürs zusehen",
	"untertitel im auftrag des zdf", "untertitelung des zdf", "untertitel von", "tschüss", "bis zum nächsten mal",
	"dziękuję", "dziękuję bardzo", "dziękuję za uwagę", "dzięki za oglądanie", "do zobaczenia",
	"napisy stworzone przez społeczność amara org", "napisy",
	"terima kasih", "gracias", "merci", "grazie", "obrigado", "amara org",
]


## {seconds, peak_rms, voiced_fraction} of 16-bit PCM as AudioEffectRecord delivers it.
static func level_stats(data: PackedByteArray, stereo: bool, mix_rate: int) -> Dictionary:
	var channels := 2 if stereo else 1
	var frame_bytes := 2 * channels
	var frames := data.size() / frame_bytes
	var window := maxi(1, int(mix_rate * WINDOW_S))
	var peak := 0.0
	var voiced := 0
	var windows := 0
	var i := 0
	while i < frames:
		var count := mini(window, frames - i)
		var total := 0.0
		for f in range(i, i + count):
			var sum := 0.0
			for c in channels:
				var at := (f * channels + c) * 2
				var sample := data.decode_s16(at) / 32768.0
				sum += sample
			var mono := sum / channels
			total += mono * mono
		var rms := sqrt(total / count)
		peak = maxf(peak, rms)
		if rms > NaretAudioManager.VAD_THRESHOLD:
			voiced += 1
		windows += 1
		i += count
	return {"seconds": float(frames) / maxf(1.0, mix_rate), "peak_rms": peak,
		"voiced_fraction": float(voiced) / maxf(1.0, windows)}


static func near_silent(stats: Dictionary) -> bool:
	return float(stats.get("peak_rms", 0.0)) < SILENT_PEAK_RMS


## "" when the transcript may be real speech; otherwise why it is invented:
## "foreign_script" (not the Latin alphabet the three languages use) or "silence_phrase".
static func invented(text: String, language: String, recording_s: float, silent := false) -> String:
	var letters := 0
	var foreign := 0
	for ch in text:
		var code := ch.unicode_at(0)
		if not ch.strip_edges().is_empty() and code > 0x40 and (ch.to_lower() != ch.to_upper() or code > 0x2FF):
			letters += 1
			if code > 0x024F:   # beyond Latin Extended-B: Cyrillic, Arabic, Indic, CJK ...
				foreign += 1
	if letters > 0 and foreign * 2 >= letters:
		return "foreign_script"
	var clean := _normalise(text)
	if clean in SILENCE_PHRASES and (recording_s >= LONG_RECORDING_S or silent or language not in ["en", "de", "pl"]):
		return "silence_phrase"
	# A foreign-language thank-you never comes from an English, German or Polish trainee.
	if clean in ["terima kasih", "gracias", "merci", "grazie", "obrigado", "amara org"]:
		return "silence_phrase"
	return ""


static func _normalise(text: String) -> String:
	var clean := text.to_lower()
	for mark in [".", ",", "!", "?", ";", ":", "\"", "'", "’", "„", "“", "”", "(", ")", "-", "…", "/"]:
		clean = clean.replace(mark, " ")
	while "  " in clean:
		clean = clean.replace("  ", " ")
	return clean.strip_edges()
