extends SpecialCareer
## Acting: classes, extra work, auditions for TV and film, an agent, awards.
## Looks, CHA and the Acting skill decide auditions; fame opens doors.

const ROLE_PAY := {"extra": 300.0, "tv": 40000.0, "film": 250000.0}


func start_state(_p: Dictionary) -> Dictionary:
	return {"credits": 0, "agent": false, "awards": 0, "best_role": "", "rep": 5.0}


func _audition_spec(p: Dictionary, st: Dictionary, difficulty: float) -> Dictionary:
	return {"base": 0.55 - difficulty + float(st.rep) * 0.004 + (0.12 if st.agent else 0.0), "mods": [
		{"path": "skill.acting", "per": 0.03}, {"path": "player.attrs.looks", "per": 0.004, "offset": 50.0},
		{"path": "stat.cha", "per": 0.003, "offset": 10.0, "max": 0.2}, {"path": "player.fame", "per": 0.003}]}


func actions(p: Dictionary, st: Dictionary) -> Array:
	return [act("class", 1, 500.0), act("extra"), act("tv", 1, 0.0, "" if int(st.credits) >= 2 else "sc.act.need_credits"),
		act("film", 2, 0.0, "" if int(st.credits) >= 5 else "sc.act.need_credits"),
		act("agent", 0, 5000.0, "" if not st.agent and float(st.rep) >= 20.0 else "ui.invalid")]


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	match action:
		"class":
			sim.skills.learn(p, "acting")
			sim.skills.add_xp(p, "acting", 12.0)
			sim.gamer.add_stat_xp(p, "cha", 12.0)
			counter("act.acting")
			return res("sc.act.class")
		"extra":
			give_money(p, ROLE_PAY.extra * sim.rng.randf_range(0.8, 1.5), ctx)
			st.credits = int(st.credits) + 1
			st.rep = float(st.rep) + 2.0
			sim.skills.add_xp(p, "acting", 5.0)
			give_exp(p, 15.0, ctx)
			return res("sc.act.extra")
		"tv", "film":
			var diff = 0.25 if action == "tv" else 0.45
			if not chance(_audition_spec(p, st, diff)):
				st.rep = maxf(0.0, float(st.rep) - 1.0)
				return res("sc.act.rejected", {}, false)
			var pay: float = ROLE_PAY[action] * (1.0 + float(st.rep) / 50.0)
			give_money(p, pay, ctx)
			st.credits = int(st.credits) + 1
			st.rep = float(st.rep) + (6.0 if action == "tv" else 12.0)
			st.best_role = action
			fame(p, 4.0 if action == "tv" else 9.0)
			give_exp(p, 150.0 if action == "tv" else 400.0, ctx)
			counter("acting.roles")
			# Award season.
			var award_p = clampf((sim.skills.level(p, "acting") * 4.0 + float(st.rep)) / 400.0, 0.01, 0.35) * (1.5 if action == "film" else 1.0)
			if sim.prob.roll(sim.prob.apply_luck(award_p)):
				st.awards = int(st.awards) + 1
				counter("acting.awards")
				fame(p, 10.0)
				log_major("log.act_award")
				return res("sc.act.award", {"v": int(pay)})
			return res("sc.act.cast", {"role": "@sc.act.role_" + action, "v": int(pay)})
		"agent":
			st.agent = true
			return res("sc.act.agent")
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	var residuals = float(st.credits) * 400.0 * (1.0 + float(st.awards))
	sim.finance.add_cash(p, residuals)
	st.last_income = residuals
	st.rep = maxf(0.0, float(st.rep) * 0.92)


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.act.credits", str(st.credits)], ["sc.act.rep", str(int(st.rep))], ["sc.act.awards", str(st.awards)],
		["sc.act.agent_word", "✔" if st.agent else "—"], ["sc.last_income", Fmt.money(float(st.get("last_income", 0)))]]
