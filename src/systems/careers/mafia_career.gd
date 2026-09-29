extends SpecialCareer
## Organized crime: associate → soldier → capo → underboss → don.
## Jobs earn money and respect but raise heat; raids end in trials.
## Informing gets you out alive — with enemies for life.

const RANKS := 5


func start_state(_p: Dictionary) -> Dictionary:
	var families = ["moretti", "kurogane", "vasquez"]
	return {"family": families[sim.rng.randi_range(0, 2)], "rank": 0, "respect": 0.0, "heat": 0.0}


func actions(_p: Dictionary, st: Dictionary) -> Array:
	return [act("extort"), act("smuggle"), act("hit", 1, 0.0, "" if int(st.rank) >= 1 and sim.allows(["mature"]) else "ui.invalid"),
		act("bribe_cop", 0, 20000.0), act("rise", 0), act("inform", 0)]


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	var rank = int(st.rank)
	match action:
		"extort", "smuggle", "hit":
			var base: float = {"extort": 0.7, "smuggle": 0.55, "hit": 0.45}[action]
			var stat_id: String = {"extort": "cha", "smuggle": "dex", "hit": "str"}[action]
			counter("crime.total")
			p.hidden.karma = clampf(float(p.hidden.get("karma", 50)) - (12.0 if action == "hit" else 3.0), 0, 100)
			if chance({"base": base, "mods": [{"path": "stat." + stat_id, "per": 0.006, "offset": 10.0, "max": 0.3}, {"path": "mod.crime_success", "per": 1.0}]}):
				var pay: float = {"extort": 6000.0, "smuggle": 25000.0, "hit": 60000.0}[action] * (1.0 + rank * 0.8)
				if action == "smuggle" and sim.state.flag("world_revealed", false):
					pay *= 1.5
				give_money(p, pay, ctx)
				st.respect = float(st.respect) + {"extort": 5.0, "smuggle": 8.0, "hit": 20.0}[action]
				st.heat = float(st.heat) + {"extort": 6.0, "smuggle": 10.0, "hit": 25.0}[action]
				give_exp(p, 40.0 * (rank + 1), ctx)
				return res("sc.maf.job_ok", {"v": int(pay)})
			st.heat = float(st.heat) + 15.0
			st.respect = maxf(0.0, float(st.respect) - 5.0)
			return res("sc.maf.job_fail", {}, false)
		"bribe_cop":
			st.heat = maxf(0.0, float(st.heat) - 30.0)
			return res("sc.maf.bribed")
		"rise":
			var need = 30.0 * (rank + 1)
			if float(st.respect) >= need and rank < RANKS - 1:
				st.respect = float(st.respect) - need
				st.rank = rank + 1
				counter("mafia.promotions")
				log_major("log.maf_rank", {"rank": "@sc.maf.rank%d" % int(st.rank)})
				return res("sc.maf.promoted", {"rank": "@sc.maf.rank%d" % int(st.rank)})
			return res("sc.maf.not_yet", {}, false)
		"inform":
			st.informant = true
			p.criminal.heat = 0.0
			sim.state.set_flag("mafia_informant")
			sim.events.schedule("mafia_revenge", sim.rng.randi_range(2, 10))
			log_major("log.maf_inform")
			return res("sc.maf.informed")
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	var cut = 5000.0 * pow(2.2, int(st.rank))
	sim.finance.add_cash(p, cut)
	st.last_income = cut
	st.heat = maxf(0.0, float(st.heat) - 8.0)
	if sim.prob.roll_neutral(clampf(float(st.heat) / 250.0, 0.0, 0.5)):
		st.raided = true
		log_major("log.maf_raid")
		sim.crime.arrest(p, "racketeering", float(st.heat) / 200.0)


func is_finished(_p: Dictionary, st: Dictionary) -> bool:
	return st.get("informant", false) or st.get("raided", false)


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.maf.family", "@sc.maf.f_" + st.family], ["sc.maf.rank", "@sc.maf.rank%d" % int(st.rank)],
		["sc.maf.respect", str(int(st.respect))], ["sc.maf.heat", str(int(st.heat))], ["sc.last_income", Fmt.money(float(st.get("last_income", 0)))]]
