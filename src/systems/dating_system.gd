class_name DatingSystem
extends RefCounted
## Dating app: each swipe session (1 time unit) shows 3 generated profiles
## with visible looks/age/job/traits and a compatibility hint. The match is
## decided by the other person's preferences, not by a single bar.

var _sim


func _init(sim) -> void:
	_sim = sim


func pool() -> Array:
	return _sim.state.data.get("dating_pool", [])


func candidates(spend_time: bool = true) -> Array:
	var p: Dictionary = _sim.player()
	if int(p.age) < 18 or _sim.crime.in_prison(p):
		return []
	if spend_time and not _sim.activities.spend_time(1):
		return []
	var ids: Array = []
	for i in 3:
		var npc: Dictionary = _sim.factory.spawn_contextual("acquaintance", {"age_rel": 0, "age_spread": 7, "sex": "pref"})
		npc.origin_role = "dating_app"
		ids.append(npc.id)
	_sim.state.data.dating_pool = ids
	_sim.activities.bump_counter("love.dating_app")
	return ids


func pick(npc_id: String) -> Dictionary:
	if not pool().has(npc_id):
		return {"ok": false, "reason": "ui.invalid"}
	var p: Dictionary = _sim.player()
	var npc: Dictionary = _sim.state.npc(npc_id)
	var spec := {"base": 0.2, "mods": [
		{"path": "calc.compat", "per": 0.01, "offset": 40.0},
		{"path": "player.attrs.looks", "per": 0.005, "offset": float(npc.attrs.looks)},
		{"path": "mod.charm", "per": 1.0}]}
	# Materialistic matches care about money; ambitious ones about careers.
	if npc.traits.has("materialistic"):
		spec.mods.append({"path": "calc.net_worth", "per": 0.000002, "max": 0.2})
	if npc.traits.has("ambitious") and p.career.job == "":
		spec.base = float(spec.base) - 0.15
	_sim.state.data.dating_pool = []
	if _sim.prob.roll_spec(spec, {"actor": npc}):
		_sim.relations.ensure(npc_id, "partner", 60)
		_sim.add_log("log.dating_app_match", {"name": npc.first_name}, "major")
		return {"ok": true, "key": "love.match", "params": {"name": npc.first_name}}
	return {"ok": false, "reason": "love.no_match"}


## Dismissed profiles are pruned at year end (not bonded).
func clear() -> void:
	_sim.state.data.dating_pool = []
