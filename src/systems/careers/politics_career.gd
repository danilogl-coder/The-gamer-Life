extends SpecialCareer
## Politics: build a base, fundraise, campaign and win elections up the ladder
## (city council → mayor → governor → president). Reputation, CHA, fame and a
## clean record matter; scandals (from your crimes and affairs) can end it.

const OFFICES := ["council", "mayor", "governor", "president"]
const SALARY := [60000.0, 120000.0, 220000.0, 400000.0]


func start_state(_p: Dictionary) -> Dictionary:
	return {"office": -1, "support": 10.0, "funds": 0.0, "terms": 0, "platform": "", "campaigning": false}


func actions(p: Dictionary, st: Dictionary) -> Array:
	var next := int(st.office) + 1
	return [act("rally"), act("fundraise"),
		act("campaign", 2, 0.0, "" if next < OFFICES.size() and float(st.funds) >= _campaign_cost(next) else ("sc.pol.need_funds" if next < OFFICES.size() else "ui.invalid")),
		act("policy_popular", 0, 0.0, "" if int(st.office) >= 0 else "sc.pol.need_office"),
		act("policy_bold", 0, 0.0, "" if int(st.office) >= 0 else "sc.pol.need_office")]


func _campaign_cost(level: int) -> float:
	return [5000.0, 40000.0, 300000.0, 2000000.0][level]


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	match action:
		"rally":
			var gain = 2.0 + stat(p, "cha") * 0.15 + float(p.get("fame", 0)) * 0.05
			st.support = clampf(float(st.support) + gain * sim.rng.randf_range(0.6, 1.4), 0.0, 100.0)
			sim.gamer.add_stat_xp(p, "cha", 15.0)
			give_exp(p, 20.0, ctx)
			return res("sc.pol.rallied", {"s": int(st.support)})
		"fundraise":
			var v = (1000.0 + stat(p, "cha") * 150.0 + float(st.support) * 300.0) * (int(st.office) + 2)
			st.funds = float(st.funds) + v
			return res("sc.pol.raised", {"v": int(v)})
		"campaign":
			var next := int(st.office) + 1
			st.funds = float(st.funds) - _campaign_cost(next)
			var scandal = p.criminal.record.size() * 0.12 + (0.15 if sim.state.flag("cheated_partner", false) else 0.0)
			var spec := {"base": 0.15 + float(st.support) / 150.0 - next * 0.08 - scandal, "mods": [
				{"path": "stat.cha", "per": 0.002, "max": 0.2}, {"path": "player.attrs.reputation", "per": 0.004, "offset": 50.0}]}
			give_exp(p, 150.0 * (next + 1), ctx)
			if chance(spec):
				st.office = next
				st.terms = 0
				fame(p, 5.0 + next * 5.0)
				counter("politics.elected")
				log_major("log.pol_elected", {"office": "@sc.pol.office_" + OFFICES[next]})
				return res("sc.pol.won", {"office": "@sc.pol.office_" + OFFICES[next]})
			st.support = float(st.support) * 0.7
			return res("sc.pol.lost", {}, false)
		"policy_popular":
			st.support = clampf(float(st.support) + 8.0, 0.0, 100.0)
			sim.state.data.world.economy = clampf(float(sim.state.data.world.economy) - 0.05 * (int(st.office) + 1), -1.0, 1.0)
			return res("sc.pol.popular")
		"policy_bold":
			st.support = clampf(float(st.support) - 10.0, 0.0, 100.0)
			sim.state.data.world.economy = clampf(float(sim.state.data.world.economy) + 0.08 * (int(st.office) + 1), -1.0, 1.0)
			p.attrs.reputation = clampf(float(p.attrs.reputation) + 3.0, 0, 100)
			return res("sc.pol.bold")
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	var office = int(st.office)
	st.support = maxf(0.0, float(st.support) - 3.0)
	st.last_income = 0.0
	if office < 0:
		return
	var pay = SALARY[office] * float(sim.finance.country(p).get("salary_mult", 1.0))
	sim.finance.add_cash(p, pay)
	st.last_income = pay
	st.terms = int(st.terms) + 1
	p.attrs.stress = clampf(float(p.attrs.stress) + 6.0 + office * 2.0, 0, 100)
	# Term ends every 4 years: re-election depends on support.
	if int(st.terms) % 4 == 0 and not sim.prob.roll_neutral(clampf(float(st.support) / 100.0 + 0.2, 0.1, 0.9)):
		log_major("log.pol_voted_out", {"office": "@sc.pol.office_" + OFFICES[office]})
		st.office = office - 1


func summary(_p: Dictionary, st: Dictionary) -> Array:
	var office = "—" if int(st.office) < 0 else "@sc.pol.office_" + OFFICES[int(st.office)]
	return [["sc.pol.office", office], ["sc.pol.support", "%d%%" % int(st.support)], ["sc.pol.funds", Fmt.money(float(st.funds))], ["sc.last_income", Fmt.money(float(st.get("last_income", 0)))]]
