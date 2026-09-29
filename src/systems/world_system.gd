class_name WorldSystem
extends RefCounted
## Global simulated world: economic cycle, inflation, unemployment, housing,
## markets and the hidden "rift" activity of the Awakened world. It is not a
## full economic model, but every value here feeds another system.

var _sim


func _init(sim) -> void:
	_sim = sim


func init_world() -> void:
	var markets := {}
	for asset in _sim.data.bal("markets.assets", []):
		markets[asset.id] = {"price": float(asset.price), "last": float(asset.price)}
	_sim.state.data.world = {
		"cycle_phase": _sim.rng.randf_range(0.0, TAU),
		"economy": 0.0,
		"inflation": 0.03,
		"price_index": 1.0,
		"unemployment": 0.08,
		"housing": 1.0,
		"rift": 0.3,
		"markets": markets,
		"events": {},
		"history": [],
	}


func w() -> Dictionary:
	return _sim.state.data.world


## Year tick. Sine-driven business cycle + noise + active world events.
func process_year() -> void:
	var world := w()
	var period: float = _sim.data.bal("world.cycle_years", 9.0)
	world.cycle_phase = fmod(float(world.cycle_phase) + TAU / period, TAU)
	var econ: float = sin(float(world.cycle_phase)) * 0.6 + _sim.rng.randn(0, 0.2) + active_value("economy")
	world.economy = clampf(econ, -1.0, 1.0)
	world.inflation = clampf(0.03 + float(world.economy) * 0.02 + _sim.rng.randn(0, 0.01) + active_value("inflation"), -0.01, 0.2)
	world.price_index = float(world.price_index) * (1.0 + float(world.inflation))
	world.unemployment = clampf(0.08 - float(world.economy) * 0.05 + active_value("unemployment"), 0.02, 0.3)
	world.housing = maxf(0.3, float(world.housing) * (1.0 + float(world.inflation) + float(world.economy) * 0.04 + _sim.rng.randn(0, 0.03) + active_value("housing")))
	world.rift = clampf(float(world.rift) + _sim.rng.randn(0, 0.05) + active_value("rift"), 0.05, 1.0)
	_update_markets()
	_tick_events()
	_maybe_start_event()


func _update_markets() -> void:
	for asset in _sim.data.bal("markets.assets", []):
		var m: Dictionary = w().markets.get(asset.id, {"price": float(asset.price)})
		m.last = m.price
		var drift := float(asset.get("trend", 0.04)) + float(w().economy) * float(asset.get("beta", 0.5))
		if asset.has("rift_beta"):
			drift += (float(w().rift) - 0.3) * float(asset.rift_beta)
		var shock: float = _sim.rng.randn(0, float(asset.get("vol", 0.1)))
		m.price = maxf(0.01, float(m.price) * (1.0 + drift + shock + active_value("market." + asset.id)))
		w().markets[asset.id] = m


func _tick_events() -> void:
	var ended: Array = []
	for id in w().events:
		w().events[id] = int(w().events[id]) - 1
		if int(w().events[id]) <= 0:
			ended.append(id)
	for id in ended:
		w().events.erase(id)
		_sim.add_log("log.world_event_end", {"event": "@wevent." + id + ".title"}, "world")
	if not ended.is_empty():
		_sim.gamer.invalidate()


func _maybe_start_event() -> void:
	if not _sim.prob.roll_neutral(_sim.data.bal("world.event_chance", 0.18)):
		return
	var ids: Array = []
	var weights: Array = []
	for id in _sim.data.table("world_events"):
		if w().events.has(id):
			continue
		var def: Dictionary = _sim.data.table("world_events")[id]
		if _sim.cond.check_all(def.get("conditions", []), {}):
			ids.append(id)
			weights.append(float(def.get("weight", 1)))
	ids.sort()
	var chosen = _sim.rng.pick_weighted(ids, weights)
	if chosen != null:
		start_event(chosen)


func start_event(id: String) -> void:
	var def: Dictionary = _sim.data.get_def("world_events", id)
	if def.is_empty():
		return
	w().events[id] = _sim.rng.randi_range(int(def.get("min_years", 1)), int(def.get("max_years", 3)))
	w().history.append({"id": id, "year": _sim.state.data.world_year})
	_sim.effects.run_all(def.get("on_start", []), {})
	_sim.add_log("log.world_event", {"event": "@wevent." + id + ".title"}, "world")
	_sim.notify("world", "wevent." + id + ".title", {})
	_sim.gamer.invalidate()


## Sum of a numeric "delta" field across active world events.
func active_value(key: String) -> float:
	var total := 0.0
	for id in w().get("events", {}):
		total += float(_sim.data.get_def("world_events", id).get("delta", {}).get(key, 0.0))
	return total


func active_mods() -> Dictionary:
	var out := {}
	for id in w().get("events", {}):
		var mods: Dictionary = _sim.data.get_def("world_events", id).get("mods", {})
		for k in mods:
			out[k] = float(out.get(k, 0.0)) + float(mods[k])
	return out


func price(asset_id: String) -> float:
	return float(w().markets.get(asset_id, {}).get("price", 0.0))


## Loot tagged "mana" follows the mana-core market: dungeon economy is part of
## the real economy.
func item_price_mult(item_def: Dictionary) -> float:
	var market: String = item_def.get("market", "")
	if market == "":
		return 1.0
	var base := 0.0
	for asset in _sim.data.bal("markets.assets", []):
		if asset.id == market:
			base = float(asset.price)
	return price(market) / base if base > 0.0 else 1.0


func salary_mult() -> float:
	return 1.0 + float(w().economy) * float(_sim.data.bal("world.salary_econ_sensitivity", 0.08))
