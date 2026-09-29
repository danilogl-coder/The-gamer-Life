extends VBoxContainer
## ATIVIDADES — what to do with this year's free time. Category chips, then
## big buttons. Two taps for anything (category → action), one tap for
## favourites. Locked actions stay visible with the reason (goals!).

const CATS := ["system", "mind", "body", "leisure", "love", "work", "health", "crime", "prison"]

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
	if def.get("special", "") == "dungeon":
		_open_dungeons()
		return
	ui.show_result(App.sim.do_activity(id))


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
