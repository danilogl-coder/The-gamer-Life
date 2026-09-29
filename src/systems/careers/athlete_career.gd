extends SpecialCareer
## Pro sports: climb leagues (amateur → semi-pro → pro → elite), train,
## play seasons, win titles, sign sponsors. Injuries hurt; age ends it.

const LEAGUES := [45.0, 70.0, 100.0, 140.0]   # rating needed to compete well
const PAY := [2000.0, 15000.0, 90000.0, 600000.0]


func start_state(p: Dictionary) -> Dictionary:
	var sports := ["football", "basketball", "mma", "tennis"]
	return {"sport": sports[sim.rng.randi_range(0, sports.size() - 1)], "rating": _base_rating(p), "league": 0, "titles": 0, "wins": 0, "sponsor": 0.0}


func _base_rating(p: Dictionary) -> float:
	return stat(p, "str") * 0.8 + stat(p, "vit") * 0.9 + stat(p, "dex") * 1.0 + (float(p.hidden.talent_sport) - 50.0) * 0.4


func actions(p: Dictionary, st: Dictionary) -> Array:
	var out := [act("train"), act("season", 2)]
	out.append(act("sponsor", 0, 0.0, "" if float(p.get("fame", 0)) >= 20.0 and float(st.sponsor) <= 0.0 else "sc.need_fame"))
	out.append(act("retire", 0))
	return out


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	match action:
		"train":
			for s in ["str", "vit", "dex"]:
				sim.gamer.add_stat_xp(p, s, 18.0)
			st.rating = maxf(float(st.rating), _base_rating(p)) + sim.rng.randf_range(1.0, 4.0)
			counter("act.gym")
			give_exp(p, 25.0, ctx)
			if sim.prob.roll_neutral(0.06 * maxf(0.2, 1.0 - sim.gamer.mod("dmg_reduction") * 3.0)):
				sim.health.injure(p, "injury_minor")
				return res("sc.ath.train_hurt", {}, false)
			return res("sc.ath.trained", {"r": int(st.rating)})
		"season":
			var league := int(st.league)
			var power: float = float(st.rating) * sim.rng.randf_range(0.75, 1.3) * (1.0 + sim.prob.luck_bonus() * 0.5)
			var ratio: float = power / LEAGUES[league]
			var pay: float = PAY[league] * (0.5 + minf(ratio, 2.0) * 0.5)
			give_money(p, pay, ctx)
			give_exp(p, 120.0 * (league + 1), ctx)
			fame(p, 1.0 + league * 2.0)
			if sim.prob.roll_neutral(0.1 + league * 0.03):
				sim.health.injure(p, "injury_severe" if sim.prob.roll_neutral(0.25) else "injury_minor")
			if ratio >= 1.15:
				st.wins = int(st.wins) + 1
				if sim.prob.roll_neutral(clampf((ratio - 1.0) * 0.8, 0.05, 0.7)):
					st.titles = int(st.titles) + 1
					fame(p, 6.0 + league * 3.0)
					counter("sport.titles")
					log_major("log.sport_title", {"league": "@sc.ath.league%d" % league})
				if league < LEAGUES.size() - 1 and ratio >= 1.25:
					st.league = league + 1
					log_major("log.sport_promoted", {"league": "@sc.ath.league%d" % (league + 1)})
					return res("sc.ath.promoted", {"league": "@sc.ath.league%d" % (league + 1)})
				return res("sc.ath.good_season", {"v": int(pay)})
			if ratio < 0.8 and league > 0:
				st.league = league - 1
				return res("sc.ath.relegated", {}, false)
			return res("sc.ath.ok_season", {"v": int(pay)})
		"sponsor":
			st.sponsor = float(p.fame) * 3000.0 * (int(st.league) + 1)
			log_major("log.sport_sponsor")
			return res("sc.ath.sponsor", {"v": int(st.sponsor)})
		"retire":
			st.retired = true
			log_major("log.sport_retired", {"titles": int(st.titles)})
			return res("sc.ath.retired", {"titles": int(st.titles)})
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	sim.finance.add_cash(p, float(st.sponsor))
	st.last_income = float(st.sponsor)
	var age := int(p.age)
	if age > 29:
		st.rating = float(st.rating) * (1.0 - 0.03 * (age - 29) * maxf(0.1, 1.0 - sim.gamer.mod("aging_resist")))


func is_finished(p: Dictionary, st: Dictionary) -> bool:
	return st.get("retired", false) or (int(p.age) >= 40 and sim.gamer.mod("aging_resist") < 0.5)


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.ath.sport", "@sc.ath.sport_" + st.sport], ["sc.ath.rating", str(int(st.rating))],
		["sc.ath.league", "@sc.ath.league%d" % int(st.league)], ["sc.ath.titles", str(st.titles)],
		["sc.ath.sponsor_word", Fmt.money(float(st.sponsor))]]
