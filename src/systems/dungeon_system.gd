class_name DungeonSystem
extends RefCounted
## Instant Dungeons: isolated pocket worlds created with MP where monsters can
## be hunted for EXP, gold, mana cores, skill books and gear. Combat is an
## automatic, deterministic (seeded) simulation that reads the Gamer stats,
## equipment, active skills and modifiers. Defeat is real: without an escape
## skill you can be crippled — or die.

const MAX_ROUNDS := 60

var _sim


func _init(sim) -> void:
	_sim = sim


func available(p: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = _sim.data.table("dungeons").keys()
	ids.sort_custom(func(a, b): return int(_sim.data.get_def("dungeons", a).min_level) < int(_sim.data.get_def("dungeons", b).min_level))
	for id in ids:
		var def: Dictionary = _sim.data.get_def("dungeons", id)
		if _sim.cond.check_all(def.get("conditions", []), {}):
			out.append({"id": id, "danger": danger(p, def)})
	return out


## 0 = trivial .. 3 = deadly, based on level difference.
func danger(p: Dictionary, def: Dictionary) -> int:
	var gap := int(def.get("min_level", 1)) - int(p.gamer.level)
	if gap <= -10: return 0
	if gap <= 0: return 1
	if gap <= 8: return 2
	return 3


func player_attack(p: Dictionary) -> float:
	return (_sim.gamer.effective_stat(p, "str") * 2.2 + float(p.gamer.level) * 2.0 + _sim.gamer.mod("atk") + _sim.pets.combat_bonus(p)) * (1.0 + _sim.gamer.mod("dmg"))


func player_defense(p: Dictionary) -> float:
	return _sim.gamer.effective_stat(p, "vit") * 1.2 + _sim.gamer.mod("def")


func run(dungeon_id: String, ctx: Dictionary) -> Dictionary:
	var p: Dictionary = _sim.player()
	var def: Dictionary = _sim.data.get_def("dungeons", dungeon_id)
	if def.is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	var lines: Array = [{"key": "dng.enter", "params": {"dungeon": "@dng." + dungeon_id}}]
	var roster: Array = []
	for i in int(def.get("waves", 3)):
		roster.append(_sim.rng.pick(def.monsters))
	if def.has("boss"):
		roster.append(def.boss)
	var totals := {"exp": 0.0, "gold": 0.0, "kills": 0}
	var outcome := "clear"
	var escaped_flag := false
	for mid in roster:
		var res := _fight(p, mid, def, lines, totals, ctx)
		if res == "dead":
			outcome = "defeat"
			break
		if res == "fled":
			outcome = "escaped"
			escaped_flag = true
			break
	var exp_gain: int = _sim.gamer.add_exp(p, totals.exp)
	_sim.pets.share_exp(p, totals.exp)
	ctx.gains["exp"] = int(ctx.gains.get("exp", 0)) + exp_gain
	var gold := float(totals.gold) * float(_sim.finance.country(p).get("salary_mult", 1.0))
	_sim.finance.add_cash(p, gold)
	ctx.gains["money"] = float(ctx.gains.get("money", 0)) + gold
	_sim.gamer.add_stat_xp(p, "str", 6.0 * totals.kills)
	_sim.gamer.add_stat_xp(p, "dex", 4.0 * totals.kills)
	_sim.gamer.add_stat_xp(p, "vit", 3.0 * totals.kills)
	_sim.activities.bump_counter("dungeon.runs")
	if outcome == "clear":
		_sim.activities.bump_counter("dungeon.clears")
		_sim.activities.bump_counter("dungeon.clear." + dungeon_id)
		_sim.effects.run_all(def.get("on_clear", []), ctx)
	elif outcome == "defeat":
		_defeat(p, def, lines)
	if escaped_flag:
		_sim.activities.bump_counter("dungeon.escapes")
	# The secret of the dungeons can leak: witnesses, rumours, the guilds notice.
	if totals.kills > 0 and not _sim.state.flag("guild_noticed", false) and _sim.prob.roll_neutral(0.05 + float(p.gamer.level) * 0.004):
		_sim.events.queue_event("guild_noticed")
	lines.append({"key": "dng.summary", "params": {"kills": totals.kills, "exp": exp_gain, "gold": int(gold)}})
	return {"ok": true, "key": "dng." + outcome, "params": {"dungeon": "@dng." + dungeon_id}, "log": lines}


func _fight(p: Dictionary, mid: String, dungeon: Dictionary, lines: Array, totals: Dictionary, ctx: Dictionary) -> String:
	var m: Dictionary = _sim.data.get_def("monsters", mid)
	var scale := float(dungeon.get("scale", 1.0))
	var m_hp := float(m.hp) * scale
	var m_atk := float(m.atk) * scale
	var m_def := float(m.get("def", 0)) * scale
	var crit := clampf(_sim.gamer.effective_stat(p, "dex") * 0.004 + _sim.gamer.effective_stat(p, "luk") * 0.002 + _sim.gamer.mod("crit"), 0.0, 0.6)
	var dodge := clampf(_sim.gamer.effective_stat(p, "dex") * 0.003 + _sim.gamer.mod("dodge"), 0.0, 0.45)
	var reduction := clampf(_sim.gamer.mod("dmg_reduction"), 0.0, 0.8)
	var skills: Array = _sim.skills.combat_skills(p)
	var used_skill := ""
	for round_i in MAX_ROUNDS:
		# Player turn: strongest affordable skill, else a physical hit.
		var dmg := player_attack(p)
		used_skill = ""
		for sid in skills:
			var cost := float(_sim.data.get_def("skills", sid).combat.get("mp", 10))
			if float(p.gamer.mp) >= cost:
				p.gamer.mp = float(p.gamer.mp) - cost
				dmg = _sim.skills.skill_power(p, sid)
				used_skill = sid
				_sim.skills.add_xp(p, sid, 2.0)
				break
		dmg *= _sim.rng.randf_range(0.85, 1.15)
		if _sim.rng.randf() < crit:
			dmg *= 1.8 + _sim.gamer.mod("crit_dmg")
		m_hp -= maxf(1.0, dmg - m_def * 0.5)
		if m_hp <= 0.0:
			_on_kill(p, mid, m, dungeon, lines, totals, used_skill, ctx)
			return "win"
		# Monster turn.
		if _sim.rng.randf() >= dodge:
			var taken := maxf(1.0, m_atk * _sim.rng.randf_range(0.8, 1.2) - player_defense(p) * 0.5) * (1.0 - reduction)
			p.gamer.hp = float(p.gamer.hp) - taken
		if float(p.gamer.hp) <= 0.0:
			lines.append({"key": "dng.fell", "params": {"monster": "@mon." + mid}})
			return "dead"
		# Without the escape skill you can still try to crawl out (DEX + luck).
		if float(p.gamer.hp) < _sim.gamer.max_hp(p) * 0.12 and not _sim.skills.knows(p, "id_escape"):
			if _sim.prob.roll_spec({"base": float(_sim.data.bal("dungeon.desperate_escape", 0.4)), "mods": [{"path": "stat.dex", "per": 0.004, "max": 0.3}]}):
				lines.append({"key": "dng.crawled", "params": {"monster": "@mon." + mid}})
				return "fled"
		if float(p.gamer.hp) < _sim.gamer.max_hp(p) * 0.2 and _sim.skills.knows(p, "id_escape"):
			lines.append({"key": "dng.fled", "params": {"monster": "@mon." + mid}})
			_sim.skills.add_xp(p, "id_escape", 5.0)
			return "fled"
	lines.append({"key": "dng.stalemate", "params": {"monster": "@mon." + mid}})
	return "fled"


func _on_kill(p: Dictionary, mid: String, m: Dictionary, dungeon: Dictionary, lines: Array, totals: Dictionary, used_skill: String, ctx: Dictionary) -> void:
	totals.kills = int(totals.kills) + 1
	totals.exp = float(totals.exp) + float(m.exp) * float(dungeon.get("exp_mult", 1.0))
	totals.gold = float(totals.gold) + float(m.get("gold", 0)) * _sim.rng.randf_range(0.7, 1.3) * float(dungeon.get("gold_mult", 1.0)) * (1.0 + _sim.gamer.mod("gold_find"))
	var key := "dng.kill_skill" if used_skill != "" else "dng.kill"
	lines.append({"key": key, "params": {"monster": "@mon." + mid, "skill": "@skill." + used_skill}})
	_sim.activities.bump_counter("kill.total")
	_sim.activities.bump_counter("kill." + mid)
	for drop in m.get("drops", []):
		var chance: float = float(drop.chance) * (1.0 + _sim.gamer.mod("drop_rate")) * _sim.prob.apply_luck(1.0)
		if _sim.rng.randf() < chance:
			_sim.gamer.add_item(p, drop.item, 1)
			ctx.gains["item:" + drop.item] = int(ctx.gains.get("item:" + drop.item, 0)) + 1
			lines.append({"key": "dng.drop", "params": {"item": "@item." + drop.item}})
	var tamed: String = _sim.pets.try_tame(p, mid)
	if tamed != "":
		lines.append({"key": "dng.tamed", "params": {"monster": "@mon." + mid, "name": tamed}})
	# Re:Monster-style predation: devour what you defeat, steal its power.
	if m.has("absorb") and _sim.skills.knows(p, "devour") and not _sim.skills.knows(p, m.absorb):
		var chance: float = 0.04 + _sim.skills.level(p, "devour") * 0.02
		if _sim.rng.randf() < chance:
			_sim.skills.learn(p, m.absorb)
			lines.append({"key": "dng.absorbed", "params": {"skill": "@skill." + m.absorb, "monster": "@mon." + mid}})
		_sim.skills.add_xp(p, "devour", 3.0)


func _defeat(p: Dictionary, dungeon: Dictionary, lines: Array) -> void:
	_sim.activities.bump_counter("dungeon.defeats")
	var death: float = float(_sim.data.bal("dungeon.death_chance", 0.3)) * (1.0 - _sim.prob.luck_bonus())
	if _sim.prob.roll_neutral(death) and _sim.gamer.mod("death_save") <= 0.0:
		lines.append({"key": "dng.died", "params": {}})
		_sim.health.kill(p, "cause.dungeon")
		return
	p.gamer.hp = 1.0
	_sim.health.injure(p, "injury_severe")
	_sim.state.set_flag("survived_death")
	lines.append({"key": "dng.expelled", "params": {}})
