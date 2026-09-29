class_name QuestSystem
extends RefCounted
## System quests. Data: quests.json
## {"id", "trigger": [conditions] (auto-offer when true), "repeatable": bool,
##  "cooldown": years, "years": deadline, "objectives": [{"counter": "act.study",
##  "target": 5}] or [{"path": "stat.str", "op": ">=", "value": 20}],
##  "rewards": [effects], "penalty": [effects], "hidden": bool}
## Counter objectives measure progress SINCE the quest started.

var _sim


func _init(sim) -> void:
	_sim = sim


func q() -> Dictionary:
	return _sim.player().quests


func start(id: String) -> void:
	var def: Dictionary = _sim.data.get_def("quests", id)
	if def.is_empty() or q().active.has(id):
		return
	var base := {}
	for obj in def.get("objectives", []):
		if obj.has("counter"):
			base[obj.counter] = _sim.state.counter(obj.counter)
	q().active[id] = {"base": base, "deadline": int(_sim.player().age) + int(def.get("years", 3)), "started": _sim.player().age}
	_sim.notify("quest", "sys.quest_new", {"quest": "@quest." + id + ".title"})
	_sim.bus.quest_started.emit(id)


func progress(id: String) -> Array:
	var def: Dictionary = _sim.data.get_def("quests", id)
	var entry: Dictionary = q().active.get(id, {})
	var out: Array = []
	for obj in def.get("objectives", []):
		if obj.has("counter"):
			var cur: int = _sim.state.counter(obj.counter) - int(entry.get("base", {}).get(obj.counter, 0))
			out.append({"cur": mini(cur, int(obj.target)), "target": int(obj.target), "done": cur >= int(obj.target)})
		else:
			var ok: bool = _sim.cond.check(obj, {})
			out.append({"cur": 1 if ok else 0, "target": 1, "done": ok})
	return out


func is_complete(id: String) -> bool:
	for o in progress(id):
		if not o.done:
			return false
	return true


func on_counter(_key: String) -> void:
	check_completion()


func check_completion() -> void:
	for id in q().active.keys():
		if is_complete(id):
			_complete(id)


func _complete(id: String) -> void:
	var def: Dictionary = _sim.data.get_def("quests", id)
	q().active.erase(id)
	q().done.append(id)
	var ctx := {}
	_sim.effects.run_all(def.get("rewards", []), ctx)
	_sim.notify("quest", "sys.quest_done", {"quest": "@quest." + id + ".title"})
	_sim.add_log("log.quest_done", {"quest": "@quest." + id + ".title"}, "system")
	_sim.activities.bump_counter("quests.done")
	_sim.bus.quest_completed.emit(id)


## Year tick: deadlines and new offers.
func process_year() -> void:
	var p: Dictionary = _sim.player()
	for id in q().active.keys():
		if int(p.age) > int(q().active[id].deadline):
			var def: Dictionary = _sim.data.get_def("quests", id)
			q().active.erase(id)
			q().failed.append(id)
			_sim.effects.run_all(def.get("penalty", []), {})
			_sim.notify("quest", "sys.quest_failed", {"quest": "@quest." + id + ".title"})
			_sim.add_log("log.quest_failed", {"quest": "@quest." + id + ".title"}, "warning")
			_sim.bus.quest_failed.emit(id)
	offer_new()


func offer_new() -> void:
	var p: Dictionary = _sim.player()
	var max_active := int(_sim.data.bal("quests.max_active", 4))
	var ids: Array = _sim.data.table("quests").keys()
	ids.sort()
	for id in ids:
		if q().active.size() >= max_active:
			return
		var def: Dictionary = _sim.data.get_def("quests", id)
		if q().active.has(id) or not def.has("trigger"):
			continue
		if q().done.has(id) and not def.get("repeatable", false):
			continue
		if q().failed.has(id) and not def.get("retry", false):
			continue
		var last := int(_sim.state.data.event_history.get("quest_" + id, {}).get("last", -999))
		if int(p.age) - last < int(def.get("cooldown", 0)):
			continue
		if _sim.cond.check_all(def.trigger, {}):
			if def.get("repeatable", false):
				q().done.erase(id)
			_sim.state.data.event_history["quest_" + id] = {"last": p.age}
			start(id)
