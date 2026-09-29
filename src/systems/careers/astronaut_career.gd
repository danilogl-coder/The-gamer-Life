extends SpecialCareer
## Astronaut: STEM degree → space academy → selection → missions (orbit,
## station, moon, the orbital rift). High risk, high glory.

const STAGES := ["academy", "candidate", "astronaut", "commander"]
const MISSIONS := {"orbit": [0.01, 150.0, 3.0], "station": [0.02, 300.0, 5.0], "moon": [0.05, 800.0, 12.0], "rift": [0.08, 2500.0, 20.0]}


func start_state(_p: Dictionary) -> Dictionary:
	return {"stage": 0, "training": 0.0, "missions": 0}


func actions(_p: Dictionary, st: Dictionary) -> Array:
	var stage = int(st.stage)
	var out = [act("train"), act("research")]
	out.append(act("selection", 0, 0.0, "" if stage < 2 and float(st.training) >= 60.0 * (stage + 1) else "sc.ast.need_training"))
	for m in MISSIONS:
		var lock = "" if stage >= 2 else "sc.ast.need_rank"
		if m == "rift" and not sim.state.flag("world_revealed", false):
			continue
		if m in ["moon", "rift"] and stage < 3:
			lock = "sc.ast.need_rank"
		out.append(act("mission_" + m, 2, 0.0, lock))
	return out


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	if action == "train":
		st.training = float(st.training) + 10.0 + stat(p, "vit") * 0.3 + stat(p, "int") * 0.3
		sim.gamer.add_stat_xp(p, "vit", 15.0)
		sim.gamer.add_stat_xp(p, "int", 10.0)
		give_exp(p, 25.0, ctx)
		return res("sc.ast.trained", {"t": int(st.training)})
	if action == "research":
		sim.gamer.add_stat_xp(p, "int", 20.0)
		st.training = float(st.training) + 5.0
		give_exp(p, 30.0, ctx)
		return res("sc.ast.research")
	if action == "selection":
		if chance({"base": 0.35, "mods": [{"path": "stat.int", "per": 0.006, "offset": 20.0, "max": 0.3}, {"path": "stat.vit", "per": 0.006, "offset": 20.0, "max": 0.3}]}):
			st.stage = int(st.stage) + 1
			log_major("log.ast_rank", {"rank": "@sc.ast.stage_" + STAGES[int(st.stage)]})
			return res("sc.ast.selected", {"rank": "@sc.ast.stage_" + STAGES[int(st.stage)]})
		return res("sc.ast.not_selected", {}, false)
	if action.begins_with("mission_"):
		var m = action.substr(8)
		var data: Array = MISSIONS[m]
		st.missions = int(st.missions) + 1
		counter("space.missions")
		if sim.prob.roll_neutral(float(data[0]) * maxf(0.2, 1.0 - float(st.training) / 400.0)):
			sim.health.kill(p, "cause.space")
			return res("sc.ast.lost", {}, false)
		give_exp(p, float(data[1]) * (1.0 + float(p.gamer.level) * 0.05), ctx)
		give_money(p, float(data[1]) * 100.0, ctx)
		fame(p, float(data[2]))
		if m == "rift":
			sim.gamer.add_item(p, "mana_core_large", 2)
		if int(st.missions) >= 5 and int(st.stage) == 2:
			st.stage = 3
			log_major("log.ast_rank", {"rank": "@sc.ast.stage_commander"})
		log_major("log.ast_mission", {"m": "@sc.ast.m_" + m})
		return res("sc.ast.mission_ok", {"m": "@sc.ast.m_" + m})
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	var pay = [30000.0, 60000.0, 120000.0, 200000.0][int(st.stage)]
	sim.finance.add_cash(p, pay)
	st.last_income = pay


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.ast.rank", "@sc.ast.stage_" + STAGES[int(st.stage)]], ["sc.ast.training", str(int(st.training))],
		["sc.ast.missions", str(st.missions)], ["sc.last_income", Fmt.money(float(st.get("last_income", 0)))]]
