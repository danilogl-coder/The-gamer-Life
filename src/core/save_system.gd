class_name SaveSystem
extends RefCounted
## JSON persistence with versioning + migrations.
##  - user://saves/slot_N.json : one life/dynasty (GameState.data)
##  - user://meta.json         : cross-life profile (soul points, achievements,
##                               settings, dynasties)
## JSON numbers come back as floats, so loaded data is normalized (integral
## floats → int). The RNG state is stored as a string to keep 64-bit precision.

const SAVE_DIR := "user://saves/"
const META_PATH := "user://meta.json"

## version -> Callable(data: Dictionary) -> void, upgrading to version+1.
static var MIGRATIONS: Dictionary = {
	# 1: func(d): d["new_field"] = default  (example for the next version)
}


static func slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot


static func save_life(data: Dictionary, slot: int = 1) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	return _write(slot_path(slot), data)


static func load_life(slot: int = 1) -> Dictionary:
	var data := _read(slot_path(slot))
	if data.is_empty():
		return {}
	return migrate(data)


static func has_save(slot: int = 1) -> bool:
	return FileAccess.file_exists(slot_path(slot))


static func delete_life(slot: int = 1) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(slot_path(slot))


static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	while version < GameState.SAVE_VERSION:
		if MIGRATIONS.has(version):
			MIGRATIONS[version].call(data)
		version += 1
		data.save_version = version
	return data


static func save_meta(meta: Dictionary) -> Error:
	return _write(META_PATH, meta)


static func load_meta() -> Dictionary:
	return _read(META_PATH)


static func _write(path: String, data: Dictionary) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data))
	f.close()
	# Atomic-ish replace so a crash mid-write never corrupts the save.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Corrupt save: " + path)
		return {}
	return normalize(parsed)


static func normalize(v):
	match typeof(v):
		TYPE_FLOAT:
			if is_equal_approx(v, roundf(v)) and absf(v) < 9.0e15:
				return int(v)
			return v
		TYPE_DICTIONARY:
			for k in v.keys():
				v[k] = normalize(v[k])
			return v
		TYPE_ARRAY:
			for i in v.size():
				v[i] = normalize(v[i])
			return v
	return v
