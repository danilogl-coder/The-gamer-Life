class_name FinanceSystem
extends RefCounted
## Money never arrives "clean": salary -> taxes -> living costs -> housing ->
## dependants -> loans/interest -> habits. Poor management has consequences
## (debt, credit score, bankruptcy events). Also owns properties and
## investments, which read the WorldSystem markets.

const LIFESTYLES := ["frugal", "normal", "comfortable", "lavish"]

var _sim


func _init(sim) -> void:
	_sim = sim


func add_cash(p: Dictionary, amount: float) -> void:
	p.finance.cash = float(p.finance.cash) + amount
	_sim.bus.money_changed.emit(amount)


func country(p: Dictionary) -> Dictionary:
	return _sim.data.get_def("countries", p.get("country", ""))


func is_dependent(p: Dictionary) -> bool:
	return int(p.age) < int(_sim.data.bal("life.adult_age", 18)) and not _sim.crime.in_prison(p)


# ---------------------------------------------------------------------------
# Income / worth
# ---------------------------------------------------------------------------

func yearly_income(p: Dictionary) -> float:
	var total: float = _sim.career.current_salary(p)
	for prop in p.finance.get("properties", []):
		if prop.get("rented", false):
			total += float(prop.value) * float(_sim.data.bal("finance.rent_yield", 0.05))
	return total


func net_worth(p: Dictionary) -> float:
	var worth := float(p.finance.cash) - float(p.finance.get("debt", 0.0))
	for prop in p.finance.get("properties", []):
		worth += float(prop.value)
	for loan in p.finance.get("loans", []):
		worth -= float(loan.balance)
	for asset_id in p.finance.get("investments", {}):
		worth += float(p.finance.investments[asset_id]) * _sim.world.price(asset_id)
	for item in p.finance.get("possessions", []):
		worth += float(item.value)
	return worth


func tax_rate(p: Dictionary, income: float) -> float:
	var c := country(p)
	var rate := float(c.get("tax", 0.25))
	if income > float(_sim.data.bal("finance.high_income", 150000)) * float(c.get("salary_mult", 1.0)):
		rate += float(_sim.data.bal("finance.high_income_extra_tax", 0.08))
	return clampf(rate - _sim.gamer.mod("tax_reduction"), 0.0, 0.7)


func living_cost(p: Dictionary) -> float:
	var c := country(p)
	var base := float(_sim.data.bal("finance.base_living_cost", 12000))
	var style := float(_sim.data.bal("finance.lifestyle_mult." + p.finance.get("lifestyle", "normal"), 1.0))
	var kids := 0
	for id in p.get("rels", {}):
		var rel: Dictionary = p.rels[id]
		if rel.role == "child" and _sim.state.has_npc(id) and int(_sim.state.npc(id).age) < 18 and _sim.state.npc(id).alive:
			kids += 1
	var kid_cost := kids * float(_sim.data.bal("finance.child_cost", 6000))
	return (base * style + kid_cost) * float(c.get("cost_of_living", 1.0)) * float(_sim.state.data.world.price_index)


func housing_cost(p: Dictionary) -> float:
	for prop in p.finance.get("properties", []):
		if prop.get("home", false):
			return float(prop.value) * float(_sim.data.bal("finance.maintenance_rate", 0.01))
	return float(_sim.data.bal("finance.rent_base", 9000)) * float(country(p).get("cost_of_living", 1.0)) * float(_sim.state.data.world.housing)


# ---------------------------------------------------------------------------
# Year tick
# ---------------------------------------------------------------------------

func process_year(p: Dictionary) -> Dictionary:
	var report := {"income": 0.0, "tax": 0.0, "expenses": 0.0, "interest": 0.0}
	_update_properties(p)
	if _sim.crime.in_prison(p):
		_accrue_interest(p, report)
		return report
	var gross := yearly_income(p)
	var tax := gross * tax_rate(p, gross)
	report.income = gross
	report.tax = tax
	var expenses := 0.0
	if not is_dependent(p):
		expenses += living_cost(p) + housing_cost(p)
	expenses += _sim.health.habit_costs(p) + _update_possessions(p)
	report.expenses = expenses
	add_cash(p, gross - tax - expenses)
	_pay_loans(p, report)
	_accrue_interest(p, report)
	_settle_negative_cash(p)
	_update_credit(p)
	_lifestyle_feelings(p)
	p.finance.last_report = report
	return report


func _update_properties(p: Dictionary) -> void:
	var world: Dictionary = _sim.state.data.world
	for prop in p.finance.get("properties", []):
		var def: Dictionary = _sim.data.get_def("properties", prop.id)
		var growth: float = float(world.inflation) + float(world.economy) * 0.03 + float(def.get("appreciation", 0.0)) + _sim.rng.randn(0, 0.03)
		prop.condition = maxf(0.0, float(prop.get("condition", 100)) - float(def.get("wear", 2)))
		var cond_factor := 0.7 + 0.3 * float(prop.condition) / 100.0
		prop.value = maxf(1000.0, float(prop.base_value) * cond_factor * (float(world.housing) / float(prop.housing_at_buy)) * (1.0 + growth * 0.2))


func _pay_loans(p: Dictionary, report: Dictionary) -> void:
	var remaining: Array = []
	for loan in p.finance.loans:
		var interest := float(loan.balance) * float(loan.rate)
		var payment := minf(float(loan.balance) + interest, float(loan.payment))
		loan.balance = float(loan.balance) + interest - payment
		add_cash(p, -payment)
		report.interest += interest
		if float(loan.balance) > 1.0:
			remaining.append(loan)
		else:
			_sim.add_log("log.loan_paid", {"loan": "@loan." + loan.kind}, "info")
	p.finance.loans = remaining


func _accrue_interest(p: Dictionary, report: Dictionary) -> void:
	var debt := float(p.finance.get("debt", 0.0))
	if debt <= 0.0:
		return
	var interest := debt * float(_sim.data.bal("finance.overdraft_rate", 0.18))
	p.finance.debt = debt + interest
	report.interest += interest
	# Pay down the overdraft with any free cash.
	var pay := minf(float(p.finance.cash), float(p.finance.debt))
	if pay > 0.0:
		p.finance.cash = float(p.finance.cash) - pay
		p.finance.debt = float(p.finance.debt) - pay


func _settle_negative_cash(p: Dictionary) -> void:
	if float(p.finance.cash) < 0.0:
		p.finance.debt = float(p.finance.get("debt", 0.0)) - float(p.finance.cash)
		p.finance.cash = 0.0
		_sim.add_log("log.overdraft", {}, "warning")
	var income: float = maxf(yearly_income(p), 1.0)
	if float(p.finance.debt) > income * float(_sim.data.bal("finance.bankruptcy_income_multiple", 4)) and float(p.finance.debt) > 20000:
		_sim.events.queue_special("fin_bankruptcy")


func _update_credit(p: Dictionary) -> void:
	var c := float(p.finance.get("credit", 650))
	if float(p.finance.debt) > 0.0:
		c -= 25
	else:
		c += 8
	if not p.finance.loans.is_empty():
		c += 4
	p.finance.credit = clampf(c, 300, 850)


func _lifestyle_feelings(p: Dictionary) -> void:
	if is_dependent(p):
		return
	var h := float(_sim.data.bal("finance.lifestyle_happiness." + p.finance.get("lifestyle", "normal"), 0))
	p.attrs.happiness = clampf(float(p.attrs.happiness) + h, 0, 100)


# ---------------------------------------------------------------------------
# Player operations
# ---------------------------------------------------------------------------

func set_lifestyle(p: Dictionary, style: String) -> void:
	if LIFESTYLES.has(style):
		p.finance.lifestyle = style


func loan_rate(p: Dictionary, kind: String) -> float:
	var base := float(_sim.data.bal("finance.loan_rates." + kind, 0.1))
	var credit := float(p.finance.get("credit", 650))
	return maxf(0.01, base + (700.0 - credit) / 1000.0 * 0.1 + float(_sim.state.data.world.inflation) * 0.5)


func max_loan(p: Dictionary) -> float:
	if int(p.age) < 18:
		return 0.0
	var credit_factor := (float(p.finance.get("credit", 650)) - 300.0) / 550.0
	return maxf(0.0, (yearly_income(p) * 3.0 + 5000.0) * credit_factor)


func take_loan(p: Dictionary, amount: float, kind: String = "personal", years: int = 5) -> Dictionary:
	if kind == "personal" and amount > max_loan(p):
		return {"ok": false, "reason": "ui.loan_denied"}
	var rate := loan_rate(p, kind)
	var payment := amount * (rate / (1.0 - pow(1.0 + rate, -years))) if rate > 0.0 else amount / years
	p.finance.loans.append({"kind": kind, "balance": amount, "rate": rate, "payment": payment})
	add_cash(p, amount)
	return {"ok": true, "key": "ui.loan_ok", "params": {"amount": int(amount)}}


func pay_debt(p: Dictionary) -> void:
	var pay := minf(float(p.finance.cash), float(p.finance.debt))
	p.finance.cash = float(p.finance.cash) - pay
	p.finance.debt = float(p.finance.debt) - pay


func property_price(def_id: String, p: Dictionary) -> float:
	var def: Dictionary = _sim.data.get_def("properties", def_id)
	return float(def.get("price", 100000)) * float(country(p).get("cost_of_living", 1.0)) * float(_sim.state.data.world.housing)


func buy_property(p: Dictionary, def_id: String, mortgage: bool) -> Dictionary:
	var price := property_price(def_id, p)
	var down := price * (float(_sim.data.bal("finance.mortgage_down", 0.2)) if mortgage else 1.0)
	if float(p.finance.cash) < down:
		return {"ok": false, "reason": "ui.no_money"}
	if mortgage and float(p.finance.credit) < float(_sim.data.bal("finance.mortgage_min_credit", 580)):
		return {"ok": false, "reason": "ui.loan_denied"}
	add_cash(p, -down)
	if mortgage:
		var principal := price - down
		var rate := loan_rate(p, "mortgage")
		var years := 25
		p.finance.loans.append({"kind": "mortgage", "balance": principal, "rate": rate,
			"payment": principal * (rate / (1.0 - pow(1.0 + rate, -years)))})
	var has_home := false
	for prop in p.finance.properties:
		has_home = has_home or prop.get("home", false)
	p.finance.properties.append({"id": def_id, "value": price, "base_value": price,
		"housing_at_buy": float(_sim.state.data.world.housing), "condition": 100.0,
		"home": not has_home, "rented": false, "bought_age": p.age})
	_sim.add_log("log.bought_property", {"prop": "@prop." + def_id}, "major")
	_sim.activities.bump_counter("buy.property")
	return {"ok": true, "key": "ui.bought", "params": {"thing": "@prop." + def_id}}


func sell_property(p: Dictionary, index: int) -> Dictionary:
	if index < 0 or index >= p.finance.properties.size():
		return {"ok": false, "reason": "ui.invalid"}
	var prop: Dictionary = p.finance.properties[index]
	p.finance.properties.remove_at(index)
	add_cash(p, float(prop.value) * 0.94)
	_sim.add_log("log.sold_property", {"prop": "@prop." + prop.id, "value": int(prop.value)}, "info")
	return {"ok": true, "key": "ui.sold", "params": {"value": int(prop.value * 0.94)}}


func toggle_rent(p: Dictionary, index: int) -> void:
	var prop: Dictionary = p.finance.properties[index]
	prop.rented = not prop.get("rented", false)
	if prop.rented:
		prop.home = false


func invest(p: Dictionary, asset_id: String, amount: float) -> Dictionary:
	var price_now: float = _sim.world.price(asset_id)
	if amount <= 0.0 or float(p.finance.cash) < amount or price_now <= 0.0:
		return {"ok": false, "reason": "ui.no_money"}
	add_cash(p, -amount)
	p.finance.investments[asset_id] = float(p.finance.investments.get(asset_id, 0.0)) + amount / price_now
	_sim.activities.bump_counter("invest")
	return {"ok": true, "key": "ui.invested", "params": {"amount": int(amount)}}


func sell_investment(p: Dictionary, asset_id: String) -> Dictionary:
	var units := float(p.finance.investments.get(asset_id, 0.0))
	if units <= 0.0:
		return {"ok": false, "reason": "ui.invalid"}
	var value: float = units * _sim.world.price(asset_id)
	p.finance.investments.erase(asset_id)
	add_cash(p, value)
	return {"ok": true, "key": "ui.sold", "params": {"value": int(value)}}


# ---------------------------------------------------------------------------
# Possessions (vehicles & collectibles)
# ---------------------------------------------------------------------------

func possession_price(p: Dictionary, def_id: String) -> float:
	var def: Dictionary = _sim.data.get_def("possessions", def_id)
	return float(def.get("price", 0)) * float(_sim.state.data.world.price_index) * maxf(0.6, float(country(p).get("cost_of_living", 1.0)))


func buy_possession(p: Dictionary, def_id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("possessions", def_id)
	if def.is_empty() or not _sim.cond.check_all(def.get("conditions", []), {}):
		return {"ok": false, "reason": "ui.invalid"}
	var price := possession_price(p, def_id)
	if not license_ok(p, def):
		return {"ok": false, "reason": "license.required_" + def.license}
	if float(p.finance.cash) < price:
		return {"ok": false, "reason": "ui.no_money"}
	add_cash(p, -price)
	p.finance.possessions.append({"id": def_id, "value": price, "age": 0, "condition": 100.0})
	_sim.gamer.invalidate()
	_sim.add_log("log.bought_possession", {"thing": "@poss." + def_id}, "major" if price > 100000 else "info")
	_sim.activities.bump_counter("buy." + def.kind)
	if def.kind == "vehicle" and not _sim.skills.knows(p, "driving") and int(p.age) >= 16:
		_sim.state.set_flag("drives_unlicensed")
	return {"ok": true, "key": "ui.bought", "params": {"thing": "@poss." + def_id}}


func license_ok(p: Dictionary, def: Dictionary) -> bool:
	var lic: String = def.get("license", "")
	if lic == "":
		return true
	if lic == "driving":
		return _sim.skills.knows(p, "driving") or int(p.age) < 16
	return p.get("licenses", []).has(lic)


func renovate(p: Dictionary, index: int) -> Dictionary:
	if index < 0 or index >= p.finance.properties.size():
		return {"ok": false, "reason": "ui.invalid"}
	var prop: Dictionary = p.finance.properties[index]
	var cost := float(prop.base_value) * 0.08
	if float(p.finance.cash) < cost:
		return {"ok": false, "reason": "ui.no_money"}
	add_cash(p, -cost)
	prop.condition = 100.0
	prop.base_value = float(prop.base_value) * 1.04
	return {"ok": true, "key": "ui.renovated", "params": {"v": int(cost)}}


func sell_possession(p: Dictionary, index: int) -> Dictionary:
	if index < 0 or index >= p.finance.possessions.size():
		return {"ok": false, "reason": "ui.invalid"}
	var item: Dictionary = p.finance.possessions[index]
	p.finance.possessions.remove_at(index)
	add_cash(p, float(item.value) * 0.9)
	_sim.gamer.invalidate()
	return {"ok": true, "key": "ui.sold", "params": {"value": int(float(item.value) * 0.9)}}


func has_vehicle(p: Dictionary) -> bool:
	for item in p.finance.get("possessions", []):
		if _sim.data.get_def("possessions", item.id).get("kind", "") == "vehicle":
			return true
	return false


## Value drift, wear, maintenance and the joy of owning things.
## Returns the yearly upkeep. Breakdowns/thefts/accidents come as events.
func _update_possessions(p: Dictionary) -> float:
	var upkeep := 0.0
	var world: Dictionary = _sim.state.data.world
	for item in p.finance.get("possessions", []):
		var def: Dictionary = _sim.data.get_def("possessions", item.id)
		item.age = int(item.age) + 1
		if def.kind == "vehicle":
			var drift := -float(def.get("depreciation", 0.12))
			if def.has("classic_age") and int(item.age) >= int(def.classic_age):
				drift = 0.06
			item.value = maxf(100.0, float(item.value) * (1.0 + drift))
			item.condition = maxf(0.0, float(item.condition) - 6.0)
			upkeep += float(def.get("maintenance", 500)) * float(world.price_index)
			if _sim.prob.roll_neutral((1.0 - float(def.get("reliability", 0.9))) * (1.5 - float(item.condition) / 100.0)):
				_sim.events.queue_event("vehicle_breakdown")
		else:
			item.value = maxf(10.0, float(item.value) * (1.0 + float(def.get("trend", 0.03)) + _sim.rng.randn(0, float(def.get("vol", 0.1)))))
		p.attrs.happiness = clampf(float(p.attrs.happiness) + float(def.get("happiness", 0)) * 0.5, 0, 100)
		p.fame = clampf(float(p.get("fame", 0)) + float(def.get("fame", 0)), 0, 100)
	return upkeep


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

func emigration_cost(p: Dictionary, country_id: String) -> float:
	return 3000.0 * float(_sim.data.get_def("countries", country_id).get("cost_of_living", 1.0)) * float(_sim.state.data.world.price_index)


## Moving abroad changes salaries, taxes, cost of living and the dungeon
## density (rifts). You lose your job and distant bonds cool off; languages
## help you adapt.
func emigrate(p: Dictionary, country_id: String) -> Dictionary:
	if country_id == p.country or _sim.data.get_def("countries", country_id).is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	if int(p.age) < 18 or _sim.crime.in_prison(p):
		return {"ok": false, "reason": "job.block.age"}
	var cost := emigration_cost(p, country_id)
	if float(p.finance.cash) < cost:
		return {"ok": false, "reason": "ui.no_money"}
	add_cash(p, -cost)
	# Visa application: money, a job, education and a clean record help.
	var visa := {"base": 0.45, "mods": [
		{"path": "calc.net_worth", "per": 0.000002, "max": 0.2},
		{"path": "calc.employed", "per": 0.1},
		{"path": "player.attrs.reputation", "per": 0.003, "offset": 50.0}]}
	if not p.criminal.record.is_empty():
		visa.base = float(visa.base) - 0.25
	if not _sim.prob.roll_spec(visa):
		_sim.add_log("log.visa_denied", {"country": "@country." + country_id}, "warning")
		return {"ok": false, "reason": "ui.visa_denied"}
	var old: String = p.country
	p.country = country_id
	if _sim.career.is_employed(p):
		_sim.career.fire(p, "quit")
	var adapt: float = 0.5 + _sim.gamer.effective_stat(p, "cha") * 0.01 + float(_sim.state.counter("act.learn_language")) * 0.05
	for id in p.rels.keys():
		if not (p.rels[id].role in ["spouse", "child", "partner", "fiance"]):
			_sim.relations.change_score(id, -15.0 / maxf(adapt, 0.5))
	p.attrs.stress = clampf(float(p.attrs.stress) + 15.0 / maxf(adapt, 0.5), 0, 100)
	_sim.activities.bump_counter("migration.moves")
	_sim.add_log("log.emigrated", {"from": "@country." + old, "to": "@country." + country_id}, "major")
	return {"ok": true, "key": "ui.emigrated", "params": {"country": "@country." + country_id}}


func npc_starting_cash(npc: Dictionary) -> float:
	var mult := {"poor": 0.1, "working": 0.4, "middle": 1.0, "upper": 4.0, "elite": 20.0}
	return maxf(0.0, float(mult.get(npc.wealth, 1.0)) * maxf(0, int(npc.age) - 18) * 1500.0 * _sim.rng.randf_range(0.5, 1.5))
