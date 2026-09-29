class_name AchievementSystem
extends RefCounted
## Achievements: pure data conditions checked each year and at death.
## Unlocked ids live in the life state and are mirrored to the global meta
## profile by the App layer (so they persist across lives).

var _sim


func _init(sim) -> void:
	_sim = sim


func check(at_death: bool = false) -> void:
	var unlocked: Dictionary = _sim.state.data.achievements
	var ids: Array = _sim.data.table("achievements").keys()
	ids.sort()
	for id in ids:
		if unlocked.has(id):
			continue
		var def: Dictionary = _sim.data.get_def("achievements", id)
		if def.get("on_death", false) != at_death and not def.get("any_time", false):
			continue
		if _sim.cond.check_all(def.get("conditions", []), {}):
			unlocked[id] = _sim.state.data.world_year
			_sim.notify("achievement", "sys.achievement", {"ach": "@ach." + id + ".title"})
			_sim.bus.achievement_unlocked.emit(id)
	_check_challenge()


## Optional challenge chosen at birth ("From teacher to millionaire"...).
func _check_challenge() -> void:
	var id: String = _sim.state.data.get("challenge", "")
	if id == "" or _sim.state.flag("challenge_done", false):
		return
	var def: Dictionary = _sim.data.get_def("challenges", id)
	if def.is_empty() or not _sim.cond.check_all(def.get("goals", []), {}):
		return
	_sim.state.set_flag("challenge_done")
	_sim.notify("achievement", "sys.challenge_done", {"ch": "@ch.%s.title" % id, "n": int(def.get("reward", 20))})
	_sim.add_log("log.challenge_done", {"ch": "@ch.%s.title" % id}, "major")
	_sim.bus.challenge_completed.emit(id, int(def.get("reward", 20)))
