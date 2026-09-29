class_name ActivitySystem
extends RefCounted
## Everything the player can DO during a year. Each activity is data:
## time cost (free-time slots), money cost, effects, stat/skill XP, EXP,
## counters (which create skills by repetition and advance quests), follow-up
## event chances and risks. The year's free time is the real currency:
## studying, training, dating, working extra and raiding dungeons compete.

var _sim


func _init(sim) -> void:
	_sim = sim


# ---------------------------------------------------------------------------
# Time budget
# ---------------------------------------------------------------------------

func start_year(p: Dictionary) -> void:
	var age := int(p.age)
	var slots := 0
	for bracket in _sim.data.bal("time.slots_by_age", []):
		if age >= int(bracket[0]):
			slots = int(bracket[1])
	var job: Dictionary = _sim.career.job_def(p)
	if not job.is_empty():
		slots -= int(_sim.data.bal("time.job_cost." + job.get("hours", "full"), 3))
	if _sim.education.in_school(p) and age >= 18:
		slots -= int(_sim.data.bal("time.college_cost", 2))
	if _sim.crime.in_prison(p):
		slots = int(_sim.data.bal("time.prison_slots", 4))
	slots += int(_sim.gamer.mod("time_slots"))
	p.time = {"slots": maxi(1, slots), "used": 0}


func free_slots(p: Dictionary) -> int:
	return int(p.time.slots) - int(p.time.used)


func spend_time(n: int) -> bool:
	var p: Dictionary = _sim.player()
	if free_slots(p) < n:
		return false
	p.time.used = int(p.time.used) + n
	return true


# ---------------------------------------------------------------------------
# Counters (repetition → skills, quests, titles)
# ---------------------------------------------------------------------------

func bump_counter(key: String, amount: int = 1) -> void:
	var value: int = _sim.state.add_counter(key, amount)
	var p: Dictionary = _sim.player()
	if p.is_empty() or not p.get("is_player", false):
		return
	_sim.skills.on_counter(p, key, value)
	_sim.quests.on_counter(key)


# ---------------------------------------------------------------------------
# Listing
# ---------------------------------------------------------------------------

## Returns [{id, locked_reason}] for activities of a category that are
## visible at the current age (locked ones included so players see goals).
func list(category: String) -> Array:
	var p: Dictionary = _sim.player()
	var out: Array = []
	var ids: Array = _sim.data.table("activities").keys()
	ids.sort_custom(func(a, b): return int(_sim.data.get_def("activities", a).get("order", 50)) < int(_sim.data.get_def("activities", b).get("order", 50)))
	for id in ids:
		var def: Dictionary = _sim.data.get_def("activities", id)
		if def.get("cat", "") != category:
			continue
		if int(p.age) < int(def.get("min_age", 0)) or int(p.age) > int(def.get("max_age", 200)):
			continue
		if def.get("hidden_until", null) != null and not _sim.cond.check_all(def.hidden_until, {}):
			continue
		if _sim.crime.in_prison(p) != def.get("prison", false) and not def.get("anywhere", false):
			continue
		out.append({"id": id, "locked": block_reason(p, def)})
	return out


func block_reason(p: Dictionary, def: Dictionary) -> String:
	if not _sim.cond.check_all(def.get("conditions", []), {}):
		return def.get("lock_key", "act.locked")
	if free_slots(p) < int(def.get("time", 1)):
		return "ui.no_time"
	if float(p.finance.cash) < cost_of(p, def):
		return "ui.no_money"
	if float(def.get("mp", 0)) > float(p.gamer.mp):
		return "ui.no_mp"
	return ""


func cost_of(p: Dictionary, def: Dictionary) -> float:
	return float(def.get("cost", 0)) * float(_sim.finance.country(p).get("cost_of_living", 1.0))


# ---------------------------------------------------------------------------
# Perform
# ---------------------------------------------------------------------------

func perform(id: String, params: Dictionary = {}) -> Dictionary:
	var p: Dictionary = _sim.player()
	var def: Dictionary = _sim.data.get_def("activities", id)
	if def.is_empty() or _sim.is_dead() or _sim.has_pending_events():
		return {"ok": false, "reason": "ui.invalid"}
	var reason := block_reason(p, def)
	if reason != "":
		return {"ok": false, "reason": reason}
	spend_time(int(def.get("time", 1)))
	var cost := cost_of(p, def)
	if cost > 0.0:
		_sim.finance.add_cash(p, -cost)
	p.gamer.mp = float(p.gamer.mp) - float(def.get("mp", 0))
	var ctx := {"gains": {}}
	var result := {"ok": true, "key": "act.%s.res" % id, "params": {}}
	match def.get("special", ""):
		"dungeon":
			result = _sim.dungeons.run(params.get("dungeon", def.get("dungeon", "")), ctx)
		"crime":
			result = _sim.crime.commit(params.get("crime", def.get("crime", "")), ctx)
		"sleep":
			_sim.gamer.refill(p)
		"escape":
			result = _sim.crime.attempt_escape(p)
		"appeal":
			result = _sim.crime.appeal(p)
	_sim.effects.run_all(def.get("effects", []), ctx)
	for stat in def.get("stat_xp", {}):
		var amt := float(def.stat_xp[stat])
		_sim.gamer.add_stat_xp(p, stat, amt)
		ctx.gains["sxp:" + stat] = float(ctx.gains.get("sxp:" + stat, 0)) + amt
	for sid in def.get("skill_xp", {}):
		_sim.skills.add_xp(p, sid, float(def.skill_xp[sid]))
	if def.has("exp"):
		ctx.gains.exp = int(ctx.gains.get("exp", 0)) + _sim.gamer.add_exp(p, float(def.exp) * float(_sim.data.bal("gamer.activity_exp_mult", 1.0)) * (1.0 + float(p.gamer.level) * 0.05))
	if def.has("fitness"):
		p.health.fitness = clampf(float(p.health.fitness) + float(def.fitness), 0, 100)
	if def.has("year_counter"):
		p.year_counters[def.year_counter] = int(p.year_counters.get(def.year_counter, 0)) + 1
	bump_counter(def.get("counter", "act." + id))
	_roll_risk(p, def)
	for e in def.get("events", []):
		if _sim.prob.roll_neutral(float(e.get("chance", 0.1))):
			_sim.events.queue_event(e.event)
	_remember_recent(p, id)
	_sim.titles_check()
	_sim.bus.action_performed.emit(id)
	result.gains = ctx.gains
	return result


func _roll_risk(p: Dictionary, def: Dictionary) -> void:
	var risk: Dictionary = def.get("risk", {})
	if risk.is_empty():
		return
	var chance := float(risk.get("chance", 0.05)) * maxf(0.1, 1.0 - _sim.gamer.effective_stat(p, risk.get("stat", "dex")) * 0.01)
	if _sim.prob.roll_neutral(chance):
		_sim.health.injure(p, risk.get("injury", "injury_minor"))


func _remember_recent(p: Dictionary, id: String) -> void:
	var recent: Array = p.get("recent_actions", [])
	recent.erase(id)
	recent.push_front(id)
	if recent.size() > 6:
		recent.resize(6)
	p.recent_actions = recent


func toggle_favorite(id: String) -> void:
	var favs: Array = _sim.player().favorites
	if favs.has(id):
		favs.erase(id)
	else:
		favs.append(id)
