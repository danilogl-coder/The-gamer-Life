class_name SpecialCareerSystem
extends RefCounted
## Registry + dispatcher for modular special careers (see SpecialCareer).
## data/special_careers.json:
##   {"id": "music", "script": "res://src/systems/careers/music_career.gd",
##    "min_age": 12, "conditions": [...], "exclusive_job": false}

var _sim
var _careers: Dictionary = {}


func _init(sim) -> void:
	_sim = sim
	for id in _sim.data.table("special_careers"):
		var def: Dictionary = _sim.data.table("special_careers")[id]
		var script = load(def.script)
		if script == null:
			push_error("Special career script missing: " + def.script)
			continue
		_careers[id] = script.new().setup(sim, def)


func career(id: String) -> SpecialCareer:
	return _careers.get(id)


func ids() -> Array:
	var out: Array = _careers.keys()
	out.sort_custom(func(a, b): return int(_careers[a].def.get("order", 50)) < int(_careers[b].def.get("order", 50)))
	return out


func active(p: Dictionary) -> Array:
	var out: Array = []
	for id in ids():
		if p.get("special", {}).has(id):
			out.append(id)
	return out


func block_reason(p: Dictionary, id: String) -> String:
	var c := career(id)
	if c == null:
		return "ui.invalid"
	if p.special.has(id):
		return "sc.block.active"
	if int(p.age) < int(c.def.get("min_age", 14)):
		return "job.block.age"
	if _sim.crime.in_prison(p):
		return "job.block.prison"
	if float(p.finance.cash) < float(c.def.get("start_cost", 0)):
		return "ui.no_money"
	if not _sim.cond.check_all(c.def.get("conditions", []), {}):
		return c.def.get("lock_key", "job.block.locked")
	return ""


func start(p: Dictionary, id: String) -> Dictionary:
	var reason := block_reason(p, id)
	if reason != "":
		return {"ok": false, "reason": reason}
	var c := career(id)
	var cost := float(c.def.get("start_cost", 0))
	if cost > 0.0:
		_sim.finance.add_cash(p, -cost)
	p.special[id] = c.start_state(p)
	p.special[id].years = 0
	_sim.add_log("log.sc_start", {"career": "@sc." + id}, "major")
	_sim.activities.bump_counter("sc.start." + id)
	return {"ok": true, "key": "sc.started", "params": {"career": "@sc." + id}}


func quit(p: Dictionary, id: String) -> Dictionary:
	if not p.special.has(id):
		return {"ok": false, "reason": "ui.invalid"}
	p.special.erase(id)
	_sim.add_log("log.sc_quit", {"career": "@sc." + id}, "info")
	return {"ok": true, "key": "sc.quit", "params": {"career": "@sc." + id}}


func actions(p: Dictionary, id: String) -> Array:
	var c := career(id)
	if c == null or not p.special.has(id):
		return []
	var out: Array = []
	for a in c.actions(p, p.special[id]):
		if a.locked == "" and _sim.activities.free_slots(p) < int(a.time):
			a.locked = "ui.no_time"
		if a.locked == "" and float(p.finance.cash) < float(a.cost):
			a.locked = "ui.no_money"
		if a.locked == "" and _sim.crime.in_prison(p):
			a.locked = "job.block.prison"
		out.append(a)
	return out


func perform(p: Dictionary, id: String, action_id: String) -> Dictionary:
	var target: Dictionary = {}
	for a in actions(p, id):
		if a.id == action_id:
			target = a
	if target.is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	if target.locked != "":
		return {"ok": false, "reason": target.locked}
	_sim.activities.spend_time(int(target.time))
	if float(target.cost) > 0.0:
		_sim.finance.add_cash(p, -float(target.cost))
	var ctx := {"gains": {}}
	var result: Dictionary = career(id).perform(p, p.special[id], action_id, ctx)
	_sim.activities.bump_counter("sc.%s.%s" % [id, action_id])
	_sim.titles_check()
	result.gains = ctx.gains
	return result


func process_year(p: Dictionary) -> void:
	for id in active(p):
		var st: Dictionary = p.special[id]
		st.years = int(st.get("years", 0)) + 1
		career(id).tick(p, st)
		if career(id).is_finished(p, st):
			p.special.erase(id)
			_sim.add_log("log.sc_end", {"career": "@sc." + id}, "major")
