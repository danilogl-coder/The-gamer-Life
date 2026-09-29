class_name RelationshipSystem
extends RefCounted
## Persistent bonds between the player and NPCs. Each bond has a role and a
## score; each NPC keeps memories of what the player did, which fade at a
## speed that depends on personality (vengeful NPCs remember for decades).
## Social actions are data (interactions.json).

const FAMILY_ROLES := ["mother", "father", "stepparent", "sibling", "grandparent", "child", "grandchild", "spouse"]
const ROMANTIC_ROLES := ["partner", "fiance", "spouse"]

var _sim


func _init(sim) -> void:
	_sim = sim


# ---------------------------------------------------------------------------
# Basic accessors
# ---------------------------------------------------------------------------

func rels() -> Dictionary:
	return _sim.player().get("rels", {})


func ensure(npc_id: String, role: String, score: float = 50.0) -> void:
	var r := rels()
	if r.has(npc_id):
		if _role_priority(role) > _role_priority(r[npc_id].role):
			r[npc_id].role = role
		return
	r[npc_id] = {"role": role, "score": clampf(score, 0, 100), "since": _sim.player().get("age", 0), "yr": 0}
	_sim.bus.relationship_changed.emit(npc_id)


func score(npc_id: String) -> float:
	return float(rels().get(npc_id, {}).get("score", 0.0))


func role_of(npc_id: String) -> String:
	return rels().get(npc_id, {}).get("role", "")


func set_role(npc_id: String, role: String) -> void:
	if rels().has(npc_id):
		rels()[npc_id].role = role
		_sim.bus.relationship_changed.emit(npc_id)


func change_score(npc_id: String, amount: float) -> void:
	if npc_id == "" or not rels().has(npc_id):
		return
	var r: Dictionary = rels()[npc_id]
	if amount > 0.0:
		amount *= 1.0 + _sim.gamer.mod("social_gain")
	r.score = clampf(float(r.score) + amount, 0, 100)
	_sim.bus.relationship_changed.emit(npc_id)


func end(npc_id: String, reason: String = "cut") -> void:
	if not rels().has(npc_id):
		return
	var role := role_of(npc_id)
	if ROMANTIC_ROLES.has(role):
		set_role(npc_id, "ex")
		var p: Dictionary = _sim.player()
		if p.family.spouse == npc_id:
			p.family.spouse = ""
			_sim.state.npc(npc_id).family.spouse = ""
	elif FAMILY_ROLES.has(role):
		rels()[npc_id].score = minf(float(rels()[npc_id].score), 5.0)
		rels()[npc_id].estranged = true
	else:
		rels().erase(npc_id)
	add_memory(npc_id, reason, 30)


func add_memory(npc_id: String, memory: String, severity: float) -> void:
	if not _sim.state.has_npc(npc_id):
		return
	var npc: Dictionary = _sim.state.npc(npc_id)
	npc.memory.append({"m": memory, "sev": severity, "age": _sim.player().get("age", 0)})
	if npc.memory.size() > 12:
		npc.memory.pop_front()


func memory_weight(npc_id: String) -> float:
	var total := 0.0
	for m in _sim.state.npc(npc_id).get("memory", []):
		total += float(m.sev)
	return total


func first_with_role(p: Dictionary, role: String) -> String:
	var ids: Array = p.get("rels", {}).keys()
	ids.sort()
	for id in ids:
		if p.rels[id].role == role and _alive(id):
			return id
	return ""


func all_with_role(p: Dictionary, role: String) -> Array:
	var out: Array = []
	for id in p.get("rels", {}):
		if p.rels[id].role == role and _alive(id):
			out.append(id)
	out.sort()
	return out


func count_role(p: Dictionary, role: String) -> int:
	return all_with_role(p, role).size()


func role_score(p: Dictionary, role: String) -> float:
	var id := first_with_role(p, role)
	return score(id) if id != "" else 50.0


func spouse_id(p: Dictionary) -> String:
	return first_with_role(p, "spouse")


func partner_id(p: Dictionary) -> String:
	for role in ROMANTIC_ROLES:
		var id := first_with_role(p, role)
		if id != "":
			return id
	return ""


func change_parents(amount: float) -> void:
	var p: Dictionary = _sim.player()
	for role in ["mother", "father", "stepparent"]:
		for id in all_with_role(p, role):
			change_score(id, amount)


## Paths like "rel.actor", "rel.mother", "rel.actor.role".
func resolve_rel(rest: String, ctx: Dictionary):
	var parts := rest.split(".")
	var id := ""
	if parts[0] == "actor":
		id = ctx.get("actor", {}).get("id", "")
	else:
		id = first_with_role(_sim.player(), parts[0])
		if id == "":
			return -1.0 if parts.size() == 1 else null
	if parts.size() > 1:
		return rels().get(id, {}).get(parts[1])
	return score(id)


## Compatibility 0..100 from traits, looks, age gap, CHA and memories.
func compatibility(npc: Dictionary) -> float:
	var p: Dictionary = _sim.player()
	var c := 50.0
	for t in npc.get("traits", []):
		var tdef: Dictionary = _sim.data.get_def("traits", t)
		for pt in p.traits:
			if tdef.get("likes", []).has(pt):
				c += 10
			if tdef.get("dislikes", []).has(pt):
				c -= 12
	c += (float(p.attrs.looks) - 50.0) * 0.25
	c += minf(_sim.gamer.effective_stat(p, "cha") - 10.0, 60.0) * 0.4
	c -= absf(float(npc.age) - float(p.age)) * 1.2
	c -= memory_weight(npc.id) * 0.3
	c += _sim.gamer.mod("charm") * 30.0
	return clampf(c, 0, 100)


# ---------------------------------------------------------------------------
# Interactions (data driven)
# ---------------------------------------------------------------------------

func available_interactions(npc_id: String) -> Array:
	var out: Array = []
	var npc: Dictionary = _sim.state.npc(npc_id)
	var ctx := {"actor": npc}
	for id in _sim.data.table("interactions"):
		var def: Dictionary = _sim.data.table("interactions")[id]
		if _visible(def, npc_id, ctx):
			out.append(id)
	out.sort_custom(func(a, b): return int(_sim.data.get_def("interactions", a).get("order", 50)) < int(_sim.data.get_def("interactions", b).get("order", 50)))
	return out


func _visible(def: Dictionary, npc_id: String, ctx: Dictionary) -> bool:
	var role := role_of(npc_id)
	var p: Dictionary = _sim.player()
	if def.has("roles") and not def.roles.has(role):
		return false
	if def.get("not_roles", []).has(role):
		return false
	if int(p.age) < int(def.get("min_age", 0)):
		return false
	if not ctx.actor.get("alive", true):
		return false
	if _sim.crime.in_prison(p) and not def.get("prison", false) and not ["inmate", "guard"].has(role):
		return false
	return _sim.cond.check_all(def.get("conditions", []), ctx)


func interact(npc_id: String, interaction_id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("interactions", interaction_id)
	if def.is_empty() or not rels().has(npc_id):
		return {"ok": false, "reason": "ui.invalid"}
	var npc: Dictionary = _sim.state.npc(npc_id)
	var ctx := {"actor": npc}
	if not _visible(def, npc_id, ctx):
		return {"ok": false, "reason": "ui.invalid"}
	var r: Dictionary = rels()[npc_id]
	if int(r.get("yr", 0)) >= int(_sim.data.bal("social.interactions_per_npc_year", 3)) and not def.get("unlimited", false):
		return {"ok": false, "reason": "social.tired"}
	var time_cost := int(def.get("time", 0))
	if time_cost > 0 and not _sim.activities.spend_time(time_cost):
		return {"ok": false, "reason": "ui.no_time"}
	var cost := float(def.get("cost", 0))
	if cost > 0.0:
		if float(_sim.player().finance.cash) < cost:
			return {"ok": false, "reason": "ui.no_money"}
		_sim.finance.add_cash(_sim.player(), -cost)
	r.yr = int(r.get("yr", 0)) + 1
	var success := true
	if def.has("chance"):
		success = _sim.prob.roll_spec(def.chance, ctx)
	var branch: Dictionary = def.get("success" if success else "fail", {})
	_sim.effects.run_all(branch.get("effects", []), ctx)
	_sim.activities.bump_counter("social." + interaction_id)
	_sim.activities.bump_counter("social.total")
	_sim.gamer.add_exp(_sim.player(), float(def.get("exp", 3)))
	_sim.gamer.add_stat_xp(_sim.player(), "cha", float(def.get("cha_xp", 4)))
	var text_key: String = "int.%s.%s" % [interaction_id, "ok" if success else "fail"]
	return {"ok": true, "success": success, "key": text_key, "params": {"name": npc.first_name}, "gains": ctx.get("gains", {})}


# ---------------------------------------------------------------------------
# Life-changing bonds
# ---------------------------------------------------------------------------

func marry(npc_id: String) -> void:
	var p: Dictionary = _sim.player()
	var npc: Dictionary = _sim.state.npc(npc_id)
	set_role(npc_id, "spouse")
	p.family.spouse = npc_id
	npc.family.spouse = p.id
	var cost := float(_sim.data.bal("social.wedding_cost", 8000)) * float(_sim.finance.country(p).get("cost_of_living", 1.0))
	_sim.finance.add_cash(p, -cost)
	_sim.add_log("log.married", {"name": npc.first_name}, "major")
	_sim.activities.bump_counter("social.marriages")


func divorce(npc_id: String) -> void:
	var p: Dictionary = _sim.player()
	if p.family.spouse != npc_id:
		return
	var npc: Dictionary = _sim.state.npc(npc_id)
	var split := float(_sim.data.bal("social.divorce_split", 0.5))
	if not _sim.state.flag("prenup_" + npc_id, false):
		var loss := maxf(0.0, float(p.finance.cash)) * split
		_sim.finance.add_cash(p, -loss)
		npc.finance.cash = float(npc.finance.cash) + loss
	set_role(npc_id, "ex")
	p.family.spouse = ""
	npc.family.spouse = ""
	add_memory(npc_id, "divorce", 40)
	_sim.add_log("log.divorced", {"name": npc.first_name}, "major")
	_sim.activities.bump_counter("social.divorces")
	p.attrs.happiness = clampf(float(p.attrs.happiness) - 15, 0, 100)


## Tries for a child with the current partner. Fertility (hidden) of both
## sides and age matter.
func conceive(npc_id: String) -> bool:
	var p: Dictionary = _sim.player()
	var npc: Dictionary = _sim.state.npc(npc_id)
	if npc.sex == p.sex:
		return false
	var mother: Dictionary = p if p.sex == "f" else npc
	var father: Dictionary = npc if p.sex == "f" else p
	var chance := fertility_chance(mother, father)
	if not _sim.prob.roll_neutral(chance):
		return false
	var child: Dictionary = _sim.factory.create_child(mother, father)
	ensure(child.id, "child", 80)
	_sim.add_log("log.child_born", {"name": child.first_name}, "major")
	_sim.activities.bump_counter("family.children")
	_sim.bus.child_born.emit(child.id)
	return true


func fertility_chance(mother: Dictionary, father: Dictionary) -> float:
	var age := float(mother.age)
	var base := float(_sim.data.bal("family.base_fertility", 0.55))
	var age_factor := 1.0
	if age > 30.0:
		age_factor = clampf(1.0 - (age - 30.0) * 0.06, 0.0, 1.0)
	if age < 16.0 or age > 50.0:
		return 0.0
	var fert := (float(mother.hidden.fertility) + float(father.hidden.fertility)) / 100.0
	return clampf(base * age_factor * fert, 0.0, 0.95)


func adopt() -> Dictionary:
	var p: Dictionary = _sim.player()
	var cost := float(_sim.data.bal("family.adoption_cost", 15000))
	if float(p.finance.cash) < cost or int(p.age) < 21:
		return {"ok": false, "reason": "ui.no_money"}
	_sim.finance.add_cash(p, -cost)
	var child: Dictionary = _sim.factory.create_npc(p.country, _sim.rng.pick(["m", "f"]), _sim.rng.randi_range(0, 8))
	child.last_name = p.last_name
	child.family.mother = p.id if p.sex == "f" else ""
	child.family.father = p.id if p.sex == "m" else ""
	p.family.children.append(child.id)
	ensure(child.id, "child", 70)
	_sim.add_log("log.adopted", {"name": child.first_name}, "major")
	return {"ok": true, "key": "family.adopted", "params": {"name": child.first_name}}


# ---------------------------------------------------------------------------
# Year tick
# ---------------------------------------------------------------------------

func process_year(p: Dictionary) -> void:
	for id in rels().keys():
		if not _sim.state.has_npc(id):
			rels().erase(id)
			continue
		var npc: Dictionary = _sim.state.npc(id)
		var r: Dictionary = rels()[id]
		if not npc.alive:
			continue
		_decay(npc, r)
		_fade_memories(npc)
		_romance_checks(p, npc, r)
		r.yr = 0
		if r.role in ["friend", "acquaintance", "classmate", "coworker"] and float(r.score) < 12.0:
			rels().erase(id)
		elif r.role == "friend" and float(r.score) >= 90.0:
			r.role = "best_friend"
			_sim.add_log("log.best_friend", {"name": npc.first_name}, "info")


func _decay(npc: Dictionary, r: Dictionary) -> void:
	var baseline := 60.0 if FAMILY_ROLES.has(r.role) else 35.0
	var speed := 0.08 if int(r.get("yr", 0)) > 0 else 0.15
	for t in npc.traits:
		speed *= float(_sim.data.get_def("traits", t).get("bond_decay", 1.0))
	r.score = clampf(lerpf(float(r.score), baseline, speed), 0, 100)


func _fade_memories(npc: Dictionary) -> void:
	var decay := 0.2
	for t in npc.traits:
		decay *= float(_sim.data.get_def("traits", t).get("memory_decay", 1.0))
	var kept: Array = []
	for m in npc.memory:
		m.sev = float(m.sev) * (1.0 - clampf(decay, 0.02, 0.9))
		if absf(float(m.sev)) >= 2.0:
			kept.append(m)
	npc.memory = kept


func _romance_checks(p: Dictionary, npc: Dictionary, r: Dictionary) -> void:
	if not ROMANTIC_ROLES.has(r.role):
		return
	var loyalty := float(npc.hidden.get("loyalty", 50))
	var cheat := (100.0 - float(r.score)) / 100.0 * (100.0 - loyalty) / 100.0 * float(_sim.data.bal("social.cheat_base", 0.18))
	if _sim.prob.roll_neutral(cheat):
		_sim.events.queue_event("rom_partner_cheated", npc.id)
	elif r.role == "spouse" and float(r.score) < 18.0 and _sim.prob.roll_neutral(0.35):
		_sim.events.queue_event("rom_divorce_request", npc.id)
	elif r.role == "partner" and float(r.score) < 22.0 and _sim.prob.roll_neutral(0.4):
		_sim.add_log("log.breakup_by_npc", {"name": npc.first_name}, "info")
		set_role(npc.id, "ex")


func _alive(id: String) -> bool:
	return _sim.state.has_npc(id) and _sim.state.npc(id).alive


static func _role_priority(role: String) -> int:
	var order := ["acquaintance", "classmate", "coworker", "inmate", "rival", "enemy", "ex", "boss", "teacher", "mentor", "friend", "best_friend", "partner", "fiance", "grandparent", "sibling", "stepparent", "father", "mother", "child", "grandchild", "spouse"]
	return order.find(role)
