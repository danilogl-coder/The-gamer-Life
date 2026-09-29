class_name GamerSystem
extends RefCounted
## "The System": level, EXP, stats, stat points, HP/MP, titles, inventory,
## equipment and the global MODIFIER pool. Every other system asks this one
## for modifiers (mod("study_gain"), mod("salary")...) which is what welds the
## Gamer layer onto ordinary life: a skill learned in a dungeon can raise your
## grades, a title earned at work can make you a better fighter.

const STAT_IDS := CharacterFactory.STAT_IDS

var _sim
var _mod_cache: Dictionary = {}
var _cache_valid := false


func _init(sim) -> void:
	_sim = sim


func invalidate() -> void:
	_cache_valid = false


func on_player_created() -> void:
	var p: Dictionary = _sim.player()
	for skill_id in _sim.data.bal("gamer.starting_skills", []):
		_sim.skills.learn(p, skill_id, true)
	refill(p)


# ---------------------------------------------------------------------------
# Modifiers
# ---------------------------------------------------------------------------

func mod(key: String) -> float:
	if not _cache_valid:
		_rebuild_mods()
	return float(_mod_cache.get(key, 0.0))


func all_mods() -> Dictionary:
	if not _cache_valid:
		_rebuild_mods()
	return _mod_cache


func _rebuild_mods() -> void:
	_mod_cache = {}
	_cache_valid = true
	var p: Dictionary = _sim.player()
	if p.is_empty():
		return
	for sid in p.gamer.get("skills", {}):
		var def: Dictionary = _sim.data.get_def("skills", sid)
		var lv := float(p.gamer.skills[sid].lv)
		_add_mods(def.get("mods", {}), lv)
		_add_mods(def.get("mods_flat", {}), 1.0)
	for tid in p.gamer.get("titles", []):
		var tdef: Dictionary = _sim.data.get_def("titles", tid)
		if tdef.get("passive", false) or tid == p.gamer.get("title", ""):
			_add_mods(tdef.get("mods", {}), 1.0)
	for slot in p.gamer.get("equipment", {}):
		_add_mods(_sim.data.get_def("items", p.gamer.equipment[slot]).get("mods", {}), 1.0)
	for t in p.get("traits", []):
		_add_mods(_sim.data.get_def("traits", t).get("mods", {}), 1.0)
	for c in p.health.get("conditions", {}):
		_add_mods(_sim.data.get_def("diseases", c).get("mods", {}), 1.0)
	for perk in _sim.state.data.legacy.get("perks", []):
		_add_mods(_sim.data.get_def("items", perk).get("mods", {}), 1.0)
	_add_mods(_sim.world.active_mods(), 1.0)
	_add_mods(_sim.pets.mods(p), 1.0)
	_add_mods(_sim.school_life.mods(p), 1.0)
	for item_id in p.gamer.get("inventory", {}):
		var idef: Dictionary = _sim.data.get_def("items", item_id)
		if idef.get("cat", "") == "heirloom":
			_add_mods(idef.get("mods", {}), 1.0)
	for item in p.finance.get("possessions", []):
		_add_mods(_sim.data.get_def("possessions", item.id).get("mods", {}), 1.0)
	var rank := int(p.gamer.get("rank", 0))
	var ranks: Array = _sim.data.bal("gamer.ranks", [])
	if rank < ranks.size():
		_add_mods(ranks[rank].get("mods", {}), 1.0)


func _add_mods(mods: Dictionary, scale: float) -> void:
	for k in mods:
		_mod_cache[k] = float(_mod_cache.get(k, 0.0)) + float(mods[k]) * scale


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

## Unbounded effective stat: (base + flat) * (1 + pct). NPCs use base only.
func effective_stat(ch: Dictionary, stat: String) -> float:
	if ch.is_empty():
		return 0.0
	var base := float(ch.gamer.stats.get(stat, 0.0))
	if not ch.get("is_player", false):
		return base
	var flat := mod("stat." + stat)
	var pct := mod("statpct." + stat) + mod("statpct.all")
	return maxf(0.0, (base + flat) * (1.0 + pct))


func allocate(stat: String, amount: int) -> bool:
	var p: Dictionary = _sim.player()
	if not STAT_IDS.has(stat) or int(p.gamer.stat_points) < amount or amount <= 0:
		return false
	p.gamer.stat_points = int(p.gamer.stat_points) - amount
	p.gamer.stats[stat] = float(p.gamer.stats[stat]) + amount
	invalidate()
	_sim.titles_check()
	return true


## Spreads unspent points following the player's current build proportions.
func auto_allocate(p: Dictionary) -> bool:
	var pts := int(p.gamer.stat_points)
	if pts <= 0:
		return false
	var weights: Array = []
	for s in STAT_IDS:
		weights.append(float(p.gamer.stats[s]))
	for i in pts:
		var s: String = _sim.rng.pick_weighted(STAT_IDS, weights)
		p.gamer.stats[s] = float(p.gamer.stats[s]) + 1.0
	p.gamer.stat_points = 0
	invalidate()
	return true


func add_stat_xp(p: Dictionary, stat: String, amount: float) -> void:
	if not STAT_IDS.has(stat):
		return
	amount *= 1.0 + mod("train_gain") + mod("train_gain." + stat)
	var xp := float(p.gamer.stat_xp.get(stat, 0.0)) + amount
	var base_need: float = _sim.data.bal("gamer.stat_xp_base", 40.0)
	var growth: float = _sim.data.bal("gamer.stat_xp_growth", 0.06)
	var guard := 0
	while guard < 50:
		guard += 1
		var need := base_need * (1.0 + float(p.gamer.stats[stat]) * growth)
		if xp < need:
			break
		xp -= need
		p.gamer.stats[stat] = float(p.gamer.stats[stat]) + 1.0
		_sim.notify("stat", "sys.stat_up", {"stat": "@stat." + stat, "value": int(p.gamer.stats[stat])})
		invalidate()
	p.gamer.stat_xp[stat] = xp


# ---------------------------------------------------------------------------
# Level / EXP
# ---------------------------------------------------------------------------

func exp_to_next(level: int) -> float:
	return floorf(float(_sim.data.bal("gamer.exp_base", 100.0)) * pow(level, float(_sim.data.bal("gamer.exp_exponent", 1.55))))


## Returns the EXP actually gained after modifiers.
func add_exp(p: Dictionary, amount: float) -> int:
	if amount <= 0.0:
		return 0
	amount *= maxf(0.0, 1.0 + mod("exp_gain"))
	p.gamer.exp = float(p.gamer.exp) + amount
	var levels := 0
	while float(p.gamer.exp) >= exp_to_next(int(p.gamer.level)):
		p.gamer.exp = float(p.gamer.exp) - exp_to_next(int(p.gamer.level))
		p.gamer.level = int(p.gamer.level) + 1
		p.gamer.stat_points = int(p.gamer.stat_points) + int(_sim.data.bal("gamer.points_per_level", 5))
		levels += 1
	if levels > 0:
		refill(p)
		_sim.notify("level", "sys.level_up", {"level": p.gamer.level, "points": levels * int(_sim.data.bal("gamer.points_per_level", 5))})
		_sim.bus.level_up.emit(int(p.gamer.level))
		_check_rank_up(p)
	return int(amount)


func _check_rank_up(p: Dictionary) -> void:
	var ranks: Array = _sim.data.bal("gamer.ranks", [])
	var rank := int(p.gamer.get("rank", 0))
	if rank + 1 < ranks.size() and int(p.gamer.level) >= int(ranks[rank + 1].level):
		_sim.events.queue_special(ranks[rank + 1].get("event", "sys_evolution"))


# ---------------------------------------------------------------------------
# HP / MP (the Gamer's Body: sleeping fully restores)
# ---------------------------------------------------------------------------

func max_hp(p: Dictionary) -> float:
	return (float(_sim.data.bal("gamer.hp_base", 100)) + effective_stat(p, "vit") * float(_sim.data.bal("gamer.hp_per_vit", 12))
		+ float(p.gamer.level) * float(_sim.data.bal("gamer.hp_per_level", 8))) * (1.0 + mod("max_hp"))


func max_mp(p: Dictionary) -> float:
	return (float(_sim.data.bal("gamer.mp_base", 40)) + effective_stat(p, "int") * float(_sim.data.bal("gamer.mp_per_int", 8))
		+ effective_stat(p, "wis") * float(_sim.data.bal("gamer.mp_per_wis", 4))) * (1.0 + mod("max_mp"))


func refill(p: Dictionary) -> void:
	p.gamer.hp = max_hp(p)
	p.gamer.mp = max_mp(p)


func heal(p: Dictionary, hp: float, mp: float = 0.0) -> void:
	p.gamer.hp = minf(max_hp(p), float(p.gamer.hp) + hp)
	p.gamer.mp = minf(max_mp(p), float(p.gamer.mp) + mp)


## Year tick: the body rests, hidden gifts may surface, titles are checked.
func process_year(p: Dictionary) -> void:
	refill(p)
	# The System rewards simply living: generous in childhood, modest later.
	var yearly: float = _sim.data.bal("gamer.yearly_exp_child", 70) if int(p.age) < 18 else _sim.data.bal("gamer.yearly_exp_adult", 30)
	add_exp(p, yearly * (1.0 + float(p.gamer.level) * 0.08))
	# Natural growth while young: bodies and minds grow even without the System.
	if int(p.age) <= 18:
		for s in STAT_IDS:
			add_stat_xp(p, s, float(_sim.data.bal("gamer.natural_growth_xp", 14)) * _sim.rng.randf_range(0.5, 1.5))
	elif int(p.age) >= int(_sim.data.bal("gamer.decline_age", 55)):
		var loss := float(_sim.data.bal("gamer.decline_per_year", 0.4)) * (1.0 - clampf(mod("aging_resist"), 0.0, 1.0))
		for s in ["str", "dex", "vit"]:
			p.gamer.stats[s] = maxf(1.0, float(p.gamer.stats[s]) - loss)
	invalidate()


# ---------------------------------------------------------------------------
# Titles
# ---------------------------------------------------------------------------

func check_titles(p: Dictionary) -> void:
	for tid in _sim.data.table("titles"):
		if p.gamer.titles.has(tid):
			continue
		var def: Dictionary = _sim.data.table("titles")[tid]
		if def.has("conditions") and _sim.cond.check_all(def.conditions, {}):
			grant_title(p, tid)


func grant_title(p: Dictionary, tid: String) -> void:
	if p.gamer.titles.has(tid) or _sim.data.get_def("titles", tid).is_empty():
		return
	p.gamer.titles.append(tid)
	if p.gamer.title == "":
		p.gamer.title = tid
	invalidate()
	_sim.notify("title", "sys.title", {"title": "@title." + tid})
	_sim.add_log("log.title", {"title": "@title." + tid}, "system")
	_sim.bus.title_earned.emit(tid)


func equip_title(p: Dictionary, tid: String) -> void:
	if p.gamer.titles.has(tid):
		p.gamer.title = tid
		invalidate()


# ---------------------------------------------------------------------------
# Inventory & equipment
# ---------------------------------------------------------------------------

func add_item(p: Dictionary, item_id: String, qty: int = 1) -> void:
	if _sim.data.get_def("items", item_id).is_empty():
		push_warning("Unknown item " + item_id)
		return
	p.gamer.inventory[item_id] = int(p.gamer.inventory.get(item_id, 0)) + qty


func remove_item(p: Dictionary, item_id: String, qty: int = 1) -> bool:
	var have := int(p.gamer.inventory.get(item_id, 0))
	if have < qty:
		return false
	if have == qty:
		p.gamer.inventory.erase(item_id)
	else:
		p.gamer.inventory[item_id] = have - qty
	return true


## Uses/equips an item. Consumables run their data effects.
func use_item(p: Dictionary, item_id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("items", item_id)
	if def.is_empty() or int(p.gamer.inventory.get(item_id, 0)) <= 0:
		return {"ok": false, "reason": "ui.no_item"}
	var ctx := {}
	if def.has("slot"):
		var old: String = p.gamer.equipment.get(def.slot, "")
		if old != "":
			add_item(p, old)
		remove_item(p, item_id)
		p.gamer.equipment[def.slot] = item_id
		invalidate()
		return {"ok": true, "key": "ui.equip_done", "params": {"item": "@item." + item_id}}
	if not def.has("use"):
		return {"ok": false, "reason": "ui.cannot_use"}
	remove_item(p, item_id)
	_sim.effects.run_all(def.use, ctx)
	_sim.activities.bump_counter("use." + item_id)
	invalidate()
	return {"ok": true, "key": "item." + item_id + ".used", "params": {}, "gains": ctx.get("gains", {})}


func unequip(p: Dictionary, slot: String) -> void:
	var item: String = p.gamer.equipment.get(slot, "")
	if item != "":
		p.gamer.equipment.erase(slot)
		add_item(p, item)
		invalidate()


func sell_item(p: Dictionary, item_id: String, qty: int = 1) -> float:
	var def: Dictionary = _sim.data.get_def("items", item_id)
	if not remove_item(p, item_id, qty):
		return 0.0
	var price: float = float(def.get("value", 0)) * qty * _sim.world.item_price_mult(def)
	_sim.finance.add_cash(p, price)
	return price


# ---------------------------------------------------------------------------
# Hidden attributes (revealed by the Observe skill / life events)
# ---------------------------------------------------------------------------

func discover_hidden(p: Dictionary, hidden_id: String = "") -> String:
	var candidates: Array = []
	for h in p.hidden:
		if not p.discovered.has(h):
			candidates.append(h)
	if candidates.is_empty():
		return ""
	if hidden_id == "" or not candidates.has(hidden_id):
		candidates.sort()
		hidden_id = _sim.rng.pick(candidates)
	p.discovered.append(hidden_id)
	_sim.notify("system", "sys.hidden_found", {"attr": "@hidden." + hidden_id, "value": int(p.hidden[hidden_id])})
	return hidden_id
