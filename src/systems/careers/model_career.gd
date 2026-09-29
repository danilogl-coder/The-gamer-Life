extends SpecialCareer
## Modeling: shoots and runway shows; better agencies unlock bigger gigs.
## Looks rule; age and neglect fade the career.

const TIERS := ["local", "national", "international", "supermodel"]


func start_state(_p: Dictionary) -> Dictionary:
	return {"tier": 0, "gigs": 0, "rep": 5.0}


func actions(_p: Dictionary, st: Dictionary) -> Array:
	return [act("shoot"), act("runway", 1, 0.0, "" if int(st.tier) >= 1 else "sc.mod.need_tier"),
		act("agency", 0, 0.0, "" if int(st.tier) < TIERS.size() - 1 and float(st.rep) >= 25.0 * (int(st.tier) + 1) else "sc.mod.need_rep")]


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	var tier = int(st.tier)
	var looks = float(p.attrs.looks)
	match action:
		"shoot", "runway":
			var ok = chance({"base": 0.4 + (looks - 60.0) * 0.01 - tier * 0.05, "mods": [{"path": "stat.cha", "per": 0.003, "offset": 10.0, "max": 0.15}]})
			if not ok:
				return res("sc.mod.passed", {}, false)
			var pay = (1500.0 if action == "shoot" else 6000.0) * pow(4.0, tier)
			give_money(p, pay, ctx)
			st.gigs = int(st.gigs) + 1
			st.rep = float(st.rep) + (4.0 if action == "shoot" else 8.0)
			fame(p, 1.0 + tier)
			give_exp(p, 40.0 * (tier + 1), ctx)
			return res("sc.mod.booked", {"v": int(pay)})
		"agency":
			st.tier = tier + 1
			log_major("log.mod_tier", {"tier": "@sc.mod.t_" + TIERS[int(st.tier)]})
			return res("sc.mod.signed", {"tier": "@sc.mod.t_" + TIERS[int(st.tier)]})
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	st.rep = maxf(0.0, float(st.rep) * 0.85)
	st.last_income = 0.0
	if int(p.age) > 32:
		st.rep = float(st.rep) * 0.8


func is_finished(p: Dictionary, st: Dictionary) -> bool:
	return int(p.age) >= 45 and float(st.rep) < 5.0


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.mod.tier", "@sc.mod.t_" + TIERS[int(st.tier)]], ["sc.mod.gigs", str(st.gigs)], ["sc.act.rep", str(int(st.rep))]]
