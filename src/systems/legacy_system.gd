class_name LegacySystem
extends RefCounted
## Death, life summary, estate/heritage and dynasties. The System does not die
## with its host: it passes to an heir (continue the dynasty) or the soul
## reincarnates carrying Soul Points to spend on perks (isekai-style NG+).

var _sim


func _init(sim) -> void:
	_sim = sim


func on_player_death(p: Dictionary, cause: String) -> void:
	_sim.achievements.check(true)
	var summary := build_summary(p, cause)
	summary.ribbon = ribbon_for(p)
	_sim.state.data.death = summary
	var legacy: Dictionary = _sim.state.data.legacy
	legacy.soul_points = int(legacy.get("soul_points", 0)) + int(summary.soul_points)
	legacy.lives.append({"name": summary.name, "age": summary.age, "level": summary.level,
		"worth": summary.net_worth, "cause": cause, "gen": _sim.state.data.generation})
	_sim.bus.character_died.emit(summary)


func build_summary(p: Dictionary, cause: String) -> Dictionary:
	var worth: float = _sim.finance.net_worth(p)
	var top_skills: Array = p.gamer.skills.keys()
	top_skills.sort_custom(func(a, b): return int(p.gamer.skills[a].lv) > int(p.gamer.skills[b].lv))
	top_skills = top_skills.slice(0, 5)
	var highlights: Array = []
	for e in _sim.state.data.timeline:
		if e.get("kind", "") == "major":
			highlights.append(e)
	if highlights.size() > 14:
		highlights = highlights.slice(highlights.size() - 14)
	var soul: int = int(p.gamer.level) * 2 + p.gamer.titles.size() * 5 + _sim.state.data.achievements.size() * 8
	soul += int(maxf(0.0, log(maxf(worth, 1.0)) / log(10.0) - 3.0) * 10.0) + int(p.age) / 5
	return {
		"name": p.first_name + " " + p.last_name,
		"age": p.age, "cause": cause, "net_worth": worth,
		"job": p.career.job, "level": p.gamer.level, "rank": p.gamer.get("rank", 0),
		"skills": top_skills, "titles": p.gamer.titles.size(),
		"children": _sim.relations.count_role(p, "child"),
		"achievements": _sim.state.data.achievements.size(),
		"highlights": highlights, "generation": _sim.state.data.generation,
		"soul_points": soul, "fame": p.get("fame", 0), "record": p.criminal.record.size(),
	}


## One ribbon per life, first match by priority (data/ribbons.json).
func ribbon_for(_p: Dictionary) -> String:
	var ids: Array = _sim.data.table("ribbons").keys()
	ids.sort_custom(func(a, b): return int(_sim.data.get_def("ribbons", a).priority) < int(_sim.data.get_def("ribbons", b).priority))
	for id in ids:
		if _sim.cond.check_all(_sim.data.get_def("ribbons", id).get("conditions", []), {}):
			return id
	return "rb_ordinary"


## Will: "equal" (children share), "spouse" (spouse gets 60%), "favorite"
## (one child gets 70%) or "charity" (half to charity: karma for the dynasty).
func set_will(p: Dictionary, mode: String, favorite: String = "") -> Dictionary:
	if not mode in ["equal", "spouse", "favorite", "charity"]:
		return {"ok": false, "reason": "ui.invalid"}
	p.will = {"mode": mode, "favorite": favorite}
	return {"ok": true, "key": "will.updated", "params": {"mode": "@will." + mode}}


func heirs() -> Array:
	var p: Dictionary = _sim.player()
	var out: Array = []
	for role in ["child", "grandchild"]:
		for id in _sim.relations.all_with_role(p, role):
			out.append(id)
	return out


## Continue the dynasty as `heir_id`. The world, relatives and history persist.
func continue_as(heir_id: String) -> bool:
	var old: Dictionary = _sim.player()
	var heir: Dictionary = _sim.state.npc(heir_id)
	if heir.is_empty() or not heir.alive or not heirs().has(heir_id):
		return false
	var siblings: Array = []
	for id in _sim.relations.all_with_role(old, "child"):
		if id != heir_id:
			siblings.append(id)
	var old_role: String = _sim.relations.role_of(heir_id)
	_distribute_estate(old, heir, siblings)
	_sim.factory.promote_to_player(heir)
	_inherit_system(old, heir)
	var partner_of_old: String = old.family.spouse
	_sim.state.data.player_id = heir.id
	old.is_player = false
	heir.rels = {}
	var parent_role := "father" if old.sex == "m" else "mother"
	_sim.relations.ensure(old.id, parent_role, 80)
	if partner_of_old != "" and _sim.state.has_npc(partner_of_old) and _sim.state.npc(partner_of_old).alive:
		_sim.relations.ensure(partner_of_old, "mother" if parent_role == "father" else "father", 70)
	if old_role == "child":
		for sid in siblings:
			_sim.relations.ensure(sid, "sibling", 55)
	if heir.family.spouse != "" and _sim.state.has_npc(heir.family.spouse):
		_sim.relations.ensure(heir.family.spouse, "spouse", 70)
	for cid in heir.family.children:
		if _sim.state.has_npc(cid):
			_sim.relations.ensure(cid, "child", 75)
	_reset_life_scoped_state()
	_sim.state.data.generation = int(_sim.state.data.generation) + 1
	_sim.gamer.invalidate()
	_sim.gamer.refill(heir)
	_sim.education.auto_enroll(heir)
	_sim.npcs.prune(heir)
	_sim.add_log("log.heir_continues", {"name": heir.first_name, "gen": _sim.state.data.generation}, "major")
	_sim.events.queue_special("sys_inheritance")
	_sim.pipeline.start_year()
	_sim.bus.new_life_started.emit()
	return true


func _distribute_estate(old: Dictionary, heir: Dictionary, siblings: Array) -> void:
	var estate := float(old.finance.cash) - float(old.finance.get("debt", 0.0))
	for loan in old.finance.get("loans", []):
		estate -= float(loan.balance)
	for asset in old.finance.get("investments", {}):
		estate += float(old.finance.investments[asset]) * _sim.world.price(asset)
	estate *= 1.0 - float(_sim.data.bal("legacy.estate_tax", 0.1))
	estate = maxf(0.0, estate)
	var will: Dictionary = old.get("will", {"mode": "equal"})
	var spouse_id: String = old.family.get("spouse", "")
	var children: Array = [heir.id] + siblings
	var shares := {}
	match will.get("mode", "equal"):
		"spouse":
			if spouse_id != "" and _sim.state.has_npc(spouse_id) and _sim.state.npc(spouse_id).alive:
				shares[spouse_id] = 0.6
		"favorite":
			if children.has(will.get("favorite", "")):
				shares[will.favorite] = 0.7
		"charity":
			shares["charity"] = 0.5
			_sim.state.set_flag("dyn_philanthropist")
	var rest := 1.0
	for k in shares:
		rest -= float(shares[k])
	for cid in children:
		shares[cid] = float(shares.get(cid, 0.0)) + rest / float(children.size())
	for k in shares:
		if k == "charity":
			continue
		var who: Dictionary = heir if k == heir.id else _sim.state.npc(k)
		if not who.is_empty():
			who.finance.cash = float(who.finance.get("cash", 0.0)) + estate * float(shares[k])
	# Heirlooms and possessions stay in the family line.
	if not heir.gamer.has("inventory"):
		heir.gamer.inventory = {}
	heir.finance.possessions = old.finance.get("possessions", []).duplicate(true)
	old.finance.possessions = []
	for item_id in old.gamer.get("inventory", {}).keys():
		if _sim.data.get_def("items", item_id).get("cat", "") == "heirloom":
			heir.gamer.inventory[item_id] = int(heir.gamer.inventory.get(item_id, 0)) + int(old.gamer.inventory[item_id])
	# Properties go to the heir (the one who keeps the family name alive).
	heir.finance.properties = old.finance.get("properties", []).duplicate(true)
	old.finance.cash = 0.0
	old.finance.properties = []


## The System passes to the heir: a fraction of the stats, one of the
## predecessor's skills (at level 1) and the dynasty's accumulated titles.
func _inherit_system(old: Dictionary, heir: Dictionary) -> void:
	var pct := float(_sim.data.bal("legacy.stat_inherit", 0.12))
	for s in CharacterFactory.STAT_IDS:
		heir.gamer.stats[s] = float(heir.gamer.stats[s]) + floorf(float(old.gamer.stats[s]) * pct)
	heir.gamer.awakened = true
	heir.gamer.level = maxi(1, int(heir.gamer.get("level", 1)))
	for sid in _sim.data.bal("gamer.starting_skills", []):
		heir.gamer.skills[sid] = {"lv": 1, "xp": 0.0}
	var candidates: Array = []
	for sid in old.gamer.skills:
		if not _sim.data.bal("gamer.starting_skills", []).has(sid):
			candidates.append(sid)
	candidates.sort()
	if not candidates.is_empty():
		var sid: String = _sim.rng.pick(candidates)
		heir.gamer.skills[sid] = {"lv": 1, "xp": 0.0}
	if old.gamer.titles.has("dynasty_founder") or int(old.gamer.level) >= 30:
		heir.gamer.titles.append("heir_of_system")


func _reset_life_scoped_state() -> void:
	var d: Dictionary = _sim.state.data
	d.dead = false
	d.death = {}
	d.pending_events = []
	d.scheduled = []
	d.event_history = {}
	d.achievements = {}
	var kept_flags := {}
	for f in d.flags:
		if str(f).begins_with("dyn_"):
			kept_flags[f] = d.flags[f]
	d.flags = kept_flags
	var kept_counters := {}
	for c in d.counters:
		if str(c).begins_with("dyn."):
			kept_counters[c] = d.counters[c]
	d.counters = kept_counters
	d.timeline = []


## Reincarnation perks bought with Soul Points (items flagged "perk").
func apply_start_perks(perks: Array) -> void:
	var p: Dictionary = _sim.player()
	for perk in perks:
		var def: Dictionary = _sim.data.get_def("items", perk)
		if def.get("perk", false):
			_sim.effects.run_all(def.get("use", []), {})
			_sim.state.data.legacy.perks.append(perk)
	_sim.gamer.invalidate()
	_sim.gamer.refill(p)
