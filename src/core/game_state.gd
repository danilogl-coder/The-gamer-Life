class_name GameState
extends RefCounted
## Central persistent state. Pure data (Dictionaries/Arrays/primitives) so it
## serializes to JSON trivially and migrations can patch it. No gameplay rules
## live here: systems read and write through the helpers below.

const SAVE_VERSION := 1

var data: Dictionary = {}


static func create_empty(p_seed: int) -> GameState:
	var gs := GameState.new()
	gs.data = {
		"save_version": SAVE_VERSION,
		"seed": p_seed,
		"rng_state": 0,
		"world_year": 2000,
		"generation": 1,
		"next_id": 1,
		"player_id": "",
		"npcs": {},
		"world": {},
		"flags": {},
		"counters": {},
		"scheduled": [],
		"pending_events": [],
		"timeline": [],
		"event_history": {},
		"achievements": {},
		"legacy": {"soul_points": 0, "dynasty": "", "lives": [], "perks": []},
		"dead": false,
		"death": {},
	}
	return gs


## ---- identity -------------------------------------------------------------

func new_id(prefix: String) -> String:
	var n: int = data.next_id
	data.next_id = n + 1
	return "%s%d" % [prefix, n]


## ---- characters -----------------------------------------------------------

func player() -> Dictionary:
	return data.npcs.get(data.player_id, {})


func npc(id: String) -> Dictionary:
	return data.npcs.get(id, {})


func has_npc(id: String) -> bool:
	return data.npcs.has(id)


func add_npc(character: Dictionary) -> void:
	data.npcs[character.id] = character


## ---- flags & counters -----------------------------------------------------

func flag(name: String, default = null):
	return data.flags.get(name, default)


func set_flag(name: String, value = true) -> void:
	data.flags[name] = value


func counter(key: String) -> int:
	return int(data.counters.get(key, 0))


func add_counter(key: String, amount: int = 1) -> int:
	var v := counter(key) + amount
	data.counters[key] = v
	return v


## ---- timeline -------------------------------------------------------------

## Timeline entries store localization keys + params, never final text.
func add_log(key: String, params: Dictionary = {}, kind: String = "info") -> Dictionary:
	var p := player()
	var entry := {
		"age": p.get("age", 0),
		"year": data.world_year,
		"key": key,
		"params": params,
		"kind": kind,
	}
	data.timeline.append(entry)
	return entry


## ---- generic path access (used by the data driven condition system) ------

static func read_path(root, path: String, default = null):
	var node = root
	for part in path.split("."):
		match typeof(node):
			TYPE_DICTIONARY:
				if not node.has(part):
					return default
				node = node[part]
			TYPE_ARRAY:
				if not part.is_valid_int() or int(part) >= node.size():
					return default
				node = node[int(part)]
			_:
				return default
	return node


static func write_path(root: Dictionary, path: String, value) -> void:
	var parts := path.split(".")
	var node: Dictionary = root
	for i in parts.size() - 1:
		if not node.has(parts[i]) or typeof(node[parts[i]]) != TYPE_DICTIONARY:
			node[parts[i]] = {}
		node = node[parts[i]]
	node[parts[parts.size() - 1]] = value
