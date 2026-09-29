class_name DataRegistry
extends RefCounted
## Loads every content table from res://data. Code runs rules, content comes
## from here. Tables are Dictionaries keyed by id so lookups are O(1).
## NOTE: exports must include "*.json" in the non-resource export filter.

const DATA_DIR := "res://data/"

## Tables indexed by "id".
const TABLES := [
	"activities", "jobs", "education", "skills", "titles", "quests",
	"monsters", "dungeons", "diseases", "countries", "traits", "items",
	"achievements", "interactions", "world_events", "properties", "crimes",
	"factions", "stats", "special_careers", "pets", "possessions", "challenges", "cliques", "clubs", "interview_questions", "ribbons", "lawyers", "lawsuits", "gangs",
	"dialogue_replies", "npc_life", "marks", "tech_eras", "parties", "place_types",
]

var tables: Dictionary = {}
var events: Dictionary = {}
var dialogue: Dictionary = {}
var balance: Dictionary = {}
var names: Dictionary = {}


func load_all() -> DataRegistry:
	for table in TABLES:
		tables[table] = _index(_read_json(DATA_DIR + table + ".json"))
	balance = _read_json(DATA_DIR + "balance.json")
	names = _read_json(DATA_DIR + "names.json")
	events = _load_dir("events")
	dialogue = _load_dir("dialogue")
	return self


func _load_dir(sub: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(DATA_DIR + sub)
	if dir:
		var files := Array(dir.get_files())
		files.sort()
		for f in files:
			if f.ends_with(".json"):
				out.merge(_index(_read_json(DATA_DIR + sub + "/" + f)))
	return out


func table(name: String) -> Dictionary:
	return tables.get(name, {})


func get_def(table_name: String, id: String) -> Dictionary:
	return table(table_name).get(id, {})


## Balance lookup with dotted path: bal("finance.tax_rate", 0.2)
func bal(path: String, default = 0.0):
	var node = balance
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(part):
			return default
		node = node[part]
	return node


func _index(raw) -> Dictionary:
	var out := {}
	if typeof(raw) == TYPE_ARRAY:
		for entry in raw:
			if typeof(entry) == TYPE_DICTIONARY and entry.has("id"):
				out[entry.id] = entry
	return out


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		push_warning("Data file missing: " + path)
		return []
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return []
	return json.data
