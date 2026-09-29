class_name SkillSystem
extends RefCounted
## Skills in the spirit of The Gamer (repeated actions become skills and level
## with use) + Tensura (tiers, evolution when mastered, fusion of skills) +
## Re:Monster (skills absorbed from what you devour).
## Tiers: common < extra < unique < ultimate.

var _sim
var _learn_index: Dictionary = {}  # counter key -> [skill ids]


func _init(sim) -> void:
	_sim = sim
	for sid in _sim.data.table("skills"):
		var learn: Dictionary = _sim.data.table("skills")[sid].get("learn", {})
		if learn.has("counter"):
			if not _learn_index.has(learn.counter):
				_learn_index[learn.counter] = []
			_learn_index[learn.counter].append(sid)


func knows(p: Dictionary, sid: String) -> bool:
	return p.gamer.skills.has(sid)


func level(p: Dictionary, sid: String) -> int:
	return int(p.gamer.skills.get(sid, {}).get("lv", 0))


func xp_needed(sid: String, lv: int) -> float:
	var def: Dictionary = _sim.data.get_def("skills", sid)
	return float(def.get("xp_base", 30)) * pow(lv, float(_sim.data.bal("skills.xp_exponent", 1.35)))


func learn(p: Dictionary, sid: String, silent: bool = false) -> bool:
	var def: Dictionary = _sim.data.get_def("skills", sid)
	if def.is_empty() or knows(p, sid):
		return false
	p.gamer.skills[sid] = {"lv": int(def.get("start_level", 1)), "xp": 0.0}
	_sim.gamer.invalidate()
	if not silent:
		_sim.notify("skill", "sys.skill_learned", {"skill": "@skill." + sid, "tier": "@tier." + def.get("tier", "common")})
		_sim.add_log("log.skill_learned", {"skill": "@skill." + sid}, "system")
	_sim.bus.skill_learned.emit(sid)
	check_fusions(p)
	return true


func add_xp(p: Dictionary, sid: String, amount: float) -> void:
	if not knows(p, sid):
		return
	var def: Dictionary = _sim.data.get_def("skills", sid)
	var entry: Dictionary = p.gamer.skills[sid]
	var max_lv := int(def.get("max_level", 10))
	if int(entry.lv) >= max_lv:
		return
	entry.xp = float(entry.xp) + amount * maxf(0.1, 1.0 + _sim.gamer.mod("skill_gain") + _sim.hidden_talent_bonus(def))
	while int(entry.lv) < max_lv and float(entry.xp) >= xp_needed(sid, int(entry.lv)):
		entry.xp = float(entry.xp) - xp_needed(sid, int(entry.lv))
		entry.lv = int(entry.lv) + 1
		_sim.gamer.invalidate()
		_sim.notify("skill", "sys.skill_level", {"skill": "@skill." + sid, "level": entry.lv})
		_sim.bus.skill_level_up.emit(sid, int(entry.lv))
	if int(entry.lv) >= max_lv:
		entry.xp = 0.0
		_try_evolve(p, sid)
	check_fusions(p)


## Called whenever a counter moves: repeated behaviour creates skills.
func on_counter(p: Dictionary, key: String, value: int) -> void:
	for sid in _learn_index.get(key, []):
		if knows(p, sid) or _evolved_from_known(p, sid):
			continue
		var learn_def: Dictionary = _sim.data.get_def("skills", sid).learn
		if value >= int(learn_def.get("count", 1)) and _sim.cond.check_all(learn_def.get("conditions", []), {}):
			learn(p, sid)


func _try_evolve(p: Dictionary, sid: String) -> void:
	var def: Dictionary = _sim.data.get_def("skills", sid)
	var target: String = def.get("evolves_to", "")
	if target == "" or knows(p, target):
		return
	if not _sim.cond.check_all(def.get("evolve_conditions", []), {}):
		return
	p.gamer.skills.erase(sid)
	p.gamer.skills[target] = {"lv": 1, "xp": 0.0}
	_sim.gamer.invalidate()
	_sim.notify("evolve", "sys.skill_evolved", {"from": "@skill." + sid, "to": "@skill." + target})
	_sim.add_log("log.skill_evolved", {"from": "@skill." + sid, "to": "@skill." + target}, "system")
	_sim.bus.skill_evolved.emit(sid, target)


func check_fusions(p: Dictionary) -> void:
	for sid in _sim.data.table("skills"):
		var fusion: Dictionary = _sim.data.table("skills")[sid].get("fusion", {})
		if fusion.is_empty() or knows(p, sid):
			continue
		var ok := true
		for src in fusion.from:
			if level(p, src) < int(fusion.get("min_level", 5)):
				ok = false
				break
		if not ok:
			continue
		for src in fusion.from:
			p.gamer.skills.erase(src)
		p.gamer.skills[sid] = {"lv": 1, "xp": 0.0}
		_sim.gamer.invalidate()
		_sim.notify("evolve", "sys.skill_fused", {"skill": "@skill." + sid})
		_sim.add_log("log.skill_fused", {"skill": "@skill." + sid}, "major")


func _evolved_from_known(p: Dictionary, sid: String) -> bool:
	# If the player already owns an evolution of this skill, don't relearn it.
	var def: Dictionary = _sim.data.get_def("skills", sid)
	var nxt: String = def.get("evolves_to", "")
	var guard := 0
	while nxt != "" and guard < 8:
		if knows(p, nxt):
			return true
		nxt = _sim.data.get_def("skills", nxt).get("evolves_to", "")
		guard += 1
	return false


## Active combat skills known by the player, strongest first.
func combat_skills(p: Dictionary) -> Array:
	var out: Array = []
	for sid in p.gamer.skills:
		var def: Dictionary = _sim.data.get_def("skills", sid)
		if def.has("combat"):
			out.append(sid)
	out.sort_custom(func(a, b): return skill_power(p, a) > skill_power(p, b))
	return out


func skill_power(p: Dictionary, sid: String) -> float:
	var c: Dictionary = _sim.data.get_def("skills", sid).get("combat", {})
	var stat_v: float = _sim.gamer.effective_stat(p, c.get("stat", "int"))
	return (float(c.get("base", 10)) + stat_v * float(c.get("mult", 2.0))) * (1.0 + float(level(p, sid) - 1) * float(c.get("per_level", 0.12)))


## The Observe skill: reading people like game windows. The deeper the skill
## level, the more of the NPC is revealed (level, stats, traits, hidden).
func observe(npc: Dictionary) -> void:
	var p: Dictionary = _sim.player()
	if not knows(p, "observe"):
		return
	add_xp(p, "observe", 6.0)
	npc.observed = maxi(int(npc.get("observed", 0)), level(p, "observe"))
	_sim.activities.bump_counter("observe.uses")
	if npc.gamer.get("awakened", false) and not _sim.state.flag("saw_awakened", false):
		_sim.state.set_flag("saw_awakened")
		_sim.events.queue_event("sys_first_awakened_seen", npc.id)
