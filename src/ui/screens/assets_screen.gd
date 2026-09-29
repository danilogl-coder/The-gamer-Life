extends VBoxContainer
## PATRIMÔNIO — cash, last year's money report, debts/loans, lifestyle,
## properties and investments (markets react to the world simulation).

var ui
var _box: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_box = W.vbox(10)
	add_child(W.scroll(_box))


func refresh() -> void:
	W.clear(_box)
	var sim: LifeSimulation = App.sim
	var p := sim.player()
	_summary(sim, p)
	if int(p.age) < 16:
		_box.add_child(W.label(App.t("ui.assets_minor"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		return
	_lifestyle(p)
	_loans(sim, p)
	_properties(sim, p)
	_possessions(sim, p)
	_markets(sim, p)
	_will(sim, p)
	_migration(sim, p)


func _summary(sim: LifeSimulation, p: Dictionary) -> void:
	var card := W.vbox(6)
	card.add_child(W.label(Fmt.money(float(p.finance.cash)), UiTheme.FONT_XL, UiTheme.GOLD))
	card.add_child(W.label(App.t("ui.net_worth") + ": " + Fmt.money(sim.finance.net_worth(p)), UiTheme.FONT_S, UiTheme.TEXT))
	card.add_child(W.label(App.t("ui.credit_score", {"n": int(p.finance.credit)}), UiTheme.FONT_S, UiTheme.TEXT_DIM))
	var r: Dictionary = p.finance.get("last_report", {})
	if not r.is_empty():
		card.add_child(W.label(App.t("ui.report", {"i": Fmt.money(r.income), "t": Fmt.money(r.tax), "e": Fmt.money(r.expenses), "x": Fmt.money(r.interest)}), 18, UiTheme.TEXT_DIM, true))
	var w: Dictionary = sim.state.data.world
	var econ := "▲" if float(w.economy) > 0.2 else ("▼" if float(w.economy) < -0.2 else "■")
	card.add_child(W.label(App.t("ui.world_line", {"e": econ, "inf": Fmt.pct(float(w.inflation)), "u": Fmt.pct(float(w.unemployment))}), 18, UiTheme.PURPLE, true))
	_box.add_child(W.system_card(card))


func _lifestyle(p: Dictionary) -> void:
	_box.add_child(W.section(App.t("ui.lifestyle")))
	var row := W.flow(6)
	for s in FinanceSystem.LIFESTYLES:
		var sel: bool = p.finance.lifestyle == s
		var b := W.tinted_button(App.t("lifestyle." + s), func(): App.sim.command("lifestyle", [s]), UiTheme.SYSTEM if sel else UiTheme.PANEL, 64)
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_FILL
		b.custom_minimum_size.x = 150
		row.add_child(b)
	_box.add_child(row)


func _loans(sim: LifeSimulation, p: Dictionary) -> void:
	_box.add_child(W.section(App.t("ui.debts")))
	var card := W.vbox(6)
	if float(p.finance.debt) > 0:
		card.add_child(W.label(App.t("ui.overdraft", {"v": Fmt.money(float(p.finance.debt))}), UiTheme.FONT_S, UiTheme.BAD))
		card.add_child(W.button(App.t("ui.pay_debt"), func(): App.sim.command("pay_debt"), 68, UiTheme.FONT_S))
	for loan in p.finance.loans:
		card.add_child(W.label("%s: %s (%s/%s)" % [App.t("loan." + loan.kind), Fmt.money(float(loan.balance)), Fmt.money(float(loan.payment)), App.t("ui.year_short")], UiTheme.FONT_S, UiTheme.TEXT))
	var max_loan := sim.finance.max_loan(p)
	if max_loan >= 1000.0:
		var amount := snappedf(max_loan * 0.5, 100.0)
		card.add_child(W.button(App.t("ui.take_loan", {"v": Fmt.money(amount), "r": Fmt.pct(sim.finance.loan_rate(p, "personal"))}), func(): ui.show_result(App.sim.command("take_loan", [amount])), 72, UiTheme.FONT_S))
	if card.get_child_count() == 0:
		card.add_child(W.label(App.t("ui.no_debts"), UiTheme.FONT_S, UiTheme.TEXT_DIM))
	_box.add_child(W.card(card))


func _properties(sim: LifeSimulation, p: Dictionary) -> void:
	_box.add_child(W.section(App.t("ui.properties")))
	for i in p.finance.properties.size():
		var prop: Dictionary = p.finance.properties[i]
		var card := W.vbox(6)
		var tag := App.t("ui.home") if prop.get("home", false) else (App.t("ui.rented_out") if prop.get("rented", false) else "")
		card.add_child(W.label("%s  %s" % [App.t("prop." + prop.id), tag], UiTheme.FONT_M, UiTheme.TEXT))
		card.add_child(W.label(App.t("ui.prop_value", {"v": Fmt.money(float(prop.value)), "c": int(prop.condition)}), UiTheme.FONT_S, UiTheme.TEXT_DIM))
		var row := W.hbox(8)
		row.add_child(W.button(App.t("ui.sell"), func(): ui.show_result(App.sim.command("sell_property", [i])), 68, UiTheme.FONT_S))
		row.add_child(W.button(App.t("ui.toggle_rent"), func(): App.sim.command("toggle_rent", [i]), 68, UiTheme.FONT_S))
		row.add_child(W.button(App.t("ui.renovate"), func(): ui.show_result(App.sim.command("renovate", [i])), 68, UiTheme.FONT_S))
		card.add_child(row)
		_box.add_child(W.card(card))
	for id in App.data.table("properties"):
		var price := sim.finance.property_price(id, p)
		var row := W.hbox(8)
		var cash := W.button(App.t("ui.buy_cash", {"p": App.t("prop." + id), "v": Fmt.money(price)}), func(): ui.show_result(App.sim.command("buy_property", [id, false])), 76, 18)
		cash.disabled = float(p.finance.cash) < price
		row.add_child(cash)
		var mort := W.button(App.t("ui.buy_mortgage", {"v": Fmt.money(price * 0.2)}), func(): ui.show_result(App.sim.command("buy_property", [id, true])), 76, 18)
		mort.disabled = float(p.finance.cash) < price * 0.2 or int(p.age) < 18
		mort.custom_minimum_size.x = 210
		mort.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(mort)
		_box.add_child(row)


func _possessions(sim: LifeSimulation, p: Dictionary) -> void:
	_box.add_child(W.section(App.t("ui.possessions")))
	for i in p.finance.possessions.size():
		var item: Dictionary = p.finance.possessions[i]
		var row := W.hbox(8)
		row.add_child(W.label("%s · %s" % [App.t("poss." + item.id), Fmt.money(float(item.value))], UiTheme.FONT_S, UiTheme.TEXT, true))
		var sell := W.button(App.t("ui.sell"), func(): ui.show_result(App.sim.command("sell_possession", [i])), 64, 18)
		sell.custom_minimum_size.x = 150
		sell.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(sell)
		_box.add_child(W.card(row))
	var flow := W.grid(2, 6)
	for id in App.data.table("possessions"):
		var def: Dictionary = App.data.get_def("possessions", id)
		if not sim.cond.check_all(def.get("conditions", []), {}):
			continue
		var price := sim.finance.possession_price(p, id)
		var lic_ok := sim.finance.license_ok(p, def)
		var label := "%s\n%s" % [App.t("poss." + id), Fmt.money(price)]
		if not lic_ok:
			label = "%s\n%s" % [App.t("poss." + id), App.t("license.required_" + def.license)]
		var b := W.button(label, func(): ui.show_result(App.sim.command("buy_possession", [id])), 76, 18)
		b.disabled = float(p.finance.cash) < price or not lic_ok
		flow.add_child(b)
	_box.add_child(flow)


func _markets(sim: LifeSimulation, p: Dictionary) -> void:
	_box.add_child(W.section(App.t("ui.investments")))
	for asset in App.data.bal("markets.assets", []):
		var m: Dictionary = sim.state.data.world.markets.get(asset.id, {})
		var price := float(m.get("price", 0))
		var change := price / maxf(float(m.get("last", price)), 0.0001) - 1.0
		var units := float(p.finance.investments.get(asset.id, 0.0))
		var card := W.vbox(6)
		var head := W.hbox(8)
		head.add_child(W.label(App.t("asset." + asset.id), UiTheme.FONT_M, UiTheme.TEXT, true))
		head.add_child(W.label("%s %s" % [Fmt.money(price), ("▲" if change >= 0 else "▼") + Fmt.pct(absf(change))], UiTheme.FONT_S, UiTheme.GOOD if change >= 0 else UiTheme.BAD))
		card.add_child(head)
		if units > 0.0:
			card.add_child(W.label(App.t("ui.holding", {"v": Fmt.money(units * price)}), UiTheme.FONT_S, UiTheme.GOLD))
		var row := W.hbox(8)
		for frac in [0.1, 0.5]:
			var amount := floorf(float(p.finance.cash) * frac)
			var b := W.button(App.t("ui.invest_amount", {"v": Fmt.money(amount)}), func(): ui.show_result(App.sim.command("invest", [asset.id, amount])), 68, 18)
			b.disabled = amount < 10.0
			row.add_child(b)
		if units > 0.0:
			row.add_child(W.button(App.t("ui.sell_all"), func(): ui.show_result(App.sim.command("sell_investment", [asset.id])), 68, 18))
		card.add_child(row)
		_box.add_child(W.card(card))


func _migration(sim: LifeSimulation, p: Dictionary) -> void:
	if int(p.age) < 18:
		return
	_box.add_child(W.section(App.t("ui.migration")))
	_box.add_child(W.label(App.t("ui.migration_hint"), 18, UiTheme.TEXT_DIM, true))
	for id in App.data.table("countries"):
		if id == p.country:
			continue
		var def: Dictionary = App.data.get_def("countries", id)
		var text := "%s · %s\n%s" % [App.t("country." + id), Fmt.money(sim.finance.emigration_cost(p, id)),
			App.t("ui.country_line", {"s": Fmt.pct(float(def.salary_mult)), "t": Fmt.pct(float(def.tax)), "c": Fmt.pct(float(def.cost_of_living)), "r": Fmt.pct(float(def.get("rift", 1.0)))})]
		var b := W.button(text, func(): ui.show_result(App.sim.command("emigrate", [id])), 84, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_box.add_child(b)


func _will(sim: LifeSimulation, p: Dictionary) -> void:
	if int(p.age) < 18:
		return
	_box.add_child(W.section(App.t("ui.will")))
	var mode: String = p.get("will", {}).get("mode", "equal")
	var row := W.grid(2, 6)
	for m in ["equal", "spouse", "favorite", "charity"]:
		var b := W.tinted_button(App.t("will." + m), func(): App.sim.command("set_will", [m, _first_child(sim, p)]), UiTheme.SYSTEM if mode == m else UiTheme.PANEL, 64)
		b.add_theme_font_size_override("font_size", 18)
		row.add_child(b)
	_box.add_child(row)
	if mode == "favorite":
		var kids := W.flow(6)
		for cid in sim.relations.all_with_role(p, "child"):
			var fav: bool = p.will.get("favorite", "") == cid
			var kb := W.tinted_button(sim.state.npc(cid).first_name, func(): App.sim.command("set_will", ["favorite", cid]), UiTheme.GOLD.darkened(0.5) if fav else UiTheme.PANEL, 60)
			kb.size_flags_horizontal = Control.SIZE_FILL
			kb.custom_minimum_size.x = 150
			kids.add_child(kb)
		_box.add_child(kids)


func _first_child(sim: LifeSimulation, p: Dictionary) -> String:
	var kids := sim.relations.all_with_role(p, "child")
	return kids[0] if not kids.is_empty() else ""
