class_name NpcSystem
extends RefCounted
## Abstract yearly simulation of RELEVANT NPCs only (those bonded to the
## player plus the player's descendants). Everyone else is pruned. This keeps
## mobile performance flat no matter how long a dynasty runs.

var _sim


func _init(sim) -> void:
	_sim = sim


func process_year(p: Dictionary) -> void:
	for id in relevant_ids(p):
		var npc: Dictionary = _sim.state.npc(id)
		if npc.is_empty() or not npc.alive or npc.get("is_player", false):
			continue
		npc.age = int(npc.age) + 1
		Persona.ensure(npc, _sim)
		_life_stage(npc)
		_mood_drift(npc)
		_marriage_drift(npc)
		_life_events(p, npc)
		Persona.refresh_voice(npc)
		if _sim.prob.roll_neutral(_sim.health.mortality(npc)):
			_npc_dies(p, npc)
	prune(p)


# ---------------------------------------------------------------------------
# Inner lives: mood, marriages and data-driven life events (data/npc_life.json)
# ---------------------------------------------------------------------------

## Mood drifts toward a personal baseline (neurotic people sit lower and
## swing harder) and reacts to the economy and to their own health.
func _mood_drift(npc: Dictionary) -> void:
	var n := Persona.trait_of(npc, "n")
	var base := 72.0 - (n - 50.0) * 0.35 + (Persona.trait_of(npc, "e") - 50.0) * 0.1
	base += float(_sim.state.data.world.economy) * 6.0
	if not npc.health.get("conditions", {}).is_empty():
		base -= 10.0
	if npc.career.get("job", "") == "" and int(npc.age) >= 20 and int(npc.age) < 66:
		base -= 8.0
	var swing: float = _sim.rng.randn(0, 4.0 + n / 12.0)
	npc.attrs.happiness = clampf(lerpf(float(npc.attrs.happiness), base, 0.35) + swing, 0, 100)
	npc.attrs.stress = clampf(lerpf(float(npc.attrs.get("stress", 20)), 20.0 + n * 0.3, 0.3) + _sim.rng.randn(0, 3), 0, 100)


## Couples among the people you know have their own marriage quality.
func _marriage_drift(npc: Dictionary) -> void:
	var sid: String = npc.family.get("spouse", "")
	if sid == "" or not _sim.state.has_npc(sid) or _sim.state.npc(sid).get("is_player", false):
		return
	var sp: Dictionary = _sim.state.npc(sid)
	if not npc.has("marriage"):
		npc.marriage = _sim.rng.randf_range(45, 85)
	var target := 60.0 + (Persona.trait_of(npc, "a") + Persona.trait_of(sp, "a") - 100.0) * 0.25 - (Persona.trait_of(npc, "n") + Persona.trait_of(sp, "n") - 100.0) * 0.2
	for t in npc.traits:
		var tdef: Dictionary = _sim.data.get_def("traits", t)
		for st in sp.get("traits", []):
			if tdef.get("likes", []).has(st):
				target += 5
			if tdef.get("dislikes", []).has(st):
				target -= 7
	if float(npc.finance.cash) + float(sp.finance.cash) < 1000:
		target -= 8
	npc.marriage = clampf(lerpf(float(npc.marriage), target, 0.2) + _sim.rng.randn(0, 5), 0, 100)
	sp.marriage = npc.marriage


func _life_events(p: Dictionary, npc: Dictionary) -> void:
	if not _sim.prob.roll_neutral(float(_sim.data.bal("npc_life.yearly_chance", 0.45))):
		return
	var facts := npc_facts(npc)
	var ids: Array = _sim.data.table("npc_life").keys()
	ids.sort()
	var pool: Array = []
	var weights: Array = []
	var age := int(npc.age)
	for id in ids:
		var def: Dictionary = _sim.data.table("npc_life")[id]
		var ar: Array = def.get("age", [0, 200])
		if age < int(ar[0]) or age > int(ar[1]):
			continue
		if not _sim.allows(def.get("tags", [])):
			continue
		if not _sim.dialogue.matches(def, facts):
			continue
		var cd := int(def.get("cd", 3))
		if _years_since(npc, id) < cd:
			continue
		var w := 1.0
		for m in def.get("mods", []):
			var v = facts.get(m[0], null)
			if m.size() == 2:
				if DialogueSystem.truthy(v):
					w += float(m[1])
			elif v != null:
				w += (float(v) - float(m[2])) * float(m[1])
		pool.append(def)
		weights.append(float(def.get("w", 1.0)) * maxf(0.05, w))
	var def = _sim.rng.pick_weighted(pool, weights)
	if def == null:
		return
	apply_life_event(p, npc, def)


func npc_facts(npc: Dictionary) -> Dictionary:
	var f := {}
	_sim.dialogue.character_facts(npc, "npc.", f)
	var role: String = _sim.relations.role_of(npc.id)
	f["role"] = role
	f["role." + role] = true
	f["bond"] = _sim.relations.score(npc.id)
	if npc.has("marriage"):
		f["npc.marriage"] = float(npc.marriage)
	f["npc.far"] = npc.get("far", false)
	f["npc.jailed"] = int(npc.get("jailed", 0)) > 0
	var sid: String = npc.family.get("spouse", "")
	if sid != "" and _sim.state.has_npc(sid):
		var sp: Dictionary = _sim.state.npc(sid)
		if sp.get("is_player", false):
			f["npc.spouse_is_player"] = true
		elif _sim.relations.role_of(sid) in ["mother", "father"] and role in ["mother", "father"]:
			f["npc.parents_couple"] = true
	f["w.economy"] = float(_sim.state.data.world.economy)
	f["w.unemployment"] = float(_sim.state.data.world.unemployment)
	_sim.society.world_facts(f)
	f["p.age"] = int(_sim.player().age)
	return f


func _years_since(npc: Dictionary, ev: String) -> int:
	var year = int(_sim.state.data.world_year)
	var log: Array = npc.get("life_log", [])
	for i in range(log.size() - 1, -1, -1):
		if log[i].e == ev:
			return year - int(log[i].y)
	return 999


func log_life(npc: Dictionary, ev: String, params: Dictionary = {}) -> void:
	if not npc.has("life_log"):
		npc.life_log = []
	npc.life_log.append({"e": ev, "y": int(_sim.state.data.world_year), "p": params})
	while npc.life_log.size() > 16:
		npc.life_log.pop_front()


func apply_life_event(p: Dictionary, npc: Dictionary, def: Dictionary) -> void:
	var params := {}
	for fx in def.get("fx", []):
		_life_fx(p, npc, fx, params)
	log_life(npc, def.id, params)
	var role: String = _sim.relations.role_of(npc.id)
	var close = RelationshipSystem.FAMILY_ROLES.has(role) or role in ["best_friend", "partner", "fiance"] or _sim.relations.score(npc.id) >= 70
	var notify: String = def.get("notify", "")
	if notify != "" and (close or notify == "major"):
		var prm := {"name": npc.first_name, "role": "@role." + role, "what": "@lifeev.%s.%s" % [def.id, npc.sex]}
		prm.merge(params, false)
		_sim.add_log("log.npc_life", prm, "major" if notify == "major" else "social")
	# How the player feels about it depends on the bond.
	var feel := float(def.get("player_mood", 0.0))
	if feel != 0.0 and close:
		p.attrs.happiness = clampf(float(p.attrs.happiness) + feel * _sim.relations.score(npc.id) / 100.0, 0, 100)


func _life_fx(p: Dictionary, npc: Dictionary, fx: Dictionary, params: Dictionary) -> void:
	var v = fx.get("v", 0)
	match fx.op:
		"cash":
			var amt := float(v)
			if fx.has("min"):
				amt = _sim.rng.randf_range(float(fx.min), float(fx.max))
			if fx.get("salary", false):
				amt = maxf(amt, float(npc.career.get("salary", 0)) * _sim.rng.randf_range(0.2, 0.6))
			amt *= float(_sim.state.data.world.price_index)
			npc.finance.cash = maxf(0.0, float(npc.finance.cash) + amt)
			params.amount = int(absf(amt))
		"mood":
			npc.attrs.happiness = clampf(float(npc.attrs.happiness) + float(v), 0, 100)
		"stress":
			npc.attrs.stress = clampf(float(npc.attrs.get("stress", 20)) + float(v), 0, 100)
		"health":
			npc.attrs.health = clampf(float(npc.attrs.health) + float(v), 1, 100)
		"lose_job":
			if npc.career.job != "":
				params.job = "@job." + npc.career.job
			npc.career.job = ""
			npc.career.salary = 0.0
		"new_job":
			_sim.career.assign_npc_job(npc)
			if npc.career.job != "":
				params.job = "@job." + npc.career.job
		"promote":
			npc.career.level = int(npc.career.get("level", 0)) + 1
			npc.career.salary = float(npc.career.get("salary", 0)) * 1.2
			if npc.career.job != "":
				params.job = "@job." + npc.career.job
		"retire":
			npc.career.job = ""
			npc.career.salary = 0.0
		"marry":
			_npc_marry(p, npc, params)
		"divorce":
			_npc_divorce(p, npc, params)
		"baby":
			_npc_baby(p, npc, params)
		"sick":
			var cid: String = _sim.rng.pick(fx.get("pool", ["flu"]))
			npc.health.conditions[cid] = {"since": int(npc.age)}
			params.cond = "@disease." + cid
		"recover":
			var conds: Array = npc.health.get("conditions", {}).keys()
			if not conds.is_empty():
				conds.sort()
				params.cond = "@disease." + str(conds[0])
				npc.health.conditions.erase(conds[0])
		"move":
			npc.far = true
			var cities: Array = _sim.society.nation(npc.country).cities
			params.city = cities[_sim.rng.randi_range(1, cities.size() - 1)]
			npc.city = params.city
		"return":
			npc.far = false
			npc.erase("city")
		"interest":
			var opts: Array = Persona.INTERESTS.filter(func(x): return not npc.persona.interests.has(x))
			if not opts.is_empty():
				var it: String = _sim.rng.pick(opts)
				npc.persona.interests.append(it)
				if npc.persona.interests.size() > 4:
					npc.persona.interests.pop_front()
				params.interest = "@interest." + it
		"awaken":
			if not npc.gamer.get("awakened", false):
				_sim.factory.make_awakened(npc, 1, 6)
		"jail":
			npc.jailed = _sim.rng.randi_range(1, 4)
			npc.career.job = ""
		"faith":
			npc.hidden.religiousness = clampf(float(npc.hidden.religiousness) + float(v), 1, 99)
		"politics":
			npc.persona.politics = clampf(float(npc.persona.politics) + float(v), -100, 100)
		"business":
			var types: Array = fx.get("pool", ["bakery", "cafe", "shop", "restaurant", "bar", "salon"])
			var c: Dictionary = _sim.society.city()
			var pl: Dictionary = _sim.society._open_place(c, _sim.rng.pick(types), npc.id, true)
			npc.business = pl.id
			params.place = _sim.society.place_name(pl)
		"close_business":
			for pl in _sim.society.city().places:
				if pl.get("owner", "") == npc.id and pl.open:
					pl.open = false
					pl.closed = int(_sim.state.data.world_year)
					params.place = _sim.society.place_name(pl)
			npc.erase("business")
		"player_bond":
			_sim.relations.change_score(npc.id, float(v))
		"memory":
			_sim.relations.add_memory(npc.id, str(v), float(fx.get("sev", 10)))
		"event":
			_sim.events.queue_event(str(v), npc.id)


func _npc_marry(p: Dictionary, npc: Dictionary, params: Dictionary) -> void:
	if npc.family.spouse != "":
		return
	var sex := "f" if npc.sex == "m" else "m"
	var spouse: Dictionary = _sim.factory.create_npc(npc.country, sex, maxi(18, int(npc.age) + _sim.rng.randi_range(-5, 5)))
	_sim.state.add_npc(spouse)
	npc.family.spouse = spouse.id
	spouse.family.spouse = npc.id
	npc.marriage = _sim.rng.randf_range(60, 90)
	params.spouse = spouse.first_name
	var role: String = _sim.relations.role_of(npc.id)
	# A single parent remarrying gives the player a stepparent.
	if role in ["mother", "father"] and int(p.age) < 30:
		_sim.relations.ensure(spouse.id, "stepparent", _sim.rng.randf_range(30, 60))
		_sim.add_log("log.new_stepparent", {"name": spouse.first_name, "parent": npc.first_name}, "major")


func _npc_divorce(p: Dictionary, npc: Dictionary, params: Dictionary) -> void:
	var sid: String = npc.family.spouse
	if sid == "" or not _sim.state.has_npc(sid):
		return
	var sp: Dictionary = _sim.state.npc(sid)
	if sp.get("is_player", false):
		return
	params.spouse = sp.first_name
	npc.family.spouse = ""
	sp.family.spouse = ""
	npc.erase("marriage")
	sp.erase("marriage")
	var roles = [_sim.relations.role_of(npc.id), _sim.relations.role_of(sid)]
	if roles.has("mother") and roles.has("father"):
		p.family_structure = "separated"
		_sim.add_log("log.parents_divorced", {}, "major")
		p.attrs.happiness = clampf(float(p.attrs.happiness) - (18.0 if int(p.age) < 18 else 6.0), 0, 100)
		p.attrs.stress = clampf(float(p.attrs.stress) + (15.0 if int(p.age) < 18 else 5.0), 0, 100)
		_sim.activities.bump_counter("family.parents_divorced")
	elif roles.has("stepparent"):
		_sim.relations.end(sid, "cut")


func _npc_baby(p: Dictionary, npc: Dictionary, params: Dictionary) -> void:
	var sid: String = npc.family.spouse
	if sid == "" or not _sim.state.has_npc(sid):
		return
	var sp: Dictionary = _sim.state.npc(sid)
	if sp.get("is_player", false):
		return
	var mother: Dictionary = npc if npc.sex == "f" else sp
	var father: Dictionary = sp if npc.sex == "f" else npc
	if int(mother.age) > 45:
		return
	var baby: Dictionary = _sim.factory.create_child(mother, father)
	params.baby = baby.first_name
	var role: String = _sim.relations.role_of(npc.id)
	if role in ["mother", "father", "stepparent"]:
		p.family.siblings.append(baby.id)
		baby.family.siblings.append(p.id)
		_sim.relations.ensure(baby.id, "sibling", 70)
		_sim.add_log("log.new_sibling", {"name": baby.first_name}, "major")
	elif role == "child":
		_sim.relations.ensure(baby.id, "grandchild", 70)
		_sim.add_log("log.grandchild", {"name": baby.first_name, "parent": npc.first_name}, "major")


func relevant_ids(p: Dictionary) -> Array:
	var ids: Array = p.get("rels", {}).keys()
	ids.sort()
	return ids


func _life_stage(npc: Dictionary) -> void:
	var age := int(npc.age)
	if int(npc.get("jailed", 0)) > 0:
		npc.jailed = int(npc.jailed) - 1
		if int(npc.jailed) == 0:
			log_life(npc, "released")
		return
	if age < 18:
		for s in CharacterFactory.STAT_IDS:
			npc.gamer.stats[s] = float(npc.gamer.stats[s]) + _sim.rng.randf_range(0.2, 1.0)
		_sim.education.assign_npc_education(npc)
	elif age == 18 or (age > 18 and npc.career.job == "" and age < 66 and _sim.prob.roll_neutral(0.3)):
		_sim.education.assign_npc_education(npc)
		_sim.career.assign_npc_job(npc)
	elif age >= 66 and npc.career.job != "":
		npc.career.job = ""
	npc.finance.cash = maxf(0.0, float(npc.finance.cash) + float(npc.career.get("salary", 0)) * 0.08 - 500.0)
	if npc.gamer.get("awakened", false) and _sim.prob.roll_neutral(0.5):
		npc.gamer.level = int(npc.gamer.level) + _sim.rng.randi_range(1, 3)
		npc.gamer.stats[_sim.rng.pick(CharacterFactory.STAT_IDS)] += 5.0


func _npc_dies(p: Dictionary, npc: Dictionary) -> void:
	npc.alive = false
	var role: String = _sim.relations.role_of(npc.id)
	_sim.add_log("log.npc_died", {"name": npc.first_name, "role": "@role." + role, "age": npc.age}, "major" if RelationshipSystem.FAMILY_ROLES.has(role) else "info")
	var bond: float = _sim.relations.score(npc.id)
	p.attrs.happiness = clampf(float(p.attrs.happiness) - bond * 0.25, 0, 100)
	if role in ["mother", "father", "grandparent", "spouse"]:
		_inheritance(p, npc, role)
	if role == "spouse":
		p.family.spouse = ""
		_sim.relations.set_role(npc.id, "late_spouse")
	_sim.activities.bump_counter("grief")


func _inheritance(p: Dictionary, npc: Dictionary, role: String) -> void:
	var heirs := maxi(1, npc.family.children.size())
	var share := float(npc.finance.cash) / heirs
	if role == "spouse":
		share = float(npc.finance.cash)
	if share < 100.0:
		return
	if _sim.relations.score(npc.id) < 15.0 and role != "spouse":
		_sim.add_log("log.disinherited", {"name": npc.first_name}, "warning")
		return
	_sim.finance.add_cash(p, share)
	npc.finance.cash = 0.0
	_sim.add_log("log.inheritance", {"name": npc.first_name, "amount": int(share)}, "major")


## Removes NPCs nobody cares about anymore (not bonded, not family chain).
func prune(p: Dictionary) -> void:
	var keep := {p.id: true}
	for id in p.get("rels", {}):
		keep[id] = true
		var npc: Dictionary = _sim.state.npc(id)
		if not npc.is_empty():
			if npc.family.spouse != "":
				keep[npc.family.spouse] = true
	for id in _sim.state.data.npcs.keys():
		if not keep.has(id):
			_sim.state.data.npcs.erase(id)
	# Dead bonds (except close family) are forgotten after a while.
	for id in p.rels.keys():
		var npc: Dictionary = _sim.state.npc(id)
		if not npc.alive and not RelationshipSystem.FAMILY_ROLES.has(p.rels[id].role) and p.rels[id].role != "late_spouse":
			p.rels.erase(id)


func spawn_classmates(p: Dictionary) -> void:
	var def: Dictionary = _sim.education.stage_def(p)
	var count := int(def.get("classmates", 2))
	for i in count:
		var npc: Dictionary = _sim.factory.spawn_contextual("classmate", {"age_rel": 0, "age_spread": 1 if int(p.age) < 18 else 4})
		_sim.relations.ensure(npc.id, "classmate", _sim.rng.randf_range(30, 60))
	if def.get("teacher", true):
		var teacher: Dictionary = _sim.factory.spawn_contextual("teacher", {"age_min": 26, "age_max": 60})
		_sim.relations.ensure(teacher.id, "teacher", 50)


func spawn_workplace(p: Dictionary, job_def: Dictionary) -> void:
	var boss: Dictionary = _sim.factory.spawn_contextual("boss", {"age_min": maxi(25, int(p.age)), "age_max": maxi(35, int(p.age) + 20), "awakened": job_def.has("faction")})
	_sim.relations.ensure(boss.id, "boss", _sim.rng.randf_range(40, 60))
	var coworker: Dictionary = _sim.factory.spawn_contextual("coworker", {"age_rel": 0, "age_spread": 8, "awakened": job_def.has("faction")})
	_sim.relations.ensure(coworker.id, "coworker", _sim.rng.randf_range(35, 60))
