extends VBoxContainer
## MUNDO — the world that lives with or without you: the yearly newspaper,
## your city and its places, the government (and your vote), technology
## eras, celebrities and the sports league.

const TABS := ["news", "city", "government", "tech", "celebs", "league"]

var _tab := "news"
var _body: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var bar := W.grid(3, 6)
	for t in TABS:
		var b := W.button(App.t("ui." + t), _select.bind(t), 64, UiTheme.FONT_S)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(b)
	add_child(bar)
	_body = W.vbox(8)
	add_child(_body)
	_render()


func _select(t: String) -> void:
	_tab = t
	_render()


func _render() -> void:
	W.clear(_body)
	match _tab:
		"news": _news()
		"city": _city()
		"government": _government()
		"tech": _tech()
		"celebs": _celebs()
		"league": _league()


func _news() -> void:
	var list: Array = App.sim.society.recent_news(3)
	if list.is_empty():
		_body.add_child(W.label(App.t("ui.no_news"), UiTheme.FONT_S, UiTheme.TEXT_DIM))
		return
	var year := -1
	for i in range(list.size() - 1, -1, -1):
		var n: Dictionary = list[i]
		if int(n.y) != year:
			year = int(n.y)
			_body.add_child(W.section(str(year)))
		var color := UiTheme.TEXT
		match n.get("tone", ""):
			"good": color = UiTheme.GOOD
			"bad": color = UiTheme.BAD
		if n.get("scope", "") == "personal":
			color = UiTheme.GOLD
		_body.add_child(W.label("• " + App.tr_entry(n), UiTheme.FONT_S, color, true))


func _city() -> void:
	var c: Dictionary = App.sim.society.city()
	_body.add_child(W.label(c.name, UiTheme.FONT_L, UiTheme.GOLD))
	_body.add_child(W.bar(float(c.prosperity), 100, UiTheme.GOOD, App.t("ui.prosperity") + " %d" % int(c.prosperity), 22))
	_body.add_child(W.bar(float(c.crime), 100, UiTheme.BAD, App.t("ui.crime_rate") + " %d" % int(c.crime), 22))
	_body.add_child(W.bar(float(c.pollution), 100, UiTheme.WARN, App.t("ui.pollution") + " %d" % int(c.pollution), 22))
	_body.add_child(W.section(App.t("ui.places")))
	var p: Dictionary = App.sim.player()
	for pl in c.places:
		if not pl.open:
			continue
		var name := App.loc.t_ref(App.sim.society.place_name(pl))
		var extra := "  " + "★".repeat(int(pl.q))
		var owner: String = pl.get("owner", "")
		if owner == p.id:
			extra += "  (" + App.t("ui.yours") + ")"
		elif owner != "" and App.sim.state.has_npc(owner):
			extra += "  (" + App.t("ui.owner", {"name": App.sim.state.npc(owner).first_name}) + ")"
		_body.add_child(W.label(name + extra, UiTheme.FONT_S, UiTheme.TEXT, true))


func _government() -> void:
	var soc = App.sim.society
	var g: Dictionary = soc.gov()
	_body.add_child(W.label(App.t("ui.party") + ": " + App.t("party." + str(g.party)), UiTheme.FONT_M, UiTheme.GOLD, true))
	_body.add_child(W.label(App.t("ui.leader") + ": " + soc.leader_name(g), UiTheme.FONT_S, UiTheme.TEXT))
	_body.add_child(W.bar(float(g.approval), 100, UiTheme.SYSTEM_EDGE, App.t("ui.approval") + " %d%%" % int(g.approval), 22))
	_body.add_child(W.label(App.t("ui.next_election", {"y": int(g.next_election)}), UiTheme.FONT_S, UiTheme.TEXT_DIM))
	_body.add_child(W.section(App.t("ui.policies")))
	var pol: Dictionary = g.policies
	_body.add_child(W.label("%s: %+d%%" % [App.t("ui.pol_tax"), int(round(float(pol.tax) * 100))], UiTheme.FONT_S, UiTheme.TEXT))
	_body.add_child(W.bar(float(pol.welfare) * 100, 100, UiTheme.GOOD, App.t("ui.pol_welfare"), 18))
	_body.add_child(W.bar(float(pol.police) * 100, 100, UiTheme.BAD, App.t("ui.pol_police"), 18))
	_body.add_child(W.label(App.t("ui.pol_rift") + ": " + App.t("rift." + str(pol.rift)), UiTheme.FONT_S, UiTheme.PURPLE))
	var p: Dictionary = App.sim.player()
	if int(p.age) >= 18:
		_body.add_child(W.section(App.t("ui.vote")))
		if p.get("vote", "") != "":
			_body.add_child(W.label(App.t("ui.your_vote", {"party": App.t("party." + str(p.vote))}), UiTheme.FONT_S, UiTheme.GOOD))
		var ids: Array = App.data.table("parties").keys()
		ids.sort()
		for id in ids:
			var def: Dictionary = App.data.get_def("parties", id)
			if def.has("era") and not soc.has_era(def.era):
				continue
			_body.add_child(W.button(App.t("party." + id), _vote.bind(id), 64, UiTheme.FONT_S))


func _vote(party: String) -> void:
	App.sim.command("vote", [party])
	_render()


func _tech() -> void:
	var t: Dictionary = App.sim.society.soc().tech
	_body.add_child(W.label(App.t("ui.tech_level", {"n": int(t.level)}), UiTheme.FONT_M, UiTheme.SYSTEM_EDGE))
	var ids: Array = App.data.table("tech_eras").keys()
	ids.sort_custom(func(a, b): return float(App.data.get_def("tech_eras", a).at) < float(App.data.get_def("tech_eras", b).at))
	for id in ids:
		var has: bool = t.eras.has(id)
		var line := ("✔ " if has else "… ") + App.t("tech." + id)
		_body.add_child(W.label(line, UiTheme.FONT_S, UiTheme.GOOD if has else UiTheme.TEXT_DIM))
		if has:
			_body.add_child(W.label(App.t("news.tech." + id), 16, UiTheme.TEXT_DIM, true))


func _celebs() -> void:
	var soc = App.sim.society
	var ids: Array = soc.soc().celebs.keys()
	ids.sort_custom(func(a, b): return float(soc.soc().celebs[a].fame) > float(soc.soc().celebs[b].fame))
	for id in ids:
		var c: Dictionary = soc.soc().celebs[id]
		if not c.alive:
			continue
		var status := "" if c.status == "active" else " (" + App.t("celebstatus." + str(c.status)) + ")"
		_body.add_child(W.label("%s — %s%s" % [soc.celeb_name(c), App.t("celebfield.%s.%s" % [c.field, c.sex]), status], UiTheme.FONT_S, UiTheme.TEXT, true))
		_body.add_child(W.bar(float(c.fame), 100, UiTheme.GOLD, "", 10))


func _league() -> void:
	var n: Dictionary = App.sim.society.nation()
	var teams: Array = n.teams.duplicate()
	teams.sort_custom(func(a, b): return int(a.titles) > int(b.titles))
	for t in teams:
		var champ: bool = int(n.champion) >= 0 and n.teams[int(n.champion)] == t
		_body.add_child(W.label(("🏆 " if champ else "") + App.loc.t_ref(App.sim.society.team_name(t)) + " — " + App.t("ui.titles_n", {"n": int(t.titles)}), UiTheme.FONT_S, UiTheme.GOLD if champ else UiTheme.TEXT, true))
