extends Control
## MUNDO — full-screen view of the world that lives with or without you:
## the yearly newspaper, your city and its places, the government (and your
## vote), technology eras, celebrities and the sports league.
## Big type, big touch targets, cards instead of tiny lines.

signal closed

const TABS := [
	["news", "news", Color("ffcf4d")],
	["city", "city", Color("6cd26a")],
	["government", "ballot", Color("5fd8ff")],
	["tech", "chip", Color("b07cff")],
	["celebs", "star", Color("ff8fd0")],
	["league", "trophy", Color("ffa84d")],
]

var _tab := "news"
var _body: VBoxContainer
var _scroll: ScrollContainer
var _tab_buttons := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var col := W.vbox(14)
	margin.add_child(col)
	col.add_child(_header())
	col.add_child(_tabs())
	_body = W.vbox(14)
	_scroll = W.scroll(_body)
	col.add_child(_scroll)
	_render()


func _header() -> Control:
	var sim: LifeSimulation = App.sim
	var row := W.hbox(14)
	var globe := W.icon("globe", UiTheme.SYSTEM_EDGE, 6)
	globe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(globe)
	var titles := W.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(W.label(App.t("ui.world").to_upper(), UiTheme.FONT_XL, UiTheme.TEXT))
	titles.add_child(W.label("%s · %d" % [sim.society.city().name, int(sim.state.data.world_year)], UiTheme.FONT_M, UiTheme.SYSTEM_EDGE, true))
	row.add_child(titles)
	var x := W.tinted_button("✕", close, UiTheme.PANEL_HI, 96)
	x.custom_minimum_size = Vector2(96, 96)
	x.size_flags_horizontal = Control.SIZE_SHRINK_END
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.add_theme_font_size_override("font_size", UiTheme.FONT_XL)
	row.add_child(x)
	return row


func _tabs() -> Control:
	var grid := W.grid(3, 10)
	for t in TABS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 104)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_select.bind(t[0]))
		var inner := W.vbox(4)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var ic := W.icon(t[1], t[2], 4)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		inner.add_child(ic)
		var lab := W.label(App.t("ui." + t[0]), UiTheme.FONT_S, UiTheme.TEXT)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(lab)
		b.add_child(inner)
		_tab_buttons[t[0]] = b
		grid.add_child(b)
	return grid


func _select(t: String) -> void:
	_tab = t
	_render()


func close() -> void:
	closed.emit()
	queue_free()


func _render() -> void:
	for id in _tab_buttons:
		_tab_buttons[id].modulate = Color.WHITE if id == _tab else Color(1, 1, 1, 0.55)
	W.clear(_body)
	_scroll.scroll_vertical = 0
	match _tab:
		"news": _news()
		"city": _city()
		"government": _government()
		"tech": _tech()
		"celebs": _celebs()
		"league": _league()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _title(text: String, color: Color = UiTheme.GOLD) -> Label:
	return W.label(text.to_upper(), UiTheme.FONT_L, color, true)


## A card with a colored stripe on the left (tone of the news, etc.).
func _stripe_card(content: Control, color: Color) -> Control:
	var row := W.hbox(12)
	var stripe := ColorRect.new()
	stripe.color = color
	stripe.custom_minimum_size = Vector2(8, 0)
	row.add_child(stripe)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	return W.card(row, UiTheme.PANEL)


## Big number tile: label, value and a thick bar.
func _stat_tile(label: String, value: float, color: Color, invert := false) -> Control:
	var box := W.vbox(6)
	var top := W.hbox(8)
	var l := W.label(label, UiTheme.FONT_M, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	top.add_child(W.label("%d" % int(value), UiTheme.FONT_XL, color))
	box.add_child(top)
	box.add_child(W.bar(value, 100, color, "", 30))
	var hint := ""
	if invert:
		hint = App.t("ui.level_high") if value >= 60 else (App.t("ui.level_mid") if value >= 30 else App.t("ui.level_low"))
	else:
		hint = App.t("ui.level_high") if value >= 65 else (App.t("ui.level_mid") if value >= 35 else App.t("ui.level_low"))
	box.add_child(W.label(hint, UiTheme.FONT_S, UiTheme.TEXT_DIM))
	return W.card(box, UiTheme.PANEL)


## Deterministic pixel face for people who are not simulated characters.
func _face(id: String, sex: String, age: int, alive := true, happy := 70.0) -> Dictionary:
	var h := absi(hash(id))
	return {"sex": sex, "age": age, "alive": alive, "attrs": {"happiness": happy},
		"look": {"skin": h % 6, "hair": (h / 6) % 8, "style": (h / 48) % 6, "eyes": (h / 288) % 5, "bg": (h / 1440) % 6}}


func _empty(text: String) -> void:
	var l := W.label(text, UiTheme.FONT_M, UiTheme.TEXT_DIM, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(W.spacer(40))
	_body.add_child(l)


# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------

func _news() -> void:
	var list: Array = App.sim.society.recent_news(3)
	if list.is_empty():
		_empty(App.t("ui.no_news"))
		return
	# Front page: the latest headline in big type.
	var top: Dictionary = list[-1]
	var front := W.vbox(8)
	front.add_child(W.label(App.t("ui.headline"), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	front.add_child(W.label(App.tr_entry(top), UiTheme.FONT_L, UiTheme.TEXT, true))
	_body.add_child(W.system_card(front))
	var year := -1
	for i in range(list.size() - 2, -1, -1):
		var n: Dictionary = list[i]
		if int(n.y) != year:
			year = int(n.y)
			_body.add_child(_title(str(year), UiTheme.SYSTEM_EDGE))
		var color := UiTheme.TEXT_DIM
		match n.get("tone", ""):
			"good": color = UiTheme.GOOD
			"bad": color = UiTheme.BAD
		if n.get("scope", "") == "personal":
			color = UiTheme.GOLD
		var col := W.vbox(2)
		col.add_child(W.label(App.t("newsscope." + str(n.get("scope", "world"))), UiTheme.FONT_S, color))
		col.add_child(W.label(App.tr_entry(n), UiTheme.FONT_M, UiTheme.TEXT, true))
		_body.add_child(_stripe_card(col, color))


func _city() -> void:
	var c: Dictionary = App.sim.society.city()
	_body.add_child(_title(c.name))
	_body.add_child(_stat_tile(App.t("ui.prosperity"), float(c.prosperity), UiTheme.GOOD))
	_body.add_child(_stat_tile(App.t("ui.crime_rate"), float(c.crime), UiTheme.BAD, true))
	_body.add_child(_stat_tile(App.t("ui.pollution"), float(c.pollution), UiTheme.WARN, true))
	_body.add_child(_title(App.t("ui.places")))
	var p: Dictionary = App.sim.player()
	var grid := W.grid(2, 10)
	for pl in c.places:
		if not pl.open:
			continue
		var box := W.vbox(4)
		box.add_child(W.label(App.t("placetype." + str(pl.type)), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
		box.add_child(W.label(App.loc.t_ref(App.sim.society.place_name(pl)), UiTheme.FONT_M, UiTheme.TEXT, true))
		box.add_child(W.label("★".repeat(int(pl.q)) + "☆".repeat(5 - int(pl.q)), UiTheme.FONT_M, UiTheme.GOLD))
		var owner: String = pl.get("owner", "")
		if owner == p.id:
			box.add_child(W.chip(App.t("ui.yours"), UiTheme.GOOD, UiTheme.FONT_S))
		elif owner != "" and App.sim.state.has_npc(owner):
			box.add_child(W.label(App.t("ui.owner", {"name": App.sim.state.npc(owner).first_name}), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		var card := W.card(box, UiTheme.PANEL)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
	_body.add_child(grid)


func _government() -> void:
	var soc = App.sim.society
	var g: Dictionary = soc.gov()
	var p: Dictionary = App.sim.player()
	# Leader card
	var lead := W.hbox(16)
	if g.get("leader", "") == "player":
		lead.add_child(W.portrait(p, 5))
	else:
		var cel: Dictionary = soc.soc().celebs.get(g.get("leader", ""), {})
		if not cel.is_empty():
			lead.add_child(W.portrait(_face(cel.id, cel.sex, int(cel.age)), 5))
	var info := W.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(W.label(App.t("ui.leader"), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	info.add_child(W.label(soc.leader_name(g), UiTheme.FONT_L, UiTheme.TEXT, true))
	info.add_child(W.label(App.t("party." + str(g.party)), UiTheme.FONT_M, UiTheme.GOLD, true))
	lead.add_child(info)
	_body.add_child(W.system_card(lead))
	var appr_col := UiTheme.GOOD if float(g.approval) >= 55 else (UiTheme.WARN if float(g.approval) >= 35 else UiTheme.BAD)
	_body.add_child(_stat_tile(App.t("ui.approval"), float(g.approval), appr_col))
	var el := W.label(App.t("ui.next_election", {"y": int(g.next_election)}), UiTheme.FONT_M, UiTheme.TEXT)
	_body.add_child(W.card(el, UiTheme.PANEL))
	_body.add_child(_title(App.t("ui.policies")))
	var pol: Dictionary = g.policies
	var pol_box := W.vbox(10)
	pol_box.add_child(_policy_row(App.t("ui.pol_tax"), "%+d%%" % int(round(float(pol.tax) * 100)), UiTheme.WARN))
	pol_box.add_child(_policy_row(App.t("ui.pol_welfare"), "%d%%" % int(float(pol.welfare) * 100), UiTheme.GOOD))
	pol_box.add_child(_policy_row(App.t("ui.pol_police"), "%d%%" % int(float(pol.police) * 100), UiTheme.BAD))
	pol_box.add_child(_policy_row(App.t("ui.pol_rift"), App.t("rift." + str(pol.rift)), UiTheme.PURPLE))
	_body.add_child(W.card(pol_box, UiTheme.PANEL))
	if int(p.age) < 18:
		return
	_body.add_child(_title(App.t("ui.vote")))
	if p.get("vote", "") != "":
		_body.add_child(W.label(App.t("ui.your_vote", {"party": App.t("party." + str(p.vote))}), UiTheme.FONT_M, UiTheme.GOOD, true))
	var ids: Array = App.data.table("parties").keys()
	ids.sort()
	for id in ids:
		var def: Dictionary = App.data.get_def("parties", id)
		if def.has("era") and not soc.has_era(def.era):
			continue
		var ideol := float(def.get("ideology", 0))
		var lean := "politics.progressive" if ideol < -35 else ("politics.conservative" if ideol > 35 else "politics.moderate")
		var text := "%s  ·  %s" % [App.t("party." + id), App.t(lean)]
		var mine: bool = p.get("vote", "") == id
		var b := W.tinted_button(("✔ " if mine else "") + text, _vote.bind(id), UiTheme.SYSTEM if mine else UiTheme.PANEL_HI, 88)
		b.add_theme_font_size_override("font_size", UiTheme.FONT_M)
		_body.add_child(b)


func _policy_row(label: String, value: String, color: Color) -> Control:
	var row := W.hbox(8)
	var l := W.label(label, UiTheme.FONT_M, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(W.label(value, UiTheme.FONT_M, color))
	return row


func _vote(party: String) -> void:
	App.sim.command("vote", [party])
	_render()


func _tech() -> void:
	var t: Dictionary = App.sim.society.soc().tech
	_body.add_child(_stat_tile(App.t("ui.tech"), minf(float(t.level), 100.0), UiTheme.PURPLE))
	var ids: Array = App.data.table("tech_eras").keys()
	ids.sort_custom(func(a, b): return float(App.data.get_def("tech_eras", a).at) < float(App.data.get_def("tech_eras", b).at))
	for id in ids:
		var has: bool = t.eras.has(id)
		var col := W.vbox(4)
		var head := W.hbox(10)
		var chip := W.icon("chip", UiTheme.PURPLE if has else UiTheme.TEXT_DIM, 3)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(chip)
		var name := W.label(App.t("tech." + id), UiTheme.FONT_M, UiTheme.TEXT if has else UiTheme.TEXT_DIM, true)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name)
		head.add_child(W.label("✔" if has else "%d" % int(App.data.get_def("tech_eras", id).at), UiTheme.FONT_M, UiTheme.GOOD if has else UiTheme.TEXT_DIM))
		col.add_child(head)
		if has:
			col.add_child(W.label(App.t("news.tech." + id), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		_body.add_child(_stripe_card(col, UiTheme.PURPLE if has else UiTheme.PANEL_HI))


func _celebs() -> void:
	var soc = App.sim.society
	var ids: Array = soc.soc().celebs.keys()
	ids.sort_custom(func(a, b): return float(soc.soc().celebs[a].fame) > float(soc.soc().celebs[b].fame))
	for id in ids:
		var c: Dictionary = soc.soc().celebs[id]
		if not c.alive:
			continue
		var row := W.hbox(14)
		row.add_child(W.portrait(_face(c.id, c.sex, int(c.age), true, 75.0 if c.status == "active" else 35.0), 3))
		var col := W.vbox(4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(W.label(soc.celeb_name(c), UiTheme.FONT_M, UiTheme.TEXT, true))
		var sub := App.t("celebfield.%s.%s" % [c.field, c.sex]) + " · " + App.t("ui.years_old", {"n": int(c.age)})
		col.add_child(W.label(sub, UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		if c.status != "active":
			col.add_child(W.chip(App.t("celebstatus." + str(c.status)), UiTheme.BAD if c.status == "jailed" else UiTheme.TEXT_DIM, UiTheme.FONT_S))
		col.add_child(W.bar(float(c.fame), 100, UiTheme.GOLD, App.t("ui.fame") + " %d" % int(c.fame), 24))
		row.add_child(col)
		_body.add_child(W.card(row, UiTheme.PANEL))


func _league() -> void:
	var n: Dictionary = App.sim.society.nation()
	var teams: Array = n.teams.duplicate()
	teams.sort_custom(func(a, b): return int(a.titles) > int(b.titles))
	var pos := 1
	for t in teams:
		var champ: bool = int(n.champion) >= 0 and n.teams[int(n.champion)] == t
		var row := W.hbox(14)
		row.add_child(W.label("%d." % pos, UiTheme.FONT_L, UiTheme.GOLD if champ else UiTheme.TEXT_DIM))
		if champ:
			var tr := W.icon("trophy", UiTheme.GOLD, 4)
			tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tr)
		var col := W.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(W.label(App.loc.t_ref(App.sim.society.team_name(t)), UiTheme.FONT_M, UiTheme.TEXT, true))
		col.add_child(W.label(App.t("ui.titles_n", {"n": int(t.titles)}) + ("  · " + App.t("ui.champion") if champ else ""), UiTheme.FONT_S, UiTheme.GOLD if champ else UiTheme.TEXT_DIM))
		row.add_child(col)
		_body.add_child(W.system_card(row) if champ else W.card(row, UiTheme.PANEL))
		pos += 1
