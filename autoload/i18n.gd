extends Node

signal locale_changed(locale: String)

const CATALOG_PATHS := {
	"en": "res://localization/en.json",
}

var _catalogs: Dictionary = {}
var _locale := "en"


func _ready() -> void:
	for locale: String in CATALOG_PATHS:
		_catalogs[locale] = _load_catalog(str(CATALOG_PATHS[locale]))
	# Astro Quest ships in English only: no saved, OS or browser locale switching.
	_locale = "en"


## Single-language game: every locale resolves to English.
static func detect_locale(_os_locale: String) -> String:
	return "en"


static func resolve_locale(_saved: String, _os_locale: String) -> String:
	return "en"


func _load_catalog(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("I18n: missing catalog " + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("I18n: invalid catalog " + path)
		return {}
	return parsed


func text(key: String, replacements: Dictionary = {}) -> String:
	var active: Dictionary = _catalogs.get(_locale, {})
	var fallback: Dictionary = _catalogs.get("en", {})
	var result := str(active.get(key, fallback.get(key, key)))
	for token: Variant in replacements:
		result = result.replace("{%s}" % str(token), str(replacements[token]))
	return result


func t(key: String, replacements: Dictionary = {}) -> String:
	return text(key, replacements)


func get_locale() -> String:
	return _locale


func set_locale(locale: String) -> void:
	if not _catalogs.has(locale):
		return
	# An explicit choice is persisted even when it matches the auto-detected language.
	if SaveStore.get_locale() != locale:
		SaveStore.set_locale(locale)
	if locale == _locale:
		return
	_locale = locale
	locale_changed.emit(locale)


func toggle_locale() -> void:
	pass


func catalog_keys(locale: String) -> Array:
	var catalog: Dictionary = _catalogs.get(locale, {})
	return catalog.keys()
