extends SpecialCareer
## Military: pick a branch, train, deploy, earn medals and climb 8 ranks.
## Deployments can wound or kill; deserting makes you a criminal.

const RANKS := 8
const BRANCH_STAT := {"army": "str", "navy": "vit", "air_force": "dex", "marines": "str"}


func start_state(_p: Dictionary) -> Dictionary:
	var branches: Array = BRANCH_STAT.keys()
	branches.sort()
	return {"branch": branches[sim.rng.randi_range(0, branches.size() - 1)], "rank": 0, "merit": 0.0, "deployments": 0, "medals": 0}


func actions(_p: Dictionary, _st: Dictionary) -> Array:
	return [act("train"), act("deploy", 2), act("promotion", 0), act("desert", 0)]


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	var key_stat: String = BRANCH_STAT[st.branch]
	match action:
		"train":
			sim.gamer.add_stat_xp(p, key_stat, 20.0)
			sim.gamer.add_stat_xp(p, "vit", 10.0)
			st.merit = float(st.merit) + 5.0
			give_exp(p, 30.0, ctx)
			p.health.fitness = clampf(float(p.health.fitness) + 8.0, 0, 100)
			return res("sc.mil.trained")
		"deploy":
			st.deployments = int(st.deployments) + 1
			counter("military.deployments")
			var danger = 0.12 - stat(p, key_stat) * 0.001
			if sim.prob.roll_neutral(clampf(danger * 0.15, 0.002, 0.03)):
				sim.health.kill(p, "cause.war")
				return res("sc.mil.kia", {}, false)
			if sim.prob.roll_neutral(clampf(danger, 0.02, 0.2)):
				sim.health.injure(p, "injury_severe")
			st.merit = float(st.merit) + 20.0 + stat(p, key_stat) * 0.2
			give_exp(p, 200.0 * (int(st.rank) + 1), ctx)
			give_money(p, 8000.0, ctx)
			p.attrs.stress = clampf(float(p.attrs.stress) + 15.0, 0, 100)
			if sim.prob.roll(sim.prob.apply_luck(0.15)):
				st.medals = int(st.medals) + 1
				counter("military.medals")
				fame(p, 2.0)
				log_major("log.mil_medal")
				return res("sc.mil.medal")
			return res("sc.mil.deployed")
		"promotion":
			var need = 40.0 * (int(st.rank) + 1)
			if float(st.merit) >= need and int(st.rank) < RANKS - 1 and chance({"base": 0.5, "mods": [{"path": "player.attrs.discipline", "per": 0.005, "offset": 50.0}]}):
				st.merit = float(st.merit) - need
				st.rank = int(st.rank) + 1
				log_major("log.mil_rank", {"rank": "@sc.mil.rank%d" % int(st.rank)})
				return res("sc.mil.promoted", {"rank": "@sc.mil.rank%d" % int(st.rank)})
			return res("sc.mil.not_promoted", {}, false)
		"desert":
			st.deserted = true
			sim.crime.add_record(p, "desertion")
			p.hidden.karma = clampf(float(p.hidden.get("karma", 50)) - 10.0, 0, 100)
			log_major("log.mil_desert")
			return res("sc.mil.deserted", {}, false)
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	var pay = 25000.0 * pow(1.3, int(st.rank)) * float(sim.finance.country(p).get("salary_mult", 1.0))
	sim.finance.add_cash(p, pay)
	st.last_income = pay
	p.attrs.discipline = clampf(float(p.attrs.discipline) + 2.0, 0, 100)


func is_finished(p: Dictionary, st: Dictionary) -> bool:
	return st.get("deserted", false) or int(p.age) >= 60


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.mil.branch", "@sc.mil.b_" + st.branch], ["sc.mil.rank", "@sc.mil.rank%d" % int(st.rank)],
		["sc.mil.merit", str(int(st.merit))], ["sc.mil.medals", str(st.medals)], ["sc.last_income", Fmt.money(float(st.get("last_income", 0)))]]
