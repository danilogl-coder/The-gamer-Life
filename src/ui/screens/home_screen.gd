extends VBoxContainer
## VIDA — the main screen: who you are right now, the life timeline, quick
## repeat of recent actions and the big "+1 YEAR" button.

var ui
var _header: VBoxContainer
var _timeline: VBoxContainer
var _scroll: ScrollContainer
var _quick: HBoxContainer
var _age_btn: Button
var _press_time := 0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_header = W.vbox(8)
	add_child(_header)
	_timeline = W.vbox(4)
	_scroll = W.scroll(_timeline)
	var tl_card := W.card(_scroll, UiTheme.BG2)
	tl_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tl_card)
	_quick = W.hbox(8)
	add_child(_quick)
	_age_btn = W.tinted_button("", _advance, Color("b8860b"), 118)
	_age_btn.add_theme_font_size_override("font_size", UiTheme.FONT_XL)
	add_child(_age_btn)


func refresh() -> void:
	var sim: LifeSimulation = App.sim
	var p := sim.player()
	_render_header(sim, p)
	_render_timeline(sim)
	_render_quick(sim, p)
	var free := sim.activities.free_slots(p)
	_age_btn.text = App.t("ui.age_up") + "   ⏱ %d/%d" % [free, int(p.time.slots)]
	_age_btn.disabled = sim.has_pending_events() or sim.is_dead()


func _render_header(sim: LifeSimulation, p: Dictionary) -> void:
	W.clear(_header)
	var row := W.hbox(14)
	row.add_child(W.portrait(p, 4))
	var info := W.vbox(4)
	info.add_child(W.label("%s %s" % [p.first_name, p.last_name], UiTheme.FONT_L, UiTheme.TEXT, true))
	var age_label := W.label(_subtitle(sim, p), UiTheme.FONT_S, UiTheme.TEXT_DIM, true)
	age_label.mouse_filter = Control.MOUSE_FILTER_STOP
	age_label.gui_input.connect(_on_age_input)
	info.add_child(age_label)
	var chips := W.flow(6)
	chips.add_child(W.chip("Lv. %d" % int(p.gamer.level), UiTheme.GOLD))
	chips.add_child(W.chip(App.t("rank.%d" % int(p.gamer.get("rank", 0))), UiTheme.SYSTEM_EDGE))
	if p.gamer.title != "":
		chips.add_child(W.chip("「%s」" % App.t("title." + p.gamer.title), UiTheme.PURPLE))
	if int(p.gamer.stat_points) > 0:
		chips.add_child(W.chip(App.t("ui.points_available", {"n": int(p.gamer.stat_points)}), UiTheme.GOOD))
	info.add_child(chips)
	info.add_child(W.bar(float(p.gamer.hp), sim.gamer.max_hp(p), UiTheme.HP, "HP %s/%s" % [Fmt.num(p.gamer.hp), Fmt.num(sim.gamer.max_hp(p))], 24))
	info.add_child(W.bar(float(p.gamer.mp), sim.gamer.max_mp(p), UiTheme.MP, "MP %s/%s" % [Fmt.num(p.gamer.mp), Fmt.num(sim.gamer.max_mp(p))], 24))
	row.add_child(info)
	var card := W.system_card(W.vbox(8))
	card.get_child(0).add_child(row)
	var money := W.hbox(10)
	money.add_child(W.icon("coin", UiTheme.GOLD, 3))
	money.add_child(W.label(Fmt.money(float(p.finance.cash)), UiTheme.FONT_M, UiTheme.GOLD))
	if float(p.finance.get("debt", 0)) > 0:
		money.add_child(W.label(App.t("ui.debt_short", {"v": Fmt.money(float(p.finance.debt))}), UiTheme.FONT_S, UiTheme.BAD))
	money.add_child(W.icon("clock", UiTheme.SYSTEM_EDGE, 3))
	money.add_child(W.label(App.t("ui.free_time", {"n": sim.activities.free_slots(p), "max": int(p.time.slots)}), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	card.get_child(0).add_child(money)
	var bars := W.grid(2, 8)
	for a in ["health", "happiness", "stress", "looks"]:
		var col := W.vbox(0)
		col.add_child(W.label(App.t("attr." + a), 17, UiTheme.TEXT_DIM))
		var v := float(p.attrs[a])
		var color := UiTheme.GOOD if v >= 60 else (UiTheme.WARN if v >= 30 else UiTheme.BAD)
		if a == "stress":
			color = UiTheme.BAD if v >= 60 else (UiTheme.WARN if v >= 30 else UiTheme.GOOD)
		col.add_child(W.bar(v, 100, color, "%d" % int(v), 20))
		bars.add_child(col)
	card.get_child(0).add_child(bars)
	_header.add_child(card)


func _subtitle(sim: LifeSimulation, p: Dictionary) -> String:
	var occ := App.t("ui.baby") if int(p.age) < 3 else App.t("ui.unemployed")
	if sim.crime.in_prison(p):
		occ = App.t("ui.prisoner", {"n": int(p.criminal.prison.years_left)})
	elif p.career.job != "":
		occ = "%s %s" % [App.t("job." + p.career.job), App.t("joblevel.%d" % int(p.career.level))]
	elif p.education.stage != "":
		occ = App.t("ui.student_of", {"school": App.t("edu." + p.education.stage)})
	elif int(p.age) >= 60 and float(p.career.get("pension", 0)) > 0:
		occ = App.t("ui.retired")
	return App.t("ui.age_line", {"age": p.age, "occ": occ, "country": App.t("country." + p.country)})


func _render_timeline(sim: LifeSimulation) -> void:
	W.clear(_timeline)
	var entries: Array = sim.state.data.timeline
	var start := maxi(0, entries.size() - 80)
	var last_age := -1
	for i in range(start, entries.size()):
		var e: Dictionary = entries[i]
		if int(e.age) != last_age:
			last_age = int(e.age)
			var h := W.label(App.t("ui.timeline_age", {"age": last_age, "year": e.year}), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE)
			_timeline.add_child(W.spacer(4))
			_timeline.add_child(h)
		var color := UiTheme.TEXT
		match e.get("kind", "info"):
			"major": color = UiTheme.GOLD
			"system": color = UiTheme.SYSTEM_EDGE
			"warning": color = UiTheme.WARN
			"world": color = UiTheme.PURPLE
		_timeline.add_child(W.label("• " + App.tr_entry(e), UiTheme.FONT_S, color, true))
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _render_quick(sim: LifeSimulation, p: Dictionary) -> void:
	W.clear(_quick)
	var ids: Array = p.get("favorites", []).duplicate()
	for id in p.get("recent_actions", []):
		if not ids.has(id):
			ids.append(id)
	for id in ids.slice(0, 3):
		var def: Dictionary = App.data.get_def("activities", id)
		if def.is_empty() or def.get("special", "") == "dungeon":
			continue
		var b := W.button(App.t("act." + id), _quick_do.bind(id), 72, UiTheme.FONT_S)
		b.disabled = sim.activities.block_reason(p, def) != ""
		_quick.add_child(b)


func _quick_do(id: String) -> void:
	ui.show_result(App.sim.do_activity(id))


func _advance() -> void:
	var r: Dictionary = App.sim.advance_year()
	if not r.ok:
		ui.show_result(r)


func _on_age_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed:
			_press_time = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _press_time > 1200:
			ui.open_debug()
