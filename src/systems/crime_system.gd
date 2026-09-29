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
	_sim.bus.crime_committed.emit(crime_id)
	var stat: String = def.get("stat", "dex")
	var spec := {"base": float(def.get("success", 0.6)), "mods": [
		{"path": "stat." + stat, "per": 0.006, "offset": 10.0, "max": 0.35},
		{"path": "mod.crime_success", "per": 1.0},
		{"path": "skill.stealth", "per": 0.02}]}
	if _sim.prob.roll_spec(spec):
		var reward: float = _sim.rng.randf_range(float(def.reward[0]), float(def.reward[1])) * float(_sim.finance.country(p).get("salary_mult", 1.0))
		_sim.finance.add_cash(p, reward)
		ctx.gains["money"] = reward
		p.criminal.heat = float(p.criminal.heat) + float(def.get("heat", 10)) * maxf(0.2, 1.0 - _sim.gamer.mod("stealth"))
		_sim.gamer.add_exp(p, float(def.get("exp", 10)))
		# Evidence may surface later.
		if _sim.prob.roll_neutral(float(def.get("investigation", 0.15)) + float(p.criminal.heat) * 0.003):
			_sim.events.schedule("crime_investigation", _sim.rng.randi_range(1, 4))
			_sim.state.set_flag("pending_case_" + crime_id)
			p.criminal.pending = crime_id
		return {"ok": true, "key": "crime.%s.ok" % crime_id, "params": {"amount": int(reward)}}
	# Caught in the act.
	_sim.activities.bump_counter("crime.caught")
	var sentence := arrest_and_trial(p, crime_id, 0.25)
	return {"ok": true, "success": false, "key": "crime.caught" if sentence > 0 else "crime.caught_free", "params": {"years": sentence}}


func add_record(p: Dictionary, crime_id: String) -> void:
	p.criminal.record.append({"crime": crime_id, "age": p.age})
	p.attrs.reputation = clampf(float(p.attrs.reputation) - float(_sim.data.get_def("crimes", crime_id).get("severity", 10)) * 0.5, 0, 100)


## Returns the sentence in years (0 = acquitted / fined).
func arrest_and_trial(p: Dictionary, crime_id: String, extra_evidence: float) -> int:
	var def: Dictionary = _sim.data.get_def("crimes", crime_id)
	var lawyer_cost := minf(float(p.finance.cash) * 0.3, float(_sim.data.bal("justice.lawyer_cost", 8000)))
	var lawyer := lawyer_cost / float(_sim.data.bal("justice.lawyer_cost", 8000))
	_sim.finance.add_cash(p, -lawyer_cost)
	var conviction: float = float(def.get("evidence", 0.5)) + extra_evidence + p.criminal.record.size() * 0.08
	conviction -= lawyer * 0.25 + (float(p.attrs.reputation) - 50.0) * 0.003 + _sim.gamer.effective_stat(p, "cha") * 0.002
	_sim.add_log("log.arrested", {"crime": "@crime." + crime_id}, "major")
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
	p.criminal.prison = {"years_left": years, "total": years}
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
	p.criminal.prison.years_left = int(p.criminal.prison.years_left) - 1
	_sim.activities.bump_counter("prison.years")
	p.attrs.happiness = clampf(float(p.attrs.happiness) - 5, 0, 100)
	if int(p.criminal.prison.years_left) <= 0:
		release(p, "log.released")


func release(p: Dictionary, key: String) -> void:
	p.criminal.prison = {}
	_sim.add_log(key, {}, "major")
	_sim.activities.start_year(p)


func attempt_escape(p: Dictionary) -> Dictionary:
	var spec := {"base": 0.08, "mods": [{"path": "stat.dex", "per": 0.004, "max": 0.35}, {"path": "skill.stealth", "per": 0.03}]}
	if _sim.prob.roll_spec(spec):
		release(p, "log.escaped")
		_sim.state.set_flag("fugitive")
		p.criminal.heat = 60.0
		return {"ok": true, "key": "prison.escape_ok", "params": {}}
	p.criminal.prison.years_left = int(p.criminal.prison.years_left) + 2
	return {"ok": false, "reason": "prison.escape_fail"}


func appeal(p: Dictionary) -> Dictionary:
	var cost := float(_sim.data.bal("justice.appeal_cost", 5000))
	if float(p.finance.cash) < cost:
		return {"ok": false, "reason": "ui.no_money"}
	_sim.finance.add_cash(p, -cost)
	if _sim.prob.roll_spec({"base": 0.12, "mods": [{"path": "stat.int", "per": 0.003, "max": 0.2}]}):
		release(p, "log.appeal_won")
		return {"ok": true, "key": "prison.appeal_ok", "params": {}}
	return {"ok": false, "reason": "prison.appeal_fail"}
