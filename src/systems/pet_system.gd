class_name PetSystem
extends RefCounted
## Pets and familiars. Ordinary pets (dog, cat...) give happiness and age like
## anyone. Familiars are TAMED monsters (needs the Taming skill, rolled in
## dungeons — Re:Monster) that fight alongside you and level with you.
## NAMING a familiar (Tensura) drains your MP and triggers its evolution into
## a named species with bonuses for the whole household.

var _sim


func _init(sim) -> void:
	_sim = sim


func pets(p: Dictionary) -> Array:
	return p.get("pets", [])


func alive(p: Dictionary) -> Array:
	return pets(p).filter(func(x): return x.alive)


func get_pet(p: Dictionary, pet_id: String) -> Dictionary:
	for x in pets(p):
		if x.id == pet_id:
			return x
	return {}


func species(x: Dictionary) -> Dictionary:
	return _sim.data.get_def("pets", x.species)


func add(p: Dictionary, species_id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("pets", species_id)
	if def.is_empty():
		return {}
	var names: Array = _sim.data.names.get("pets", ["Bit"])
	var x := {"id": _sim.state.new_id("pet"), "species": species_id, "name": _sim.rng.pick(names), "age": 0,
		"health": 100.0, "bond": 50.0, "level": 1, "exp": 0.0, "named": false, "alive": true}
	p.pets.append(x)
	_sim.gamer.invalidate()
	_sim.add_log("log.pet_new" if def.kind == "pet" else "log.familiar_new", {"name": x.name, "species": "@pet." + species_id}, "major")
	_sim.activities.bump_counter("pets." + def.kind)
	return x


func adopt(p: Dictionary, species_id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("pets", species_id)
	if def.get("kind", "") != "pet":
		return {"ok": false, "reason": "ui.invalid"}
	var cost := float(def.get("cost", 300))
	if float(p.finance.cash) < cost:
		return {"ok": false, "reason": "ui.no_money"}
	_sim.finance.add_cash(p, -cost)
	var x := add(p, species_id)
	return {"ok": true, "key": "pet.adopted", "params": {"name": x.name, "species": "@pet." + species_id}}


## Called by the dungeon on each kill. Needs the Taming skill.
func try_tame(p: Dictionary, monster_id: String) -> String:
	if not _sim.skills.knows(p, "taming") or alive(p).filter(func(x): return species(x).kind == "familiar").size() >= 3:
		return ""
	var target := ""
	for sid in _sim.data.table("pets"):
		if _sim.data.table("pets")[sid].get("from", "") == monster_id:
			target = sid
	if target == "":
		return ""
	var chance: float = 0.03 + _sim.skills.level(p, "taming") * 0.012 + _sim.gamer.effective_stat(p, "cha") * 0.0006
	if not _sim.prob.roll(_sim.prob.apply_luck(chance)):
		return ""
	_sim.skills.add_xp(p, "taming", 12.0)
	return add(p, target).get("name", "")


## Tensura naming: costs most of your MP, evolves the familiar.
func name_familiar(p: Dictionary, pet_id: String) -> Dictionary:
	var x := get_pet(p, pet_id)
	var def := species(x)
	if x.is_empty() or def.get("kind", "") != "familiar" or x.named or not def.has("named"):
		return {"ok": false, "reason": "ui.invalid"}
	var cost: float = _sim.gamer.max_mp(p) * 0.8
	if float(p.gamer.mp) < cost:
		return {"ok": false, "reason": "ui.no_mp"}
	p.gamer.mp = float(p.gamer.mp) - cost
	var old: String = x.species
	x.species = def.named
	x.named = true
	x.level = int(x.level) + 5
	x.bond = 100.0
	_sim.gamer.invalidate()
	_sim.activities.bump_counter("pets.named")
	_sim.skills.learn(p, "naming")
	_sim.add_log("log.familiar_named", {"name": x.name, "from": "@pet." + old, "to": "@pet." + x.species}, "major")
	_sim.notify("evolve", "sys.familiar_evolved", {"name": x.name, "to": "@pet." + x.species})
	return {"ok": true, "key": "pet.named", "params": {"name": x.name, "to": "@pet." + x.species}}


func interact(p: Dictionary, pet_id: String, action: String) -> Dictionary:
	var x := get_pet(p, pet_id)
	if x.is_empty() or not x.alive:
		return {"ok": false, "reason": "ui.invalid"}
	match action:
		"play":
			if not _sim.activities.spend_time(1):
				return {"ok": false, "reason": "ui.no_time"}
			x.bond = minf(100.0, float(x.bond) + 12.0)
			p.attrs.happiness = clampf(float(p.attrs.happiness) + 5.0, 0, 100)
			p.attrs.stress = clampf(float(p.attrs.stress) - 6.0, 0, 100)
			_sim.activities.bump_counter("pets.play")
			return {"ok": true, "key": "pet.played", "params": {"name": x.name}}
		"vet":
			var cost := 250.0 * float(_sim.finance.country(p).get("cost_of_living", 1.0))
			if float(p.finance.cash) < cost:
				return {"ok": false, "reason": "ui.no_money"}
			_sim.finance.add_cash(p, -cost)
			x.health = minf(100.0, float(x.health) + 30.0)
			return {"ok": true, "key": "pet.vet", "params": {"name": x.name}}
		"name":
			return name_familiar(p, pet_id)
		"release":
			x.alive = false
			x.released = true
			_sim.gamer.invalidate()
			return {"ok": true, "key": "pet.released", "params": {"name": x.name}}
	return {"ok": false, "reason": "ui.invalid"}


## Familiars fight: extra damage per dungeon round.
func combat_bonus(p: Dictionary) -> float:
	var total := 0.0
	for x in alive(p):
		var def := species(x)
		if def.get("kind", "") == "familiar":
			total += float(def.get("atk", 0)) * (1.0 + float(x.level) * float(def.get("growth", 0.15))) * (0.5 + float(x.bond) / 200.0)
	return total


## Familiars share dungeon EXP.
func share_exp(p: Dictionary, amount: float) -> void:
	for x in alive(p):
		if species(x).get("kind", "") != "familiar":
			continue
		x.exp = float(x.exp) + amount * 0.5
		var need := 80.0 * pow(float(x.level), 1.4)
		while float(x.exp) >= need:
			x.exp = float(x.exp) - need
			x.level = int(x.level) + 1
			need = 80.0 * pow(float(x.level), 1.4)


func mods(p: Dictionary) -> Dictionary:
	var out := {}
	for x in alive(p):
		var m: Dictionary = species(x).get("mods", {})
		for k in m:
			out[k] = float(out.get(k, 0.0)) + float(m[k])
	return out


func process_year(p: Dictionary) -> void:
	for x in alive(p):
		var def := species(x)
		x.age = int(x.age) + 1
		x.bond = maxf(0.0, float(x.bond) - 6.0)
		var life := float(def.get("lifespan", 12))
		if float(x.age) > life * 0.7:
			x.health = float(x.health) - 12.0 * (float(x.age) / life)
		p.attrs.happiness = clampf(float(p.attrs.happiness) + float(def.get("happiness", 2)) * float(x.bond) / 100.0, 0, 100)
		if float(x.health) <= 0.0 or float(x.age) >= life + _sim.rng.randi_range(0, 3):
			x.alive = false
			p.attrs.happiness = clampf(float(p.attrs.happiness) - 10.0, 0, 100)
			_sim.add_log("log.pet_died", {"name": x.name, "age": x.age}, "major")
			_sim.gamer.invalidate()
	# Keep only a small memorial of dead pets.
	var kept: Array = []
	for x in pets(p):
		if x.alive or kept.size() < 8:
			kept.append(x)
	p.pets = kept
