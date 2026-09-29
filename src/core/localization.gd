class_name Localization
extends RefCounted
## Key based localization. Texts never live in code: code asks for keys like
## "ev.bully.title" and passes params that replace {name} tokens.

const LOCALE_DIR := "res://locale/"
const SUPPORTED := ["pt", "en"]
const FALLBACK := "en"

var locale: String = "pt"
var _strings: Dictionary = {}
var _fallback: Dictionary = {}


func _init(p_locale: String = "pt") -> void:
	_fallback = _load(FALLBACK)
	set_locale(p_locale)


func set_locale(p_locale: String) -> void:
	locale = p_locale if p_locale in SUPPORTED else FALLBACK
	_strings = _load(locale)


func has(key: String) -> bool:
	return _strings.has(key) or _fallback.has(key)


func t(key: String, params: Dictionary = {}) -> String:
	var text: String = _strings.get(key, _fallback.get(key, key))
	for p in params:
		text = text.replace("{" + str(p) + "}", str(params[p]))
	return text


## Resolves a log/UI entry { "key": ..., "params": {...} } where params may
## themselves be keys prefixed with "@" (translated at display time, so a
## language switch retranslates old timeline entries).
func t_entry(entry: Dictionary) -> String:
	var params: Dictionary = {}
	var raw: Dictionary = entry.get("params", {})
	for p in raw:
		var v = raw[p]
		if typeof(v) == TYPE_STRING and v.begins_with("@"):
			v = t(v.substr(1))
		params[p] = v
	return t(entry.get("key", ""), params)


## Every *.json inside locale/<code>/ is merged, so content packs can ship
## their own string files.
func _load(code: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(LOCALE_DIR + code)
	if dir == null:
		return out
	var files := Array(dir.get_files())
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(LOCALE_DIR + code + "/" + f))
		if typeof(data) == TYPE_DICTIONARY:
			out.merge(data, true)
		else:
			push_error("Locale file invalid: %s/%s" % [code, f])
	return out
