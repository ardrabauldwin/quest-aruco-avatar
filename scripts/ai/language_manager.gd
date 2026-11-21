class_name NaretLanguage
extends RefCounted
## Loads every fixed text of the app from data/ui_texts.json and hands it out by key and
## language. No text lives in code any more (11 Nov 2026): a translator edits the JSON, the
## tests check that German, Polish and English carry the same keys.

const PATH := "res://data/ui_texts.json"
const SUPPORTED := ["de", "pl", "en"]

static var _data: Dictionary = _load()
static var STRINGS: Dictionary = _data.get("strings", {})
static var UI_EN: Dictionary = _data.get("ui_en", {})
static var STATUS: Dictionary = _data.get("status", {})

static func _load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		push_error("NaretLanguage: missing " + PATH)
		return {"strings": {"de": {}, "pl": {}, "en": {}}, "ui_en": {}, "status": {}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_error("NaretLanguage: " + PATH + " is not valid JSON")
		return {"strings": {"de": {}, "pl": {}, "en": {}}, "ui_en": {}, "status": {}}
	return parsed

## A keyed text ("instruction.cpr") in the selected language; German, then the key, as fallback.
static func text(key: String, lang: String = "de") -> String:
	var german: Dictionary = STRINGS.get("de", {})
	var selected: Dictionary = STRINGS.get(lang, german)
	return str(selected.get(key, german.get(key, key)))

## A menu or panel label written in German at the call site, with its Polish twin; English
## comes from the ui_en table.
static func ui(german: String, polish: String, lang: String) -> String:
	if lang == "en": return str(UI_EN.get(german, german))
	return polish if lang == "pl" else german

static func next_language(lang: String) -> String:
	return SUPPORTED[(SUPPORTED.find(lang) + 1) % SUPPORTED.size()]

## A dashboard status line or spoken "cannot hear you" reply by status key and language;
## the key itself when the status has no text.
static func status(key: String, lang: String) -> String:
	var entry: Dictionary = STATUS.get(key, {})
	return str(entry.get(lang, entry.get("en", key)))
