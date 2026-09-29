class_name CrimeSystem
extends RefCounted
## Crime → (maybe) investigation years later → arrest → trial → sentence →
## prison as its own game state. Nothing is "button → money": each crime
## leaves heat and evidence that the future can collect on.

var _sim


func _init(sim) -> void:
	_sim = sim


func in_prison(p: Dictionary) -> bool:
	return int(p.get("criminal", {}).get("prison", {}).get("years_left", 0)) > 0


func commit(crime_id: String, ctx: Dictionary) -> Dictionary:
	var p: Dictionary = _sim.player()
	var def: Dictionary = _sim.data.get_def("crimes", crime_id)
	if def.is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	_sim.activities.bump_counter("crime.total")
	_sim.activities.bump_counter("crime." + crime_id)
	p.hidden.karma = clampf(float(p.hidden.get("karma", 50)) - float(def.get("severity", 10)) * 0.35, 0.0, 100.0)
	_sim.bus.crime_committed.emit(crime_id)
	var stat: String = def.get("stat", "dex")
	var spec := {"base": float(def.get("success", 0.6)), "mods": [
		{"path": "stat." + stat, "per": 0.006, "offset": 10.0, "max": 0.35},
		{"path": "mod.crime_success", "per": 1.0},
		{"path": "skill.stealth", "per": 0.02}]}
	if _sim.prob.roll_spec(spec):
		var reward: float = _sim.rng.randf_range(float(def.reward[0]), float(def.reward[1])) * float(_sim.finance.country(p).get("salary_mult", 1.0))
		if def.has("reward_salary"):
			reward = _sim.career.current_salary(p) * _sim.rng.randf_range(float(def.reward_salary[0]), float(def.reward_salary[1]))
		_sim.finance.add_cash(p, reward)
		ctx.gains["money"] = reward
		p.criminal.heat = float(p.criminal.heat) + float(def.get("heat", 10)) * maxf(0.2, 1.0 - _sim.gamer.mod("stealth"))
		_sim.gamer.add_exp(p, float(def.get("exp", 10)))
		# Evidence may surface later.
		if _sim.prob.roll_neutral(float(def.get("investigation", 0.15)) * (1.0 + _sim.society.policy("police")) + float(p.criminal.heat) * 0.003):
			_sim.events.schedule("crime_investigation", _sim.rng.randi_range(1, 4))
			_sim.state.set_flag("pending_case_" + crime_id)
			p.criminal.pending = crime_id
		return {"ok": true, "key": "crime.%s.ok" % crime_id, "params": {"amount": int(reward)}}
	# Caught in the act: arrested, the trial comes next (lawyer choice event).
	_sim.activities.bump_counter("crime.caught")
	arrest(p, crime_id, 0.25)
	return {"ok": true, "success": false, "key": "crime.caught", "params": {"crime": "@crime." + crime_id}}


## Arrest now; the TRIAL happens when the player picks a lawyer
## (event "trial_lawyer": public defender / cheap / top firm).
func arrest(p: Dictionary, crime_id: String, extra_evidence: float) -> void:
	p.criminal.pending = crime_id
	p.criminal.pending_extra = extra_evidence
	_sim.add_log("log.arrested", {"crime": "@crime." + crime_id}, "major")
	_sim.events.queue_special("trial_lawyer")


func lawyer_cost(p: Dictionary, lawyer_id: String) -> float:
	return float(_sim.data.get_def("lawyers", lawyer_id).get("cost", 0)) * maxf(0.5, float(_sim.finance.country(p).get("cost_of_living", 1.0)))


func add_record(p: Dictionary, crime_id: String) -> void:
	p.criminal.record.append({"crime": crime_id, "age": p.age})
	p.attrs.reputation = clampf(float(p.attrs.reputation) - float(_sim.data.get_def("crimes", crime_id).get("severity", 10)) * 0.5, 0, 100)


## Returns the sentence in years (0 = acquitted / fined).
## lawyer_id: "public" | "cheap" | "elite" | "auto" (best affordable).
func arrest_and_trial(p: Dictionary, crime_id: String, extra_evidence: float, lawyer_id: String = "auto") -> int:
	var def: Dictionary = _sim.data.get_def("crimes", crime_id)
	if lawyer_id == "auto":
		lawyer_id = "public"
		for lid in ["cheap", "elite"]:
			if float(p.finance.cash) * 0.5 >= lawyer_cost(p, lid):
				lawyer_id = lid
	var cost := minf(lawyer_cost(p, lawyer_id), maxf(0.0, float(p.finance.cash)))
	_sim.finance.add_cash(p, -cost)
	var lawyer_bonus := float(_sim.data.get_def("lawyers", lawyer_id).get("bonus", 0.0))
	var conviction: float = float(def.get("evidence", 0.5)) + extra_evidence + p.criminal.record.size() * 0.08
	conviction -= lawyer_bonus + (float(p.attrs.reputation) - 50.0) * 0.003 + _sim.gamer.effective_stat(p, "cha") * 0.002
	p.criminal.erase("pending")
	p.criminal.erase("pending_extra")
	if not _sim.prob.roll_neutral(clampf(conviction, 0.05, 0.95)):
		_sim.add_log("log.acquitted", {}, "info")
		return 0
	add_record(p, crime_id)
	var years: int = _sim.rng.randi_range(int(def.sentence[0]), int(def.sentence[1]))
	if years <= 0:
		var fine := float(def.get("fine", 2000))
		_sim.finance.add_cash(p, -fine)
		_sim.add_log("log.fined", {"amount": int(fine)}, "warning")
		return 0
	imprison(p, years)
	return years


func imprison(p: Dictionary, years: int) -> void:
	p.criminal.prison = {"years_left": years, "total": years, "served": 0, "behavior": 60.0, "gang": "", "life": years >= 50}
	p.criminal.heat = 0.0
	_sim.add_log("log.prison", {"years": years}, "major")
	_sim.activities.bump_counter("prison.sentences")
	if _sim.education.in_school(p):
		_sim.education.drop_out(p)
	_sim.relations.change_parents(-15)
	var inmate: Dictionary = _sim.factory.spawn_contextual("inmate", {"age_min": 20, "age_max": 55})
	_sim.relations.ensure(inmate.id, "inmate", 35)


## Called by the year pipeline.
func process_year(p: Dictionary) -> void:
	p.criminal.heat = maxf(0.0, float(p.criminal.heat) - 5.0)
	if not in_prison(p):
		return
	var pr: Dictionary = p.criminal.prison
	pr.years_left = int(pr.years_left) - 1
	pr.served = int(pr.get("served", 0)) + 1
	_sim.activities.bump_counter("prison.years")
	p.attrs.happiness = clampf(float(p.attrs.happiness) - 5, 0, 100)
	_family_visits(p)
	if int(pr.years_left) <= 0:
		release(p, "log.released")
		return
	# Parole: good behaviour after serving at least half the sentence.
	if float(pr.get("behavior", 50)) >= 70.0 and int(pr.served) * 2 >= int(pr.get("total", 1)) and not pr.get("life", false):
		if _sim.prob.roll_neutral((float(pr.behavior) - 60.0) / 60.0):
			_sim.activities.bump_counter("prison.parole")
			release(p, "log.parole")
			return
	pr.behavior = clampf(float(pr.get("behavior", 50)) + 4.0, 0.0, 100.0)
	if pr.get("gang", "") != "" and _sim.prob.roll_neutral(0.25):
		_sim.events.queue_event("prison_gang_war")


func release(p: Dictionary, key: String) -> void:
	p.criminal.prison = {}
	_sim.add_log(key, {}, "major")
	_sim.activities.start_year(p)


func change_behavior(p: Dictionary, amount: float) -> void:
	if in_prison(p):
		p.criminal.prison.behavior = clampf(float(p.criminal.prison.get("behavior", 50)) + amount, 0.0, 100.0)


func _family_visits(p: Dictionary) -> void:
	for id in p.rels:
		var r: Dictionary = p.rels[id]
		if r.role in ["mother", "father", "spouse", "child", "sibling"] and float(r.score) >= 55.0 and _sim.state.npc(id).get("alive", false):
			p.attrs.happiness = clampf(float(p.attrs.happiness) + 3.0, 0, 100)
			r.score = float(r.score) - 2.0
		elif r.role in ["partner", "spouse"] and float(r.score) < 40.0 and _sim.prob.roll_neutral(0.3):
			_sim.relations.end(id, "prison")


func join_gang(p: Dictionary, gang_id: String) -> Dictionary:
	if not in_prison(p) or _sim.data.get_def("gangs", gang_id).is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	var gdef: Dictionary = _sim.data.get_def("gangs", gang_id)
	var spec := {"base": 0.4, "mods": [{"path": "stat." + gdef.get("stat", "str"), "per": 0.01, "offset": 10.0, "max": 0.4}]}
	if not _sim.prob.roll_spec(spec):
		return {"ok": false, "reason": "prison.gang_rejected"}
	p.criminal.prison.gang = gang_id
	change_behavior(p, -15.0)
	_sim.activities.bump_counter("prison.gang")
	_sim.add_log("log.gang_join", {"gang": "@gang." + gang_id}, "major")
	return {"ok": true, "key": "prison.gang_joined", "params": {"gang": "@gang." + gang_id}}


func bribe_guard(p: Dictionary) -> Dictionary:
	var cost := 3000.0 * maxf(0.5, float(_sim.finance.country(p).get("cost_of_living", 1.0)))
	if float(p.finance.cash) < cost:
		return {"ok": false, "reason": "ui.no_money"}
	_sim.finance.add_cash(p, -cost)
	if _sim.prob.roll_spec({"base": 0.45, "mods": [{"path": "stat.cha", "per": 0.008, "offset": 10.0, "max": 0.3}]}):
		p.criminal.prison.years_left = maxi(1, int(p.criminal.prison.years_left) - 1)
		change_behavior(p, 10.0)
		return {"ok": true, "key": "prison.bribe_ok", "params": {}}
	p.criminal.prison.years_left = int(p.criminal.prison.years_left) + 1
	change_behavior(p, -20.0)
	return {"ok": false, "reason": "prison.bribe_fail"}


## Riot: the bigger the gang, the better the odds; can end in escape.
func riot(p: Dictionary) -> Dictionary:
	var spec := {"base": 0.12, "mods": [{"path": "stat.cha", "per": 0.004, "offset": 10.0, "max": 0.2}, {"path": "stat.str", "per": 0.004, "offset": 10.0, "max": 0.2}]}
	if p.criminal.prison.get("gang", "") != "":
		spec.base = float(spec.base) + 0.12
	change_behavior(p, -40.0)
	_sim.activities.bump_counter("prison.riots")
	if _sim.prob.roll_spec(spec):
		release(p, "log.riot_escape")
		_sim.state.set_flag("fugitive")
		p.criminal.heat = 70.0
		return {"ok": true, "key": "prison.riot_escape", "params": {}}
	p.criminal.prison.years_left = int(p.criminal.prison.years_left) + 3
	if _sim.prob.roll_neutral(0.35):
		_sim.health.injure(p, "injury_minor")
	return {"ok": false, "reason": "prison.riot_fail"}


## Result of the escape mini-game (or a roll when played headless).
func escape_result(p: Dictionary, success: bool) -> Dictionary:
	if not in_prison(p):
		return {"ok": false, "reason": "ui.invalid"}
	_sim.activities.bump_counter("prison.escape_attempts")
	if success:
		release(p, "log.escaped")
		_sim.state.set_flag("fugitive")
		p.criminal.heat = 60.0
		return {"ok": true, "key": "prison.escape_ok", "params": {}}
	p.criminal.prison.years_left = int(p.criminal.prison.years_left) + 2
	change_behavior(p, -30.0)
	return {"ok": false, "reason": "prison.escape_fail"}


func attempt_escape(p: Dictionary) -> Dictionary:
	var spec := {"base": 0.08, "mods": [{"path": "stat.dex", "per": 0.004, "max": 0.35}, {"path": "skill.stealth", "per": 0.03}]}
	if _sim.prob.roll_spec(spec):
		release(p, "log.escaped")
		_sim.state.set_flag("fugitive")
		p.criminal.heat = 60.0
		return {"ok": true, "key": "prison.escape_ok", "params": {}}
	p.criminal.prison.years_left = int(p.criminal.prison.years_left) + 2
	return {"ok": false, "reason": "prison.escape_fail"}


## Appeal through a law firm (lawyers.json): pricier firms win more often;
## a partial win cuts years instead of freeing you.
func appeal(p: Dictionary, lawyer_id: String = "cheap") -> Dictionary:
	var cost := lawyer_cost(p, lawyer_id) * 0.7
	if float(p.finance.cash) < cost:
		return {"ok": false, "reason": "ui.no_money"}
	_sim.finance.add_cash(p, -cost)
	var bonus := float(_sim.data.get_def("lawyers", lawyer_id).get("bonus", 0.0))
	var roll: float = _sim.rng.randf()
	var win: float = 0.06 + bonus * 0.8 + _sim.prob.luck_bonus() * 0.2
	if roll < win:
		release(p, "log.appeal_won")
		return {"ok": true, "key": "prison.appeal_ok", "params": {}}
	if roll < win * 2.2:
		p.criminal.prison.years_left = maxi(1, int(int(p.criminal.prison.years_left) * 0.6))
		return {"ok": true, "key": "prison.appeal_partial", "params": {"n": int(p.criminal.prison.years_left)}}
	return {"ok": false, "reason": "prison.appeal_fail"}


## Civil lawsuit against someone (employer, doctor, neighbour, ex...).
func sue(p: Dictionary, target: String, lawyer_id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("lawsuits", target)
	if def.is_empty() or not _sim.cond.check_all(def.get("conditions", []), {}):
		return {"ok": false, "reason": "ui.invalid"}
	var cost := lawyer_cost(p, lawyer_id)
	if float(p.finance.cash) < cost:
		return {"ok": false, "reason": "ui.no_money"}
	_sim.finance.add_cash(p, -cost)
	_sim.activities.bump_counter("lawsuits.filed")
	var spec := {"base": float(def.get("base", 0.3)) + float(_sim.data.get_def("lawyers", lawyer_id).get("bonus", 0.0)),
		"mods": [{"path": "stat.int", "per": 0.003, "offset": 10.0, "max": 0.15}, {"path": "stat.cha", "per": 0.003, "offset": 10.0, "max": 0.15}]}
	if _sim.prob.roll_spec(spec):
		var award: float = _sim.rng.randf_range(float(def.award[0]), float(def.award[1])) * float(_sim.finance.country(p).get("salary_mult", 1.0))
		_sim.finance.add_cash(p, award)
		_sim.activities.bump_counter("lawsuits.won")
		_sim.effects.run_all(def.get("on_win", []), {})
		_sim.add_log("log.lawsuit_won", {"target": "@lawsuit." + target, "v": int(award)}, "major")
		return {"ok": true, "key": "lawsuit.won", "params": {"v": int(award)}, "gains": {"money": award}}
	_sim.effects.run_all(def.get("on_lose", []), {})
	_sim.add_log("log.lawsuit_lost", {"target": "@lawsuit." + target}, "info")
	return {"ok": false, "reason": "lawsuit.lost"}
