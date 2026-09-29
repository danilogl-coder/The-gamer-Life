extends Node
## Autoload "App": composition root for the running game. Holds the data
## registry, localization, event bus and the LifeSimulation, and bridges the
## simulation with persistence (autosave each year) and the meta profile.

var data: DataRegistry
var loc: Localization
var bus: EventBus
var sim: LifeSimulation
var meta: Dictionary = {}
var slot := 1


func _ready() -> void:
	data = DataRegistry.new().load_all()
	meta = SaveSystem.load_meta()
	meta.merge({"locale": _default_locale(), "soul_points": 0, "achievements": {}, "lives": [], "dev": false}, false)
	loc = Localization.new(meta.locale)
	bus = EventBus.new()
	sim = LifeSimulation.new(data, bus)
	bus.year_advanced.connect(func(_a): autosave())
	bus.character_died.connect(_on_death)
	bus.achievement_unlocked.connect(func(id): meta.achievements[id] = true; save_meta())


func t(key: String, params: Dictionary = {}) -> String:
	return loc.t(key, params)


func tr_entry(entry: Dictionary) -> String:
	return loc.t_entry(entry)


func set_locale(code: String) -> void:
	loc.set_locale(code)
	meta.locale = code
	save_meta()
	bus.state_changed.emit()


func has_save() -> bool:
	return SaveSystem.has_save(slot)


func start_new_life(options: Dictionary = {}) -> void:
	var seed := int(options.get("seed", Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system())))
	options.legacy = {"soul_points": 0, "lives": meta.lives.slice(-20)}
	sim.new_life(seed, options)
	autosave()


func continue_life() -> bool:
	var saved := SaveSystem.load_life(slot)
	if saved.is_empty():
		return false
	sim.load_state(saved)
	return true


func autosave() -> void:
	SaveSystem.save_life(sim.snapshot(), slot)


func save_meta() -> void:
	SaveSystem.save_meta(meta)


func _on_death(summary: Dictionary) -> void:
	meta.soul_points = int(meta.soul_points) + int(summary.soul_points)
	meta.lives.append({"name": summary.name, "age": summary.age, "level": summary.level, "worth": summary.net_worth, "gen": summary.generation})
	save_meta()
	autosave()


func _default_locale() -> String:
	return "pt" if OS.get_locale_language() == "pt" else "en"
