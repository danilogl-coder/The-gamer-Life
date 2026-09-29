class_name SpecialCareer
extends RefCounted
## Base class for "careers that play like small games" (music, sports,
## business, influencer...). A new special career is a new script + one row
## in data/special_careers.json — the core never changes.
##
## Each career keeps its own state dictionary inside player.special[id].
## Helpers below give careers the same currency as the rest of the game:
## chance specs (ProbabilityService), EXP, stats, money, fame, counters.

var sim
var id: String
var def: Dictionary


func setup(p_sim, p_def: Dictionary) -> SpecialCareer:
	sim = p_sim
	def = p_def
	id = p_def.id
	return self


## Initial state when the player starts this career.
func start_state(_p: Dictionary) -> Dictionary:
	return {}


## [{id, time, cost, locked: reason_key or ""}]
func actions(_p: Dictionary, _st: Dictionary) -> Array:
	return []


## Returns a result dict like other actions ({ok, key, params, gains}).
func perform(_p: Dictionary, _st: Dictionary, _action: String, _ctx: Dictionary) -> Dictionary:
	return {"ok": false, "reason": "ui.invalid"}


## Yearly simulation.
func tick(_p: Dictionary, _st: Dictionary) -> void:
	pass


## [[label_key, value_string]] for the UI card.
func summary(_p: Dictionary, _st: Dictionary) -> Array:
	return []


## Money this career adds to the yearly income report (already applied in tick).
func is_finished(_p: Dictionary, _st: Dictionary) -> bool:
	return false


# ------------------------------------------------------------------ helpers

func act(action_id: String, time: int = 1, cost: float = 0.0, locked: String = "") -> Dictionary:
	return {"id": action_id, "time": time, "cost": cost, "locked": locked}


func chance(spec: Dictionary) -> bool:
	return sim.prob.roll_spec(spec)


func stat(p: Dictionary, s: String) -> float:
	return sim.gamer.effective_stat(p, s)


func give_money(p: Dictionary, amount: float, ctx: Dictionary) -> void:
	sim.finance.add_cash(p, amount)
	ctx.gains["money"] = float(ctx.gains.get("money", 0)) + amount


func give_exp(p: Dictionary, amount: float, ctx: Dictionary) -> void:
	ctx.gains["exp"] = int(ctx.gains.get("exp", 0)) + sim.gamer.add_exp(p, amount)


func fame(p: Dictionary, amount: float) -> void:
	p.fame = clampf(float(p.get("fame", 0)) + amount, 0.0, 100.0)


func counter(key: String, amount: int = 1) -> void:
	sim.activities.bump_counter(key, amount)


func log_major(key: String, params: Dictionary = {}) -> void:
	sim.add_log(key, params, "major")


## Logistic growth towards the world's audience cap: gains shrink as you
## approach it, so even overpowered stats can't exceed the planet.
const AUDIENCE_CAP := 3.0e9


func grow_audience(current: float, gain: float) -> float:
	return clampf(current + gain * maxf(0.0, 1.0 - current / AUDIENCE_CAP), 0.0, AUDIENCE_CAP)


func res(key: String, params: Dictionary = {}, ok: bool = true) -> Dictionary:
	return {"ok": true, "success": ok, "key": key, "params": params}
