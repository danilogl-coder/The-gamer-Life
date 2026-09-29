extends SpecialCareer
## Street hustles: busking, living statue, street magic (real magic once the
## hidden world is revealed!) or fortune telling (WIS/Observe). Anyone can
## start; regulars build up; a lucky day can go viral.

const HUSTLES := {"busker": "cha", "statue": "vit", "magic": "int", "fortune": "wis"}


func start_state(_p: Dictionary) -> Dictionary:
	var ids: Array = HUSTLES.keys()
	ids.sort()
	return {"hustle": ids[sim.rng.randi_range(0, ids.size() - 1)], "regulars": 0.0, "earned": 0.0}


func actions(_p: Dictionary, _st: Dictionary) -> Array:
	var out = [act("perform"), act("switch", 0)]
	return out


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	match action:
		"perform":
			var s: String = HUSTLES[st.hustle]
			var v = (30.0 + stat(p, s) * 12.0 + float(st.regulars) * 3.0) * sim.rng.randf_range(0.5, 1.6)
			if st.hustle == "magic" and sim.skills.knows(p, "mana_control"):
				v *= 3.0
			if st.hustle == "fortune":
				v *= 1.0 + sim.skills.level(p, "observe") * 0.1
			give_money(p, v, ctx)
			st.earned = float(st.earned) + v
			st.regulars = float(st.regulars) + 1.0 + stat(p, "cha") * 0.05
			sim.gamer.add_stat_xp(p, s, 12.0)
			give_exp(p, 12.0, ctx)
			if sim.prob.roll(sim.prob.apply_luck(0.03)):
				fame(p, 4.0)
				st.regulars = float(st.regulars) * 2.0
				return res("sc.hus.viral", {"v": int(v)})
			return res("sc.hus.earned", {"v": int(v)})
		"switch":
			var ids: Array = HUSTLES.keys()
			ids.sort()
			st.hustle = ids[(ids.find(st.hustle) + 1) % ids.size()]
			st.regulars = float(st.regulars) * 0.5
			return res("sc.hus.switched", {"h": "@sc.hus.h_" + st.hustle})
	return {"ok": false, "reason": "ui.invalid"}


func tick(_p: Dictionary, st: Dictionary) -> void:
	st.regulars = float(st.regulars) * 0.8
	st.last_income = 0.0


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.hus.hustle", "@sc.hus.h_" + st.hustle], ["sc.hus.regulars", str(int(st.regulars))], ["sc.hus.earned_total", Fmt.money(float(st.earned))]]
