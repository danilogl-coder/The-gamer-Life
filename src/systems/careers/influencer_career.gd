extends SpecialCareer
## Content creator on fictional platforms. Posts grow followers based on CHA,
## quality and the algorithm (luck); controversies can cancel you; sponsors
## and streams pay. Followers feed global fame.

const PLATFORMS := ["clipz", "tubee", "chirp", "lumigram", "streamo"]


func start_state(_p: Dictionary) -> Dictionary:
	return {"platform": PLATFORMS[sim.rng.randi_range(0, PLATFORMS.size() - 1)], "followers": 100.0, "engagement": 0.05, "posts": 0, "controversy": 0.0, "sponsors": 0}


func actions(_p: Dictionary, st: Dictionary) -> Array:
	return [act("post"), act("hot_take"), act("stream", 1, 0.0, "" if float(st.followers) >= 1000.0 else "sc.need_fans"),
		act("sponsor", 0, 0.0, "" if float(st.followers) >= 20000.0 else "sc.need_fans"),
		act("apology", 0, 0.0, "" if float(st.controversy) > 10.0 else "ui.invalid")]


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	match action:
		"post":
			st.posts = int(st.posts) + 1
			var quality: float = stat(p, "cha") * 0.8 + stat(p, "dex") * 0.3 + float(p.attrs.looks) * 0.3 + sim.skills.level(p, "drawing") * 2.0
			var growth: float = float(st.followers) * minf(0.3, 0.05 + quality / 3000.0) + minf(quality, 2000.0) * 3.0
			if sim.prob.roll_spec({"base": 0.04, "mods": [{"path": "stat.cha", "per": 0.001, "max": 0.1}]}):
				growth = growth * 4.0 + 20000.0
				fame(p, 5.0)
				st.followers = grow_audience(float(st.followers), growth)
				log_major("log.inf_viral", {"platform": "@sc.inf.plat_" + st.platform})
				return res("sc.inf.viral", {"n": int(growth)})
			st.followers = grow_audience(float(st.followers), growth)
			sim.health.change_habit(p, "social_media", 6.0)
			give_exp(p, 12.0, ctx)
			return res("sc.inf.posted", {"n": int(growth)})
		"hot_take":
			if chance({"base": 0.4, "mods": [{"path": "stat.cha", "per": 0.004, "offset": 10.0, "max": 0.3}]}):
				st.followers = grow_audience(float(st.followers), float(st.followers) * 0.4 + 500.0)
				fame(p, 3.0)
				return res("sc.inf.take_ok")
			st.controversy = float(st.controversy) + 25.0
			st.followers = float(st.followers) * 0.8
			p.attrs.reputation = clampf(float(p.attrs.reputation) - 8.0, 0, 100)
			p.attrs.stress = clampf(float(p.attrs.stress) + 12.0, 0, 100)
			return res("sc.inf.cancelled", {}, false)
		"stream":
			var v: float = float(st.followers) * 0.08 * sim.rng.randf_range(0.5, 1.5)
			give_money(p, v, ctx)
			give_exp(p, 20.0, ctx)
			return res("sc.inf.streamed", {"v": int(v)})
		"sponsor":
			if float(st.controversy) > 30.0:
				return res("sc.inf.sponsor_no", {}, false)
			var v: float = float(st.followers) * 0.5
			st.sponsors = int(st.sponsors) + 1
			give_money(p, v, ctx)
			return res("sc.inf.sponsor", {"v": int(v)})
		"apology":
			st.controversy = maxf(0.0, float(st.controversy) - 20.0)
			st.followers = float(st.followers) * 0.95
			return res("sc.inf.apology")
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	var income: float = float(st.followers) * 0.03 * (1.0 - clampf(float(st.controversy) / 100.0, 0.0, 0.9))
	sim.finance.add_cash(p, income)
	st.last_income = income
	st.followers = maxf(10.0, float(st.followers) * 0.9)
	st.controversy = maxf(0.0, float(st.controversy) - 10.0)
	p.fame = clampf(maxf(float(p.get("fame", 0)), log(maxf(float(st.followers), 1.0)) / log(10.0) * 12.0 - 30.0), 0.0, 100.0)
	if float(st.followers) >= 1000000.0:
		counter("inf.million")


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.inf.platform", "@sc.inf.plat_" + st.platform], ["sc.inf.followers", Fmt.num(st.followers)],
		["sc.inf.posts", str(st.posts)], ["sc.inf.controversy", str(int(st.controversy))], ["sc.last_income", Fmt.money(float(st.get("last_income", 0)))]]
