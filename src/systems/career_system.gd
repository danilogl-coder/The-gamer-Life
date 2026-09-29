class_name CareerSystem
extends RefCounted
## Jobs (normal, informal, part-time and Awakened guild careers), hiring,
## performance, promotion, firing, retirement and factions.
## Performance uses the job's key Gamer stat: a STR monster makes a great
## builder, an INT monster a great surgeon. That is how the System leaks into
## ordinary careers.

var _sim


func _init(sim) -> void:
	_sim = sim


func job_def(p: Dictionary) -> Dictionary:
	return _sim.data.get_def("jobs", p.career.job)


func is_employed(p: Dictionary) -> bool:
	return p.career.job != ""


func current_salary(p: Dictionary) -> float:
	if not is_employed(p) or _sim.crime.in_prison(p):
		return float(p.career.get("pension", 0.0))
	return float(p.career.salary) * _sim.world.salary_mult()


func level_mult(level: int) -> float:
	return pow(float(_sim.data.bal("career.promotion_mult", 1.22)), level)


## "" if the player could apply, otherwise a localization key with the reason.
func block_reason(p: Dictionary, id: String) -> String:
	var def: Dictionary = _sim.data.get_def("jobs", id)
	if def.is_empty():
		return "ui.invalid"
	if p.career.job == id:
		return "job.block.current"
	if int(p.age) < int(def.get("min_age", 18)):
		return "job.block.age"
	if int(p.age) > int(def.get("max_age", 70)):
		return "job.block.old"
	if _sim.crime.in_prison(p):
		return "job.block.prison"
	for req in def.get("education", []):
		if not _sim.education.has_completed(p, req):
			return "job.block.education"
	for stat in def.get("stat_req", {}):
		if _sim.gamer.effective_stat(p, stat) < float(def.stat_req[stat]):
			return "job.block.stat"
	if def.has("faction") and p.faction.id != def.faction:
		return "job.block.faction"
	if def.get("no_record", false) and not p.criminal.record.is_empty():
		return "job.block.record"
	if not _sim.cond.check_all(def.get("conditions", []), {}):
		return "job.block.locked"
	return ""


func apply(p: Dictionary, id: String) -> Dictionary:
	var reason := block_reason(p, id)
	if reason != "":
		return {"ok": false, "reason": reason}
	var def: Dictionary = _sim.data.get_def("jobs", id)
	var spec := {
		"base": float(def.get("hire_chance", 0.55)) - float(_sim.state.data.world.unemployment),
		"mods": [
			{"path": "stat.cha", "per": 0.006, "offset": 10.0, "max": 0.25},
			{"path": "stat." + def.get("key_stat", "int"), "per": 0.004, "offset": 10.0, "max": 0.2},
			{"path": "player.attrs.reputation", "per": 0.003, "offset": 50.0},
			{"path": "mod.interview", "per": 1.0},
		],
	}
	if not p.criminal.record.is_empty():
		spec.base = float(spec.base) - 0.2
	_sim.activities.bump_counter("job.applications")
	if not _sim.prob.roll_spec(spec):
		_sim.add_log("log.job_rejected", {"job": "@job." + id}, "info")
		return {"ok": false, "reason": "job.rejected"}
	hire(p, id)
	return {"ok": true, "key": "job.hired", "params": {"job": "@job." + id}}


func hire(p: Dictionary, id: String, _forced: bool = false) -> void:
	var def: Dictionary = _sim.data.get_def("jobs", id)
	if def.is_empty():
		return
	if is_employed(p):
		_archive(p, "changed")
	var c: Dictionary = _sim.finance.country(p)
	p.career.job = id
	p.career.level = 0
	p.career.years = 0
	p.career.performance = 55.0
	p.career.salary = float(def.salary) * float(c.get("salary_mult", 1.0)) * (1.0 + _sim.gamer.mod("salary"))
	p.career.pension = 0.0
	_sim.add_log("log.job_start", {"job": "@job." + id}, "major")
	_sim.activities.bump_counter("job.hired")
	_sim.activities.bump_counter("job.cat." + def.get("cat", "misc"))
	_sim.npcs.spawn_workplace(p, def)
	_sim.bus.job_changed.emit(id)


func fire(p: Dictionary, reason: String = "fired") -> void:
	if not is_employed(p):
		return
	_archive(p, reason)
	_sim.add_log("log.job_" + reason, {"job": "@job." + p.career.job}, "major")
	if reason == "fired":
		_sim.activities.bump_counter("job.fired")
		p.attrs.happiness = clampf(float(p.attrs.happiness) - 12, 0, 100)
		p.attrs.reputation = clampf(float(p.attrs.reputation) - 4, 0, 100)
	p.career.job = ""
	p.career.salary = 0.0
	for id in p.rels.keys():
		if p.rels[id].role in ["boss", "coworker"]:
			_sim.relations.set_role(id, "acquaintance")
	_sim.bus.job_changed.emit("")


func retire(p: Dictionary) -> Dictionary:
	if not is_employed(p) or int(p.age) < int(_sim.data.bal("career.retire_age", 60)):
		return {"ok": false, "reason": "job.block.retire"}
	var pension := float(p.career.salary) * float(_sim.data.bal("career.pension_rate", 0.45)) * minf(1.0, float(p.career.get("total_years", 0) + int(p.career.years)) / 30.0)
	fire(p, "retired")
	p.career.pension = pension
	return {"ok": true, "key": "job.retired", "params": {"pension": int(pension)}}


func _archive(p: Dictionary, reason: String) -> void:
	p.career.history.append({"job": p.career.job, "years": p.career.years, "level": p.career.level, "end": reason, "age": p.age})
	p.career.total_years = int(p.career.get("total_years", 0)) + int(p.career.years)


# ---------------------------------------------------------------------------
# Year tick
# ---------------------------------------------------------------------------

func process_year(p: Dictionary) -> void:
	if not is_employed(p) or _sim.crime.in_prison(p):
		if _sim.crime.in_prison(p) and is_employed(p):
			fire(p, "fired")
		return
	var def := job_def(p)
	p.career.years = int(p.career.years) + 1
	_update_performance(p, def)
	p.attrs.stress = clampf(float(p.attrs.stress) + float(def.get("stress", 5)) * maxf(0.1, 1.0 + _sim.gamer.mod("stress_gain")), 0, 100)
	_sim.gamer.add_exp(p, float(def.get("exp", 30)) * (1.0 + int(p.career.level) * 0.3))
	_sim.gamer.add_stat_xp(p, def.get("key_stat", "int"), float(_sim.data.bal("career.stat_xp_per_year", 25)))
	if def.has("skill"):
		if not _sim.skills.knows(p, def.skill):
			_sim.activities.bump_counter("work." + p.career.job)
		_sim.skills.add_xp(p, def.skill, 20.0)
	_sim.activities.bump_counter("work.years")
	if float(def.get("fame", 0)) > 0.0:
		p.fame = clampf(float(p.get("fame", 0)) + float(def.fame) * (1 + int(p.career.level)), 0, 100)
	if _sim.prob.roll_neutral(float(def.get("risk", 0.0))):
		_sim.health.injure(p, def.get("injury", "injury_minor"))
	_promotion_or_firing(p, def)
	p.career.salary = float(p.career.salary) * (1.0 + float(_sim.state.data.world.inflation) * 0.8)


func _update_performance(p: Dictionary, def: Dictionary) -> void:
	var key: float = _sim.gamer.effective_stat(p, def.get("key_stat", "int"))
	var need := float(def.get("stat_req", {}).get(def.get("key_stat", "int"), 10)) + int(p.career.level) * 4.0
	var target := 50.0 + (key - need) * 1.5 + (float(p.attrs.discipline) - 50.0) * 0.3
	target += float(p.year_counters.get("work_hard", 0)) * 8.0
	target += _sim.gamer.mod("work_perf") * 40.0
	target += (_sim.relations.role_score(p, "boss") - 50.0) * 0.2
	target -= maxf(0.0, float(p.attrs.stress) - 60.0) * 0.5
	target -= 15.0 if float(p.attrs.health) < 30.0 else 0.0
	p.career.performance = clampf(lerpf(float(p.career.performance), clampf(target, 0, 100), 0.5) + _sim.rng.randn(0, 4), 0, 100)


func _promotion_or_firing(p: Dictionary, def: Dictionary) -> void:
	var perf := float(p.career.performance)
	var max_level := int(def.get("max_level", 4))
	if perf >= 72.0 and int(p.career.level) < max_level:
		var spec := {"base": 0.25 + (perf - 72.0) * 0.015, "mods": [{"path": "mod.promotion", "per": 1.0}]}
		if _sim.prob.roll_spec(spec):
			promote(p)
	elif perf < 25.0 and _sim.prob.roll_neutral(0.45 - perf * 0.01 + float(_sim.state.data.world.unemployment)):
		fire(p, "fired")
	elif _sim.prob.roll_neutral(float(_sim.state.data.world.unemployment) * 0.25 * (1.0 - float(_sim.state.data.world.economy))):
		fire(p, "laid_off")


func promote(p: Dictionary) -> void:
	p.career.level = int(p.career.level) + 1
	p.career.salary = float(p.career.salary) * float(_sim.data.bal("career.promotion_mult", 1.22))
	_sim.add_log("log.promoted", {"job": "@job." + p.career.job, "rank": "@joblevel." + str(p.career.level)}, "major")
	_sim.activities.bump_counter("job.promotions")
	p.attrs.happiness = clampf(float(p.attrs.happiness) + 8, 0, 100)


func ask_raise(p: Dictionary) -> Dictionary:
	if not is_employed(p):
		return {"ok": false, "reason": "ui.invalid"}
	var spec := {"base": 0.15, "mods": [
		{"path": "player.career.performance", "per": 0.006, "offset": 50.0},
		{"path": "stat.cha", "per": 0.004, "offset": 10.0, "max": 0.2}]}
	if _sim.prob.roll_spec(spec):
		p.career.salary = float(p.career.salary) * 1.08
		return {"ok": true, "key": "job.raise_ok", "params": {}}
	_sim.relations.change_score(_sim.relations.first_with_role(p, "boss"), -5)
	return {"ok": false, "reason": "job.raise_no"}


# ---------------------------------------------------------------------------
# Factions (guilds of the Awakened)
# ---------------------------------------------------------------------------

func join_faction(p: Dictionary, faction: String) -> void:
	if _sim.data.get_def("factions", faction).is_empty():
		return
	p.faction.id = faction
	p.faction.rank = 0
	p.faction.rep[faction] = maxf(float(p.faction.rep.get(faction, 0)), 10.0)
	_sim.add_log("log.faction_join", {"faction": "@faction." + faction}, "major")
	_sim.activities.bump_counter("faction.joined")


func change_faction_rep(p: Dictionary, faction: String, amount: float) -> void:
	p.faction.rep[faction] = clampf(float(p.faction.rep.get(faction, 0)) + amount, -100, 100)


# ---------------------------------------------------------------------------
# NPC jobs (coherent with age and education)
# ---------------------------------------------------------------------------

func assign_npc_job(npc: Dictionary) -> void:
	var age := int(npc.age)
	if age < 18 or age >= 66:
		npc.career.job = ""
		return
	var tiers := {"poor": [1, 2], "working": [1, 2, 3], "middle": [2, 3, 4], "upper": [3, 4, 5], "elite": [4, 5]}
	var allowed: Array = tiers.get(npc.wealth, [2, 3])
	var options: Array = []
	for id in _sim.data.table("jobs"):
		var def: Dictionary = _sim.data.table("jobs")[id]
		if def.get("npc", true) == false or not allowed.has(int(def.get("tier", 2))):
			continue
		if age < int(def.get("min_age", 18)):
			continue
		var ok := true
		for req in def.get("education", []):
			if req == "any_university":
				ok = ok and npc.education.major != ""
			elif not npc.education.completed.has(req):
				ok = false
		if ok:
			options.append(id)
	options.sort()
	if options.is_empty() or _sim.prob.roll_neutral(0.08):
		npc.career.job = ""
		return
	var id: String = _sim.rng.pick(options)
	npc.career.job = id
	npc.career.level = mini(int((age - 18) / 8), int(_sim.data.get_def("jobs", id).get("max_level", 4)))
	npc.career.salary = float(_sim.data.get_def("jobs", id).salary) * level_mult(npc.career.level)
