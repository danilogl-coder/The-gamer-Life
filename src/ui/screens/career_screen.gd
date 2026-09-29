extends VBoxContainer
## CARREIRA — education and work. Shows where you are, what's open to you and
## exactly why the rest is locked, so players can plan their route.

var ui
var _only_open := true
var _box: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_box = W.vbox(10)
	add_child(W.scroll(_box))


func refresh() -> void:
	W.clear(_box)
	var sim: LifeSimulation = App.sim
	var p := sim.player()
	_render_education(sim, p)
	_render_school_life(sim, p)
	_render_job(sim, p)
	_render_special(sim, p)
	_render_board(sim, p)


func _render_education(sim: LifeSimulation, p: Dictionary) -> void:
	_box.add_child(W.section(App.t("ui.education")))
	var card := W.vbox(6)
	if p.education.stage != "":
		var def: Dictionary = App.data.get_def("education", p.education.stage)
		card.add_child(W.label("%s  (%d/%d)" % [App.t("edu." + p.education.stage), int(p.education.years) + 1, int(def.get("years", 1))], UiTheme.FONT_M, UiTheme.TEXT, true))
		card.add_child(W.bar(float(p.education.grades), 100, UiTheme.SYSTEM_EDGE, App.t("ui.grades") + " %d" % int(p.education.grades), 24))
		if int(p.education.absences) > 0:
			card.add_child(W.label(App.t("ui.absences", {"n": int(p.education.absences)}), UiTheme.FONT_S, UiTheme.WARN))
		if not def.get("auto", false) or int(p.age) >= int(def.get("drop_age", 99)):
			card.add_child(W.button(App.t("ui.drop_out"), func(): App.sim.command("drop_out"), 72, UiTheme.FONT_S))
	else:
		card.add_child(W.label(App.t("ui.not_studying"), UiTheme.FONT_S, UiTheme.TEXT_DIM))
	var done: Array = []
	for c in p.education.completed:
		done.append(App.t("edu." + c))
	if not done.is_empty():
		card.add_child(W.label(App.t("ui.completed") + ": " + ", ".join(done), 17, UiTheme.TEXT_DIM, true))
	_box.add_child(W.card(card))
	if int(p.age) < 16:
		return
	var ids: Array = App.data.table("education").keys()
	for id in ids:
		var def: Dictionary = App.data.get_def("education", id)
		if def.get("auto", false):
			continue
		var reason := sim.education.enroll_block_reason(p, id)
		if reason in ["edu.block.done", "edu.block.already"] or (_only_open and reason != ""):
			continue
		var tuition := float(def.get("tuition", 0)) * float(sim.finance.country(p).get("cost_of_living", 1.0))
		var text := "%s · %d %s · %s" % [App.t("edu." + id), int(def.years), App.t("ui.years"), Fmt.money(tuition) + "/" + App.t("ui.year_short")]
		if reason != "":
			text += "\n" + App.t(reason)
		var b := W.button(text, func(): ui.show_result(App.sim.command("enroll", [id])), 84, UiTheme.FONT_S)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = reason != ""
		_box.add_child(b)


func _render_job(sim: LifeSimulation, p: Dictionary) -> void:
	_box.add_child(W.section(App.t("ui.work")))
	var card := W.vbox(6)
	if p.career.job != "":
		card.add_child(W.label("%s — %s" % [App.t("job." + p.career.job), App.t("joblevel.%d" % int(p.career.level))], UiTheme.FONT_M, UiTheme.GOLD, true))
		card.add_child(W.label(App.t("ui.salary_line", {"v": Fmt.money(sim.career.current_salary(p)), "y": int(p.career.years)}), UiTheme.FONT_S, UiTheme.TEXT))
		card.add_child(W.bar(float(p.career.performance), 100, UiTheme.GOOD, App.t("ui.performance") + " %d" % int(p.career.performance), 22))
		var hours := W.hbox(6)
		for h in ["part", "normal", "overtime"]:
			var hb := W.tinted_button(App.t("job.hours_" + h), func(): App.sim.command("set_hours", [h]), UiTheme.SYSTEM if p.get("job_hours", "normal") == h else UiTheme.PANEL, 60)
			hb.add_theme_font_size_override("font_size", 17)
			hours.add_child(hb)
		card.add_child(hours)
		var row := W.hbox(8)
		row.add_child(W.button(App.t("ui.ask_raise"), func(): ui.show_result(App.sim.command("ask_raise")), 72, UiTheme.FONT_S))
		row.add_child(W.button(App.t("ui.quit_job"), func(): App.sim.command("quit_job"), 72, UiTheme.FONT_S))
		if int(p.age) >= int(App.data.bal("career.retire_age", 60)):
			row.add_child(W.button(App.t("ui.retire"), func(): ui.show_result(App.sim.command("retire")), 72, UiTheme.FONT_S))
		card.add_child(row)
	else:
		card.add_child(W.label(App.t("ui.unemployed"), UiTheme.FONT_S, UiTheme.TEXT_DIM))
	if p.faction.id != "":
		card.add_child(W.label(App.t("ui.faction_line", {"f": App.t("faction." + p.faction.id), "rep": int(p.faction.rep.get(p.faction.id, 0))}), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	_box.add_child(W.card(card))


## Popularity, cliques and clubs (only while at school).
func _render_school_life(sim: LifeSimulation, p: Dictionary) -> void:
	if not sim.education.in_school(p) or int(p.age) < 7:
		return
	var sch: Dictionary = sim.school_life.school(p)
	_box.add_child(W.section(App.t("ui.school_life")))
	var card := W.vbox(6)
	card.add_child(W.bar(float(sch.popularity), 100, UiTheme.PURPLE, App.t("ui.popularity") + " %d" % int(sch.popularity), 22))
	card.add_child(W.label(App.t("ui.clique_line", {"c": App.t("clique." + sch.clique) if sch.clique != "" else "—"}), UiTheme.FONT_S))
	for cid in sch.clubs:
		var row := W.hbox(8)
		row.add_child(W.label("%s · %s" % [App.t("club." + cid), App.t("club_rank.%d" % int(sch.clubs[cid].rank))], UiTheme.FONT_S, UiTheme.TEXT, true))
		var b := W.button(App.t("ui.practice") + " ⏱", func(): ui.show_result(App.sim.command("practice_club", [cid])), 64, 18)
		b.custom_minimum_size.x = 170
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(b)
		card.add_child(row)
	_box.add_child(W.card(card))
	var cl := W.grid(2, 6)
	for id in App.data.table("cliques"):
		var reason := sim.school_life.clique_block_reason(p, id)
		if reason in ["job.block.age"]:
			continue
		var b := W.button(App.t("clique." + id) + ("\n" + App.t(reason) if reason != "" else ""), func(): ui.show_result(App.sim.command("join_clique", [id])), 72, 17)
		b.disabled = reason != ""
		cl.add_child(b)
	_box.add_child(W.label(App.t("ui.cliques"), 18, UiTheme.TEXT_DIM))
	_box.add_child(cl)
	if sch.clubs.size() < 2:
		var clubs := W.grid(2, 6)
		for id in App.data.table("clubs"):
			if sch.clubs.has(id) or int(p.age) < int(App.data.get_def("clubs", id).min_age):
				continue
			clubs.add_child(W.button(App.t("club." + id), func(): ui.show_result(App.sim.command("join_club", [id])), 64, 17))
		_box.add_child(W.label(App.t("ui.clubs"), 18, UiTheme.TEXT_DIM))
		_box.add_child(clubs)


## Job interview: two questions, then the application with the bonus.
func _interview(job_id: String) -> void:
	var qs: Array = App.sim.career.interview_questions()
	var answers := {}
	var box := W.vbox(10)
	var sheet = null
	var render := func(step: int, self_ref: Callable) -> void:
		W.clear(box)
		if step >= qs.size():
			ui.close_overlays()
			ui.show_result(App.sim.command("apply_job", [job_id, answers]))
			return
		var q: Dictionary = qs[step]
		box.add_child(W.label(App.t("iq.%s" % q.id), UiTheme.FONT_M, UiTheme.TEXT, true))
		for a in q.answers:
			box.add_child(W.button(App.t("iq.%s.%s" % [q.id, a]), func(): answers[q.id] = a; self_ref.call(step + 1, self_ref), 80, UiTheme.FONT_S))
	render.call(0, render)
	sheet = ui.open_sheet(App.t("ui.interview", {"job": App.t("job." + job_id)}), box, true)


## Special careers: small games inside the life sim (music, sports, business, influencer).
func _render_special(sim: LifeSimulation, p: Dictionary) -> void:
	if int(p.age) < 12:
		return
	_box.add_child(W.section(App.t("ui.special_careers")))
	for id in sim.special.ids():
		if p.special.has(id):
			_box.add_child(_special_card(sim, p, id))
		else:
			var reason := sim.special.block_reason(p, id)
			var cost := float(sim.special.career(id).def.get("start_cost", 0))
			var text := App.t("ui.sc_start", {"career": App.t("sc." + id)}) + (" · " + Fmt.money(cost) if cost > 0 else "")
			if reason != "":
				text += "\n" + App.t(reason)
			var b := W.button(text, func(): ui.show_result(App.sim.command("sc_start", [id])), 80, UiTheme.FONT_S)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.disabled = reason != ""
			_box.add_child(b)


func _special_card(sim: LifeSimulation, p: Dictionary, id: String) -> Control:
	var box := W.vbox(6)
	box.add_child(W.label("★ " + App.t("sc." + id), UiTheme.FONT_M, UiTheme.GOLD))
	var grid := W.grid(2, 6)
	for row in sim.special.career(id).summary(p, p.special[id]):
		grid.add_child(W.label(App.t(row[0]), 18, UiTheme.TEXT_DIM))
		var v: String = row[1]
		grid.add_child(W.label(App.t(v.substr(1)) if v.begins_with("@") else v, 18, UiTheme.TEXT))
	box.add_child(grid)
	var actions := W.grid(2, 6)
	for a in sim.special.actions(p, id):
		var label := App.t("sc.%s.act.%s" % [id, a.id])
		if int(a.time) > 0:
			label += " ⏱%d" % int(a.time)
		if float(a.cost) > 0:
			label += " " + Fmt.money(float(a.cost))
		var b := W.button(label, func(): ui.show_result(App.sim.command("sc_action", [id, a.id])), 72, 18)
		b.disabled = a.locked != ""
		if a.locked != "":
			b.tooltip_text = App.t(a.locked)
		actions.add_child(b)
	box.add_child(actions)
	var quit := W.button(App.t("ui.sc_quit"), func(): App.sim.command("sc_quit", [id]), 60, 17)
	box.add_child(quit)
	return W.system_card(box)


func _render_board(sim: LifeSimulation, p: Dictionary) -> void:
	if int(p.age) < 12:
		return
	var head := W.hbox(8)
	head.add_child(W.section(App.t("ui.job_board")))
	var toggle := W.button(App.t("ui.show_all") if _only_open else App.t("ui.show_open"), func(): _only_open = not _only_open; refresh(), 60, 18)
	toggle.custom_minimum_size.x = 220
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	head.add_child(toggle)
	_box.add_child(head)
	var ids: Array = App.data.table("jobs").keys()
	ids.sort_custom(func(a, b): return float(App.data.get_def("jobs", a).salary) < float(App.data.get_def("jobs", b).salary))
	var shown := 0
	for id in ids:
		var def: Dictionary = App.data.get_def("jobs", id)
		var reason := sim.career.block_reason(p, id)
		if reason == "job.block.current" or (_only_open and reason != ""):
			continue
		if reason in ["job.block.age", "job.block.old"] and _only_open:
			continue
		var salary := float(def.salary) * float(sim.finance.country(p).get("salary_mult", 1.0))
		var text := "%s · %s/%s · %s" % [App.t("job." + id), Fmt.money(salary), App.t("ui.year_short"), App.t("jobcat." + def.get("cat", "admin"))]
		if reason != "":
			text += "\n" + App.t(reason)
		var b := W.button(text, _interview.bind(id), 84, UiTheme.FONT_S)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = reason != ""
		_box.add_child(b)
		shown += 1
	if shown == 0:
		_box.add_child(W.label(App.t("ui.no_jobs"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
