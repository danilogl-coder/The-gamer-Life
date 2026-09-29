extends Control
## End-of-life retrospective + legacy: continue as an heir (dynasty) or
## reincarnate as a brand new life with Soul Points.

var ui


func setup(p_ui) -> void:
	ui = p_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.04, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var body := W.vbox(14)
	margin.add_child(W.scroll(body))
	var s: Dictionary = App.sim.state.data.get("death", {})
	var p := App.sim.player()
	body.add_child(W.label(App.t("ui.host_deceased"), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	var head := W.hbox(16)
	head.add_child(W.portrait(p, 4))
	var info := W.vbox(4)
	info.add_child(W.label(s.get("name", ""), UiTheme.FONT_XL, UiTheme.GOLD, true))
	info.add_child(W.label(App.t("ui.died_at", {"age": s.get("age", 0), "cause": App.t(s.get("cause", ""))}), UiTheme.FONT_M, UiTheme.TEXT, true))
	head.add_child(info)
	body.add_child(head)
	var stats := W.grid(2, 8)
	var job: String = s.get("job", "")
	for pair in [
		[App.t("ui.level"), str(s.get("level", 1))], [App.t("ui.rank"), App.t("rank.%d" % int(s.get("rank", 0)))],
		[App.t("ui.net_worth"), Fmt.money(float(s.get("net_worth", 0)))], [App.t("ui.occupation"), App.t("job." + job) if job != "" else "—"],
		[App.t("ui.children"), str(s.get("children", 0))], [App.t("ui.titles"), str(s.get("titles", 0))],
		[App.t("ui.achievements"), str(s.get("achievements", 0))], [App.t("ui.generation"), str(s.get("generation", 1))]]:
		stats.add_child(W.label(pair[0], UiTheme.FONT_S, UiTheme.TEXT_DIM))
		stats.add_child(W.label(pair[1], UiTheme.FONT_M, UiTheme.TEXT))
	body.add_child(W.system_card(stats))
	if not s.get("skills", []).is_empty():
		var flow := W.flow()
		for sid in s.skills:
			flow.add_child(W.chip(App.t("skill." + sid), UiTheme.tier_color(App.data.get_def("skills", sid).get("tier", "common"))))
		body.add_child(W.section(App.t("ui.best_skills")))
		body.add_child(flow)
	body.add_child(W.section(App.t("ui.life_story")))
	var story := W.vbox(4)
	for e in s.get("highlights", []):
		story.add_child(W.label("%d — %s" % [int(e.age), App.tr_entry(e)], UiTheme.FONT_S, UiTheme.TEXT, true))
	body.add_child(W.card(story))
	body.add_child(W.label(App.t("ui.soul_gain", {"n": int(s.get("soul_points", 0))}), UiTheme.FONT_M, UiTheme.PURPLE))
	var heirs: Array = App.sim.legacy.heirs()
	if not heirs.is_empty():
		body.add_child(W.section(App.t("ui.continue_dynasty")))
		for id in heirs:
			var h: Dictionary = App.sim.state.npc(id)
			var row := W.hbox(10)
			row.add_child(W.portrait(h, 2))
			row.add_child(W.tinted_button(App.t("ui.play_as", {"name": h.first_name, "age": h.age, "role": App.t("role." + App.sim.relations.role_of(id))}), _continue_as.bind(id), UiTheme.SYSTEM))
			body.add_child(row)
	body.add_child(W.tinted_button(App.t("ui.reincarnate"), _new_life, UiTheme.PANEL_HI, 100))


func _continue_as(id: String) -> void:
	if App.sim.legacy.continue_as(id):
		App.autosave()
		queue_free()


func _new_life() -> void:
	queue_free()
	ui._show_title()
