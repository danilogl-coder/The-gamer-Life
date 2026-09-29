class_name HealthSystem
extends RefCounted
## Aging, diseases, injuries, habits/addictions, stress and death.
## VIT and the Gamer's Body push back against aging; WIS and the Gamer's Mind
## tame stress. Overpowered characters can live very long lives — but never
## forever unless they earn it.

var _sim


func _init(sim) -> void:
	_sim = sim


func add_condition(p: Dictionary, id: String) -> void:
	var def: Dictionary = _sim.data.get_def("diseases", id)
	if def.is_empty() or p.health.conditions.has(id):
		return
	p.health.conditions[id] = {"years": 0, "severity": float(def.get("severity", 30))}
	_sim.gamer.invalidate()
	if p.get("is_player", false):
		_sim.add_log("log.condition", {"cond": "@disease." + id}, "warning")
		_sim.bus.disease_added.emit(id)
		_sim.activities.bump_counter("disease." + id)


func remove_condition(p: Dictionary, id: String) -> void:
	if p.health.conditions.erase(id):
		_sim.gamer.invalidate()
		if p.get("is_player", false):
			_sim.add_log("log.cured", {"cond": "@disease." + id}, "info")


func injure(p: Dictionary, id: String = "injury_minor") -> void:
	if _sim.gamer.mod("injury_immune") > 0.0 and _sim.data.get_def("diseases", id).get("injury", false):
		_sim.notify("system", "sys.body_negated", {})
		return
	add_condition(p, id)
	var def: Dictionary = _sim.data.get_def("diseases", id)
	p.attrs.health = clampf(float(p.attrs.health) - float(def.get("on_add_health", 10)), 0, 100)


func change_habit(p: Dictionary, habit: String, amount: float) -> void:
	var v := clampf(float(p.health.habits.get(habit, 0)) + amount, 0, 100)
	p.health.habits[habit] = v
	var addiction := "addiction_" + habit
	if v >= float(_sim.data.bal("health.addiction_threshold", 60)) and not p.health.conditions.has(addiction):
		var resist: float = float(p.hidden.get("addiction_resist", 50)) / 100.0 + _sim.gamer.mod("addiction_resist")
		if _sim.prob.roll_neutral(clampf(0.5 - resist * 0.4, 0.05, 0.9)):
			add_condition(p, addiction)


func habit_costs(p: Dictionary) -> float:
	var total := 0.0
	for h in p.health.get("habits", {}):
		total += float(p.health.habits[h]) * float(_sim.data.bal("health.habit_cost." + h, 20))
	return total


# ---------------------------------------------------------------------------
# Year tick
# ---------------------------------------------------------------------------

func process_year(p: Dictionary) -> void:
	var age := int(p.age)
	var vit: float = _sim.gamer.effective_stat(p, "vit")
	var mitigation := clampf(vit * float(_sim.data.bal("health.vit_mitigation", 0.012)) + _sim.gamer.mod("aging_resist"), 0.0, 0.9)
	var decline := maxf(0.0, age - float(_sim.data.bal("health.decline_start", 35))) * float(_sim.data.bal("health.decline_rate", 0.09))
	var h := float(p.attrs.health) - decline * (1.0 - mitigation)
	h += _sim.gamer.mod("health_regen") * 10.0
	h += (float(p.health.fitness) - 40.0) * 0.05
	# Stress: decays with WIS, hurts when high.
	var stress := float(p.attrs.stress)
	stress -= float(_sim.data.bal("health.stress_decay", 8)) + _sim.gamer.effective_stat(p, "wis") * 0.15 + (float(p.hidden.stress_tolerance) - 50.0) * 0.05
	if stress > 70.0:
		h -= 3.0
		p.attrs.happiness = clampf(float(p.attrs.happiness) - 4, 0, 100)
		_sim.activities.bump_counter("stress.high_years")
	p.attrs.stress = clampf(stress, 0, 100)
	p.health.fitness = clampf(float(p.health.fitness) - 4.0, 0, 100)
	for habit in p.health.habits.keys():
		p.health.habits[habit] = maxf(0.0, float(p.health.habits[habit]) - 6.0)
	h += _progress_conditions(p)
	p.attrs.health = clampf(h, 0, 100)
	_roll_new_conditions(p)
	# Happiness drifts to a personal baseline.
	var base_happy: float = 55.0 + (float(p.hidden.get("stress_tolerance", 50)) - 50.0) * 0.2 + _sim.gamer.mod("happiness") * 20.0
	p.attrs.happiness = clampf(lerpf(float(p.attrs.happiness), base_happy, 0.15), 0, 100)
	_death_check(p)


func _progress_conditions(p: Dictionary) -> float:
	var delta := 0.0
	for id in p.health.conditions.keys():
		var def: Dictionary = _sim.data.get_def("diseases", id)
		var c: Dictionary = p.health.conditions[id]
		c.years = int(c.years) + 1
		delta -= float(def.get("yearly_health", 3))
		if def.has("death_chance") and _sim.prob.roll_neutral(float(def.death_chance) * (1.0 - clampf(_sim.gamer.mod("disease_resist"), 0, 0.9))):
			kill(p, "cause.disease." + id)
			return delta
		var heal: float = float(def.get("natural_cure", 0.0)) + _sim.gamer.mod("health_regen") * 0.3
		if not def.get("chronic", false) and _sim.prob.roll_neutral(heal):
			remove_condition(p, id)
	return delta


func _roll_new_conditions(p: Dictionary) -> void:
	var age := int(p.age)
	var resist := clampf(_sim.gamer.mod("disease_resist") + _sim.gamer.effective_stat(p, "vit") * 0.004, 0.0, 0.95)
	var risk := 1.0 + (float(p.hidden.disease_risk) - 50.0) / 60.0
	for id in _sim.data.table("diseases"):
		var def: Dictionary = _sim.data.table("diseases")[id]
		if not def.has("chance") or p.health.conditions.has(id):
			continue
		if age < int(def.get("min_age", 0)) or age > int(def.get("max_age", 200)):
			continue
		var chance := float(def.chance) * risk * (1.0 - resist)
		chance *= 1.0 + maxf(0.0, age - float(def.get("age_ramp_from", 999))) * float(def.get("age_ramp", 0.0))
		for f in def.get("factors", []):
			var v = _sim.resolve(f.path, {})
			if v != null and float(v) >= float(f.get("above", 0)):
				chance *= float(f.get("mult", 1.5))
		if _sim.prob.roll_neutral(chance):
			add_condition(p, id)


func mortality(ch: Dictionary) -> float:
	var age := float(ch.age)
	var a := float(_sim.data.bal("health.gompertz_a", 0.00004))
	var b := float(_sim.data.bal("health.gompertz_b", 0.088))
	var m := a * exp(b * age)
	var longevity := (float(ch.hidden.get("longevity", 50)) - 50.0) / 150.0
	if ch.get("is_player", false):
		longevity += clampf(_sim.gamer.effective_stat(ch, "vit") * 0.003, 0.0, 0.5) + _sim.gamer.mod("lifespan")
	m *= clampf(1.0 - longevity, 0.03, 2.0)
	if float(ch.attrs.health) < 15.0:
		m += 0.12
	if age < 1.0:
		m += float(_sim.data.bal("health.infant_mortality", 0.004))
	return clampf(m, 0.0, 0.95)


func _death_check(p: Dictionary) -> void:
	if not p.alive:
		return
	if float(p.attrs.health) <= 0.0:
		kill(p, "cause.health")
		return
	if _sim.prob.roll_neutral(mortality(p)):
		kill(p, "cause.old_age" if int(p.age) >= 70 else "cause.natural")


func kill(p: Dictionary, cause: String) -> void:
	if not p.alive:
		return
	p.alive = false
	p.death_cause = cause
	if p.get("is_player", false):
		_sim.state.data.dead = true
		_sim.state.data.pending_events.clear()
		_sim.add_log("log.died", {"cause": "@" + cause, "age": p.age}, "major")
		_sim.legacy.on_player_death(p, cause)


# ---------------------------------------------------------------------------
# Medical actions
# ---------------------------------------------------------------------------

func treat(p: Dictionary, id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("diseases", id)
	if not p.health.conditions.has(id):
		return {"ok": false, "reason": "ui.invalid"}
	var cost := float(def.get("treat_cost", 2000)) * float(_sim.finance.country(p).get("cost_of_living", 1.0))
	if float(p.finance.cash) < cost:
		return {"ok": false, "reason": "ui.no_money"}
	_sim.finance.add_cash(p, -cost)
	if _sim.prob.roll_spec({"base": float(def.get("treat_success", 0.6)), "mods": [{"path": "mod.treatment", "per": 1.0}]}):
		remove_condition(p, id)
		return {"ok": true, "key": "health.treated", "params": {"cond": "@disease." + id}}
	return {"ok": false, "reason": "health.treat_failed"}
