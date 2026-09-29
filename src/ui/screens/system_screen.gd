extends VBoxContainer
## SISTEMA — the Gamer's windows: Status (stats & points), Skills, Quests,
## Titles, Inventory and Achievements.

const SUBTABS := ["status", "skills", "quests", "titles", "inventory", "achievements"]

var ui
var _sub := "status"
var _tabs: HFlowContainer
var _content: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_tabs = W.flow(6)
	add_child(_tabs)
	_content = W.vbox(10)
	add_child(W.scroll(_content))


func refresh() -> void:
	W.clear(_tabs)
	for s in SUBTABS:
		var b := W.tinted_button(App.t("sys.tab." + s), func(): _sub = s; refresh(), UiTheme.SYSTEM if s == _sub else UiTheme.PANEL, 64)
		b.size_flags_horizontal = Control.SIZE_FILL
		b.custom_minimum_size.x = 108
		b.add_theme_font_size_override("font_size", 18)
		_tabs.add_child(b)
	W.clear(_content)
	call("_render_" + _sub, App.sim, App.sim.player())


# ---------------------------------------------------------------- status
func _render_status(sim: LifeSimulation, p: Dictionary) -> void:
	var box := W.vbox(10)
	box.add_child(W.label("[ STATUS ]", UiTheme.FONT_L, UiTheme.SYSTEM_EDGE))
	box.add_child(W.label("%s  ·  Lv. %d  ·  %s" % [p.first_name, int(p.gamer.level), App.t("rank.%d" % int(p.gamer.get("rank", 0)))], UiTheme.FONT_M, UiTheme.TEXT, true))
	var need := sim.gamer.exp_to_next(int(p.gamer.level))
	box.add_child(W.bar(float(p.gamer.exp), need, UiTheme.EXP, "EXP %s / %s" % [Fmt.num(p.gamer.exp), Fmt.num(need)], 28))
	box.add_child(W.bar(float(p.gamer.hp), sim.gamer.max_hp(p), UiTheme.HP, "HP %s" % Fmt.num(sim.gamer.max_hp(p)), 24))
	box.add_child(W.bar(float(p.gamer.mp), sim.gamer.max_mp(p), UiTheme.MP, "MP %s" % Fmt.num(sim.gamer.max_mp(p)), 24))
	if p.gamer.title != "":
		box.add_child(W.label(App.t("ui.title_line", {"title": App.t("title." + p.gamer.title)}), UiTheme.FONT_S, UiTheme.PURPLE))
	var pts := int(p.gamer.stat_points)
	var pts_row := W.hbox(8)
	pts_row.add_child(W.label(App.t("ui.points_available", {"n": pts}), UiTheme.FONT_M, UiTheme.GOOD if pts > 0 else UiTheme.TEXT_DIM))
	if pts > 0:
		var auto := W.button(App.t("ui.auto"), func(): App.sim.command("auto_allocate"), 64, UiTheme.FONT_S)
		auto.size_flags_horizontal = Control.SIZE_SHRINK_END
		auto.custom_minimum_size.x = 140
		pts_row.add_child(auto)
	box.add_child(pts_row)
	for s in CharacterFactory.STAT_IDS:
		box.add_child(_stat_row(sim, p, s, pts))
	_content.add_child(W.system_card(box))
	# Hidden attributes discovered with Observe.
	var hid := W.vbox(4)
	hid.add_child(W.section(App.t("ui.hidden_attrs")))
	hid.add_child(W.label("%s: %s" % [App.t("ui.zodiac"), App.t("zodiac." + CharacterFactory.zodiac_of(p))], UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	if p.discovered.is_empty():
		hid.add_child(W.label(App.t("ui.hidden_none"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	for h in p.discovered:
		hid.add_child(W.label("%s: %d" % [App.t("hidden." + h), int(p.hidden[h])], UiTheme.FONT_S))
	var traits := W.flow()
	for t in p.traits:
		traits.add_child(W.chip(App.t("trait." + t), UiTheme.TEXT_DIM))
	hid.add_child(traits)
	_content.add_child(W.card(hid))
	var mods := sim.gamer.all_mods()
	if not mods.is_empty():
		var m := W.vbox(4)
		m.add_child(W.section(App.t("ui.active_bonuses")))
		m.add_child(W.label(Fmt.mods(mods), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		_content.add_child(W.card(m))


func _stat_row(sim: LifeSimulation, p: Dictionary, s: String, pts: int) -> Control:
	var row := W.hbox(8)
	var name := W.label(App.t("stat." + s), UiTheme.FONT_M, UiTheme.stat_color(s))
	name.custom_minimum_size.x = 70
	row.add_child(name)
	var base := float(p.gamer.stats[s])
	var eff := sim.gamer.effective_stat(p, s)
	var txt := Fmt.num(eff)
	if absf(eff - base) >= 1.0:
		txt += "  (%s %s)" % [Fmt.num(base), Fmt.signed(eff - base)]
	var val := W.label(txt, UiTheme.FONT_M, UiTheme.TEXT)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	var info := W.button("?", func(): ui.show_result({"ok": true, "key": "statdesc." + s, "params": {}}), 64, UiTheme.FONT_S)
	info.custom_minimum_size.x = 64
	info.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(info)
	if pts > 0:
		var plus := W.tinted_button("+", func(): App.sim.allocate_stat(s, 1), Color("2f7a3a"), 64)
		plus.custom_minimum_size.x = 80
		plus.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(plus)
		if pts >= 5:
			var plus5 := W.tinted_button("+5", func(): App.sim.allocate_stat(s, 5), Color("2f7a3a"), 64)
			plus5.custom_minimum_size.x = 80
			plus5.size_flags_horizontal = Control.SIZE_SHRINK_END
			row.add_child(plus5)
	return row


# ---------------------------------------------------------------- skills
func _render_skills(sim: LifeSimulation, p: Dictionary) -> void:
	var ids: Array = p.gamer.skills.keys()
	ids.sort_custom(func(a, b): return int(p.gamer.skills[a].lv) > int(p.gamer.skills[b].lv))
	if ids.is_empty():
		_content.add_child(W.label(App.t("ui.no_skills"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	for sid in ids:
		var def: Dictionary = App.data.get_def("skills", sid)
		var entry: Dictionary = p.gamer.skills[sid]
		var box := W.vbox(4)
		var head := W.hbox(8)
		head.add_child(W.label(App.t("skill." + sid), UiTheme.FONT_M, UiTheme.tier_color(def.get("tier", "common")), true))
		head.add_child(W.chip(App.t("tier." + def.get("tier", "common")), UiTheme.tier_color(def.get("tier", "common")), 16))
		box.add_child(head)
		var max_lv := int(def.get("max_level", 10))
		var lv := int(entry.lv)
		var lv_text := "Lv. %d / %d" % [lv, max_lv] if lv < max_lv else "Lv. MAX"
		box.add_child(W.bar(float(entry.xp), sim.skills.xp_needed(sid, lv) if lv < max_lv else 1.0, UiTheme.SYSTEM_EDGE, lv_text, 22))
		var desc := Fmt.mods(def.get("mods", {}), lv)
		var flat := Fmt.mods(def.get("mods_flat", {}))
		if flat != "":
			desc = flat if desc == "" else desc + ", " + flat
		if def.has("combat"):
			desc = App.t("ui.skill_power", {"p": Fmt.num(sim.skills.skill_power(p, sid)), "mp": int(def.combat.get("mp", 0))}) + ("  " + desc if desc != "" else "")
		if desc != "":
			box.add_child(W.label(desc, UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		if def.has("evolves_to"):
			box.add_child(W.label(App.t("ui.evolves_at_max"), 17, UiTheme.PURPLE))
		_content.add_child(W.card(box))


# ---------------------------------------------------------------- quests
func _render_quests(sim: LifeSimulation, p: Dictionary) -> void:
	var active: Dictionary = p.quests.active
	if active.is_empty():
		_content.add_child(W.label(App.t("ui.no_quests"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	for id in active:
		var box := W.vbox(6)
		box.add_child(W.label("[%s] %s" % [App.t("ui.quest"), App.t("quest.%s.title" % id)], UiTheme.FONT_M, UiTheme.SYSTEM_EDGE, true))
		box.add_child(W.label(App.t("quest.%s.desc" % id), UiTheme.FONT_S, UiTheme.TEXT, true))
		for o in sim.quests.progress(id):
			box.add_child(W.bar(o.cur, o.target, UiTheme.GOOD if o.done else UiTheme.GOLD, "%d / %d" % [o.cur, o.target], 22))
		box.add_child(W.label(App.t("ui.deadline", {"age": int(active[id].deadline)}), 17, UiTheme.WARN))
		_content.add_child(W.system_card(box))
	_content.add_child(W.label(App.t("ui.quests_done", {"n": p.quests.done.size(), "f": p.quests.failed.size()}), UiTheme.FONT_S, UiTheme.TEXT_DIM))


# ---------------------------------------------------------------- titles
func _render_titles(_sim: LifeSimulation, p: Dictionary) -> void:
	if p.gamer.titles.is_empty():
		_content.add_child(W.label(App.t("ui.no_titles"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	for tid in p.gamer.titles:
		var def: Dictionary = App.data.get_def("titles", tid)
		var equipped: bool = p.gamer.title == tid
		var passive: bool = def.get("passive", false)
		var txt := "「%s」\n%s" % [App.t("title." + tid), Fmt.mods(def.get("mods", {}))]
		if passive:
			txt += "  · " + App.t("ui.passive")
		elif equipped:
			txt += "  · " + App.t("ui.equipped")
		var b := W.tinted_button(txt, func(): App.sim.command("equip_title", [tid]), UiTheme.SYSTEM if equipped else UiTheme.PANEL, 90)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_content.add_child(b)


# ---------------------------------------------------------------- inventory
func _render_inventory(_sim: LifeSimulation, p: Dictionary) -> void:
	_content.add_child(W.section(App.t("ui.equipment")))
	for slot in ["weapon", "armor", "accessory"]:
		var item: String = p.gamer.equipment.get(slot, "")
		var row := W.hbox(8)
		row.add_child(W.label("%s: %s" % [App.t("slot." + slot), App.t("item." + item) if item != "" else "—"], UiTheme.FONT_S, UiTheme.TEXT, true))
		if item != "":
			var b := W.button(App.t("ui.unequip"), func(): App.sim.command("unequip", [slot]), 64, UiTheme.FONT_S)
			b.custom_minimum_size.x = 170
			b.size_flags_horizontal = Control.SIZE_SHRINK_END
			row.add_child(b)
		_content.add_child(row)
	_content.add_child(W.section(App.t("ui.items")))
	if p.gamer.inventory.is_empty():
		_content.add_child(W.label(App.t("ui.empty_inventory"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	for id in p.gamer.inventory:
		var def: Dictionary = App.data.get_def("items", id)
		var box := W.vbox(6)
		box.add_child(W.label("%s ×%d" % [App.t("item." + id), int(p.gamer.inventory[id])], UiTheme.FONT_M, UiTheme.PURPLE if def.get("rarity", "") != "" else UiTheme.TEXT, true))
		if def.has("mods"):
			box.add_child(W.label(Fmt.mods(def.mods), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		var row := W.hbox(8)
		if def.has("use") or def.has("slot"):
			row.add_child(W.button(App.t("ui.equip") if def.has("slot") else App.t("ui.use"), func(): ui.show_result(App.sim.command("use_item", [id])), 68, UiTheme.FONT_S))
		var price := float(def.get("value", 0)) * App.sim.world.item_price_mult(def)
		row.add_child(W.button(App.t("ui.sell_for", {"v": Fmt.money(price)}), func(): ui.show_result(App.sim.command("sell_item", [id, 1])), 68, UiTheme.FONT_S))
		box.add_child(row)
		_content.add_child(W.card(box))


# ---------------------------------------------------------------- achievements
func _render_achievements(sim: LifeSimulation, _p: Dictionary) -> void:
	var ids: Array = App.data.table("achievements").keys()
	ids.sort()
	for id in ids:
		var got: bool = sim.state.data.achievements.has(id) or App.meta.achievements.has(id)
		var row := W.hbox(10)
		row.add_child(W.icon("star" if got else "lock", UiTheme.GOLD if got else UiTheme.TEXT_DIM, 3))
		var col := W.vbox(2)
		col.add_child(W.label(App.t("ach.%s.title" % id), UiTheme.FONT_M, UiTheme.GOLD if got else UiTheme.TEXT_DIM))
		col.add_child(W.label(App.t("ach.%s.desc" % id), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		row.add_child(col)
		_content.add_child(W.card(row))
