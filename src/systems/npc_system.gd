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
		_life_stage(npc)
		if _sim.prob.roll_neutral(_sim.health.mortality(npc)):
			_npc_dies(p, npc)
	prune(p)


func relevant_ids(p: Dictionary) -> Array:
	var ids: Array = p.get("rels", {}).keys()
	ids.sort()
	return ids


func _life_stage(npc: Dictionary) -> void:
	var age := int(npc.age)
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
	# Player's children build their own families: grandchildren appear.
	var role: String = _sim.relations.role_of(npc.id)
	if role == "child" and age >= 24 and npc.family.spouse == "" and _sim.prob.roll_neutral(0.12):
		var spouse: Dictionary = _sim.factory.create_npc(npc.country, "f" if npc.sex == "m" else "m", age + _sim.rng.randi_range(-3, 3))
		_sim.state.add_npc(spouse)
		npc.family.spouse = spouse.id
		spouse.family.spouse = npc.id
		_sim.add_log("log.child_married", {"name": npc.first_name}, "info")
	elif role == "child" and npc.family.spouse != "" and age < 42 and npc.family.children.size() < 3 and _sim.prob.roll_neutral(0.15):
		var spouse: Dictionary = _sim.state.npc(npc.family.spouse)
		if not spouse.is_empty():
			var mother: Dictionary = npc if npc.sex == "f" else spouse
			var father: Dictionary = spouse if npc.sex == "f" else npc
			var gc: Dictionary = _sim.factory.create_child(mother, father)
			_sim.relations.ensure(gc.id, "grandchild", 70)
			_sim.add_log("log.grandchild", {"name": gc.first_name, "parent": npc.first_name}, "major")


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
