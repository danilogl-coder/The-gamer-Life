extends SpecialCareer
## Royalty (only by birth in a monarchy): public duties, charity, scandals,
## succession, decrees that move the economy, abdication.

func start_state(p: Dictionary) -> Dictionary:
	return {"title": "prince" if p.sex == "m" else "princess", "rep": 60.0, "reigning": false, "decrees": 0}


func actions(_p: Dictionary, st: Dictionary) -> Array:
	var out = [act("appearance"), act("charity", 0, 50000.0), act("party")]
	if st.reigning:
		out.append(act("decree_prosperity", 0))
		out.append(act("decree_austerity", 0))
		out.append(act("abdicate", 0))
	return out


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	match action:
		"appearance":
			st.rep = clampf(float(st.rep) + 3.0 + stat(p, "cha") * 0.1, 0.0, 100.0)
			fame(p, 1.0)
			give_exp(p, 20.0, ctx)
			return res("sc.roy.appeared")
		"charity":
			st.rep = clampf(float(st.rep) + 8.0, 0.0, 100.0)
			p.hidden.karma = clampf(float(p.hidden.get("karma", 50)) + 5.0, 0, 100)
			return res("sc.roy.charity")
		"party":
			p.attrs.happiness = clampf(float(p.attrs.happiness) + 10.0, 0, 100)
			if sim.prob.roll_neutral(0.35):
				st.rep = clampf(float(st.rep) - 15.0, 0.0, 100.0)
				fame(p, 3.0)
				return res("sc.roy.scandal", {}, false)
			return res("sc.roy.party")
		"decree_prosperity", "decree_austerity":
			st.decrees = int(st.decrees) + 1
			var w: Dictionary = sim.state.data.world
			if action == "decree_prosperity":
				w.economy = clampf(float(w.economy) + 0.2, -1.0, 1.0)
				w.inflation = float(w.inflation) + 0.02
				st.rep = clampf(float(st.rep) + 6.0, 0.0, 100.0)
			else:
				w.inflation = maxf(0.0, float(w.inflation) - 0.02)
				w.economy = clampf(float(w.economy) - 0.1, -1.0, 1.0)
				st.rep = clampf(float(st.rep) - 8.0, 0.0, 100.0)
			return res("sc.roy.decreed")
		"abdicate":
			st.reigning = false
			st.abdicated = true
			log_major("log.roy_abdicate")
			return res("sc.roy.abdicated")
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	var allowance = (5000000.0 if st.reigning else 400000.0) * float(sim.finance.country(p).get("salary_mult", 1.0))
	sim.finance.add_cash(p, allowance)
	st.last_income = allowance
	p.fame = maxf(float(p.get("fame", 0)), 40.0 if not st.reigning else 80.0)
	st.rep = clampf(float(st.rep) - 2.0, 0.0, 100.0)
	if not st.reigning and not st.get("abdicated", false) and int(p.age) >= 21:
		var parents_alive = false
		for role in ["mother", "father"]:
			if sim.relations.first_with_role(p, role) != "":
				parents_alive = true
		if not parents_alive or int(p.age) >= 60:
			st.reigning = true
			st.title = "king" if p.sex == "m" else "queen"
			counter("royal.crowned")
			log_major("log.roy_crowned", {"title": "@sc.roy.t_" + st.title})
	if st.reigning and float(st.rep) < 10.0 and sim.prob.roll_neutral(0.3):
		st.reigning = false
		st.abdicated = true
		log_major("log.roy_overthrown")


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.roy.title", "@sc.roy.t_" + st.title], ["sc.roy.rep", "%d%%" % int(st.rep)], ["sc.roy.decrees", str(st.decrees)], ["sc.last_income", Fmt.money(float(st.get("last_income", 0)))]]
