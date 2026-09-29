extends VBoxContainer
## ATIVIDADES — what to do with this year's free time. Category chips, then
## big buttons. Two taps for anything (category → action), one tap for
## favourites. Locked actions stay visible with the reason (goals!).

const CATS := ["system", "mind", "body", "leisure", "love", "beauty", "fertility", "work", "health", "crime", "prison"]
const EscapeGame := preload("res://src/ui/minigames/escape_game.gd")
const BlackjackGame := preload("res://src/ui/minigames/blackjack_game.gd")

var ui
var _cat := "system"
var _chips: HFlowContainer
var _list: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_chips = W.flow(6)
	add_child(_chips)
	_list = W.vbox(8)
	add_child(W.scroll(_list))


func refresh() -> void:
	var sim: LifeSimulation = App.sim
	var p := sim.player()
	if sim.crime.in_prison(p):
		_cat = "prison"
	elif _cat == "prison":
		_cat = "system"
	W.clear(_chips)
	for c in CATS:
		if sim.activities.list(c).is_empty() and not (c == "health" and not p.health.conditions.is_empty()):
			continue
		var b := W.tinted_button(App.t("actcat." + c), func(): _cat = c; refresh(), UiTheme.SYSTEM if c == _cat else UiTheme.PANEL, 64)
		b.size_flags_horizontal = Control.SIZE_FILL
		b.custom_minimum_size.x = 120
		b.add_theme_font_size_override("font_size", 18)
		_chips.add_child(b)
	W.clear(_list)
	_list.add_child(W.label(App.t("ui.free_time", {"n": sim.activities.free_slots(p), "max": int(p.time.slots)}), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	for entry in sim.activities.list(_cat):
		_list.add_child(_activity_row(sim, p, entry))
	if _cat == "health":
		for cid in p.health.conditions:
			var def: Dictionary = App.data.get_def("diseases", cid)
			var cost := float(def.get("treat_cost", 2000)) * float(sim.finance.country(p).get("cost_of_living", 1.0))
			var b := W.tinted_button(App.t("ui.treat", {"cond": App.t("disease." + cid), "cost": Fmt.money(cost)}), func(): ui.show_result(App.sim.command("treat", [cid])), Color("7a2d3a"), 84)
			_list.add_child(b)


func _activity_row(sim: LifeSimulation, p: Dictionary, entry: Dictionary) -> Control:
	var id: String = entry.id
	var def: Dictionary = App.data.get_def("activities", id)
	var row := W.hbox(6)
	var cost_bits: Array = []
	if int(def.get("time", 1)) > 0:
		cost_bits.append("⏱%d" % int(def.get("time", 1)))
	var cost := sim.activities.cost_of(p, def)
	if cost > 0.0:
		cost_bits.append(Fmt.money(cost))
	if float(def.get("mp", 0)) > 0:
		cost_bits.append("MP %d" % int(def.mp))
	var text := App.t("act." + id)
	if not cost_bits.is_empty():
		text += "   " + " · ".join(cost_bits)
	if entry.locked != "":
		text += "\n" + App.t(entry.locked)
	var b := W.button(text, _perform.bind(id), 88)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = entry.locked != ""
	row.add_child(b)
	var fav: bool = p.favorites.has(id)
	var star := W.button("★" if fav else "☆", func(): App.sim.command("favorite", [id]), 88, UiTheme.FONT_L)
	star.custom_minimum_size.x = 76
	star.size_flags_horizontal = Control.SIZE_SHRINK_END
	star.add_theme_color_override("font_color", UiTheme.GOLD if fav else UiTheme.TEXT_DIM)
	row.add_child(star)
	return row


func _perform(id: String) -> void:
	var def: Dictionary = App.data.get_def("activities", id)
	match def.get("special", ""):
		"dungeon":
			_open_dungeons()
			return
		"dating":
			var r: Dictionary = App.sim.do_activity(id)
			if r.get("ok", false):
				_open_dating(r.get("dating", []))
			else:
				ui.show_result(r)
			return
		"escape":
			var game = EscapeGame.new()
			game.setup(Time.get_ticks_usec())
			var sheet = ui.open_sheet(App.t("act.prison_escape"), game, true)
			game.finished.connect(func(ok): sheet.close(); ui.show_result(App.sim.do_activity(id, {"success": ok})))
			return
		"blackjack":
			var bj = BlackjackGame.new()
			bj.setup(Time.get_ticks_usec(), minf(500.0, float(App.sim.player().finance.cash)))
			var sheet2 = ui.open_sheet(App.t("act.blackjack"), bj, true)
			bj.finished.connect(func(won, bet): sheet2.close(); ui.show_result(App.sim.do_activity(id, {"won": won, "bet": bet})))
			return
	ui.show_result(App.sim.do_activity(id))


## Dating app: three profiles; the System shows what it can read about them.
func _open_dating(ids: Array) -> void:
	var sim: LifeSimulation = App.sim
	var box := W.vbox(10)
	if ids.is_empty():
		box.add_child(W.label(App.t("love.no_profiles"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	for id in ids:
		var npc: Dictionary = sim.state.npc(id)
		var row := W.hbox(12)
		row.add_child(W.portrait(npc, 3))
		var col := W.vbox(3)
		col.add_child(W.label("%s, %d" % [npc.first_name, int(npc.age)], UiTheme.FONT_M, UiTheme.TEXT))
		var job: String = npc.career.get("job", "")
		col.add_child(W.label(App.t("job." + job) if job != "" else App.t("ui.unemployed"), 17, UiTheme.TEXT_DIM))
		col.add_child(W.bar(float(npc.attrs.looks), 100, UiTheme.PURPLE, App.t("attr.looks"), 16))
		var tr := W.flow(4)
		for t in npc.traits.slice(0, 2):
			tr.add_child(W.chip(App.t("trait." + t), UiTheme.TEXT_DIM, 15))
		tr.add_child(W.chip(App.t("zodiac." + CharacterFactory.zodiac_of(npc)), UiTheme.SYSTEM_EDGE, 15))
		col.add_child(tr)
		col.add_child(W.label(App.t("ui.compat", {"n": int(sim.relations.compatibility(npc))}), 17, UiTheme.GOLD))
		row.add_child(col)
		box.add_child(row)
		box.add_child(W.tinted_button(App.t("love.swipe_right", {"name": npc.first_name}), func(): ui.close_overlays(); ui.show_result(App.sim.command("dating_pick", [id])), UiTheme.PURPLE.darkened(0.4), 72))
	ui.open_sheet(App.t("act.dating_app"), box, true)


func _open_dungeons() -> void:
	var sim: LifeSimulation = App.sim
	var p := sim.player()
	var box := W.vbox(8)
	box.add_child(W.label(App.t("ui.dungeon_hint"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	var colors := [UiTheme.TEXT_DIM, UiTheme.GOOD, UiTheme.WARN, UiTheme.BAD]
	for d in sim.dungeons.available(p):
		var def: Dictionary = App.data.get_def("dungeons", d.id)
		var text := "%s   Lv.%d+\n%s" % [App.t("dng." + d.id), int(def.min_level), App.t("dng.danger%d" % int(d.danger))]
		var b := W.button(text, func(): ui.close_overlays(); ui.show_result(App.sim.do_activity("dungeon", {"dungeon": d.id})), 96)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", colors[int(d.danger)])
		box.add_child(b)
	ui.open_sheet(App.t("act.dungeon"), box, true)
