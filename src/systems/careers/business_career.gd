extends SpecialCareer
## Entrepreneur: found a company in a sector, set price, hire, market, invest
## in quality, expand, sell. Demand follows the world economy and sector
## trends; competitors react to your success. INT/CHA and Negotiation matter.

const SECTORS := {
	"food": {"demand": 900.0, "beta": 0.3, "unit": 35.0},
	"tech": {"demand": 500.0, "beta": 0.8, "unit": 120.0},
	"retail": {"demand": 1100.0, "beta": 0.5, "unit": 28.0},
	"services": {"demand": 700.0, "beta": 0.4, "unit": 60.0},
	"mana_goods": {"demand": 400.0, "beta": 0.2, "unit": 200.0},
}
const PRICE_MULT := {"low": 0.75, "mid": 1.0, "high": 1.4}


func start_state(_p: Dictionary) -> Dictionary:
	var keys: Array = SECTORS.keys()
	if not sim.state.flag("world_revealed", false):
		keys.erase("mana_goods")
	keys.sort()
	return {"sector": keys[sim.rng.randi_range(0, keys.size() - 1)], "employees": 1, "quality": 40.0,
		"brand": 5.0, "price": "mid", "capital": 0.0, "profit": 0.0, "revenue": 0.0, "competition": 1.0, "rounds": 0}


func actions(_p: Dictionary, st: Dictionary) -> Array:
	return [act("hire", 0, 0.0, "" if int(st.employees) < 500 else "ui.invalid"),
		act("fire", 0, 0.0, "" if int(st.employees) > 1 else "ui.invalid"),
		act("marketing", 1, 2000.0 + int(st.employees) * 300.0),
		act("rnd", 1, 3000.0 + int(st.employees) * 400.0),
		act("price_low", 0, 0.0, "" if st.price != "low" else "ui.invalid"),
		act("price_mid", 0, 0.0, "" if st.price != "mid" else "ui.invalid"),
		act("price_high", 0, 0.0, "" if st.price != "high" else "ui.invalid"),
		act("sell", 0, 0.0, "" if valuation(st) > 0.0 else "ui.invalid")]


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	match action:
		"hire":
			st.employees = int(st.employees) + maxi(1, int(int(st.employees) * 0.25))
			return res("sc.biz.hired", {"n": int(st.employees)})
		"fire":
			st.employees = maxi(1, int(int(st.employees) * 0.75))
			p.attrs.reputation = clampf(float(p.attrs.reputation) - 1.0, 0, 100)
			return res("sc.biz.fired", {"n": int(st.employees)})
		"marketing":
			var gain: float = 5.0 + stat(p, "cha") * 0.3 + sim.skills.level(p, "negotiation") * 1.5
			st.brand = float(st.brand) + gain * sim.rng.randf_range(0.6, 1.4)
			give_exp(p, 30.0, ctx)
			return res("sc.biz.marketing", {"b": int(st.brand)})
		"rnd":
			st.quality = float(st.quality) + (4.0 + stat(p, "int") * 0.25 + sim.skills.level(p, "programming")) * sim.rng.randf_range(0.5, 1.5)
			give_exp(p, 30.0, ctx)
			return res("sc.biz.rnd", {"q": int(st.quality)})
		"price_low", "price_mid", "price_high":
			st.price = action.substr(6)
			return res("sc.biz.price", {"p": "@sc.biz.price_" + st.price})
		"sell":
			var v := valuation(st)
			give_money(p, v, ctx)
			st.sold = true
			counter("biz.sold")
			if v >= 1.0e9:
				counter("biz.unicorn")
			log_major("log.biz_sold", {"v": int(v)})
			return res("sc.biz.sold", {"v": int(v)})
	return {"ok": false, "reason": "ui.invalid"}


func valuation(st: Dictionary) -> float:
	return maxf(0.0, float(st.profit) * 6.0 + float(st.revenue) * 0.5 + float(st.brand) * 800.0)


func tick(p: Dictionary, st: Dictionary) -> void:
	var sec: Dictionary = SECTORS[st.sector]
	var econ: float = float(sim.state.data.world.economy)
	var price_m: float = PRICE_MULT[st.price]
	var demand: float = float(sec.demand) * (1.0 + econ * float(sec.beta)) * (1.0 + float(st.brand) / 25.0)
	demand *= clampf(float(st.quality) / 50.0, 0.3, 4.0) / pow(price_m, 1.6) / float(st.competition)
	if st.sector == "mana_goods":
		demand *= 0.6 + float(sim.state.data.world.rift)
	var capacity: float = float(st.employees) * 260.0
	var sold := minf(demand * sim.rng.randf_range(0.8, 1.2), capacity)
	var revenue := sold * float(sec.unit) * price_m
	var mgmt: float = 1.0 + (stat(p, "int") + stat(p, "cha")) * 0.002 + sim.skills.level(p, "leadership") * 0.02
	var costs: float = float(st.employees) * 22000.0 * float(sim.finance.country(p).get("salary_mult", 1.0)) / mgmt + 5000.0
	var profit: float = revenue - costs
	if profit > 0.0:
		profit *= 1.0 - sim.finance.tax_rate(p, profit)
	st.revenue = revenue
	st.profit = profit
	st.brand = maxf(0.0, float(st.brand) * 0.9)
	st.quality = maxf(10.0, float(st.quality) * 0.97)
	# Competitors react to success.
	st.competition = clampf(float(st.competition) + (0.1 if profit > 200000.0 else -0.05), 0.7, 3.0)
	sim.finance.add_cash(p, profit)
	st.last_income = profit
	st.capital = float(st.capital) + profit
	give_exp(p, clampf(profit / 1000.0, 10.0, 3000.0), {"gains": {}})
	if profit > 1.0e6:
		counter("biz.million_year")
	if float(st.capital) < -150000.0:
		st.bankrupt = true
		log_major("log.biz_bankrupt")


func is_finished(_p: Dictionary, st: Dictionary) -> bool:
	return st.get("sold", false) or st.get("bankrupt", false)


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.biz.sector", "@sc.biz.sector_" + st.sector], ["sc.biz.employees", str(st.employees)],
		["sc.biz.quality", str(int(st.quality))], ["sc.biz.brand", str(int(st.brand))],
		["sc.biz.price_word", "@sc.biz.price_" + st.price], ["sc.biz.revenue", Fmt.money(float(st.revenue))],
		["sc.biz.profit", Fmt.money(float(st.profit))], ["sc.biz.valuation", Fmt.money(valuation(st))]]
