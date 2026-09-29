extends VBoxContainer
## A conversation scene: setting (narration), what the person says (speech
## bubbles in their own voice) and your possible replies with the odds the
## System estimates from their personality. Used for talks you start and for
## people who call you (pending "__talk" events).

signal finished

var _conv: Dictionary
var _pending := false


func setup(conv: Dictionary, pending: bool) -> void:
	_conv = conv
	_pending = pending
	add_theme_constant_override("separation", 12)
	_render()


func _render() -> void:
	W.clear(self)
	var sim: LifeSimulation = App.sim
	var npc: Dictionary = sim.state.npc(_conv.get("npc", ""))
	if npc.is_empty():
		return
	var head := W.hbox(12)
	head.add_child(W.portrait(npc, 3))
	var col := W.vbox(2)
	col.add_child(W.label("%s %s" % [npc.first_name, npc.last_name], UiTheme.FONT_M, UiTheme.TEXT, true))
	var role: String = sim.relations.role_of(npc.id)
	col.add_child(W.label(App.t("role." + role) if role != "" else "", UiTheme.FONT_S, UiTheme.TEXT_DIM))
	var mood := W.flow(4)
	mood.add_child(W.chip(App.t("ui.mood") + ": " + App.t("ui.mood_band." + Persona.mood_band(npc)), _mood_color(npc), 16))
	if int(npc.get("observed", 0)) >= 2 or RelationshipSystem.FAMILY_ROLES.has(role):
		mood.add_child(W.chip(App.t("voice." + str(npc.get("persona", {}).get("voice", "calm"))), UiTheme.PURPLE, 16))
	col.add_child(mood)
	head.add_child(col)
	add_child(head)
	for l in _conv.get("lines", []):
		add_child(_line(l))
	var replies: Array = _conv.get("replies", [])
	if replies.is_empty():
		add_child(W.tinted_button(App.t("ui.continue"), _end, UiTheme.SYSTEM))
		return
	add_child(W.label(App.t("ui.you_say"), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	for r in replies:
		var text := App.t("dlgui." + str(r.id)) + "   [%s]" % Fmt.pct(float(r.chance))
		var b := W.tinted_button(text, _reply.bind(r.id), UiTheme.PANEL_HI)
		if float(r.get("cost", 0)) > float(sim.player().finance.cash):
			b.disabled = true
		add_child(b)


func _line(l: Dictionary) -> Control:
	var text := App.tr_entry(l)
	if l.get("kind", "") == "narration":
		var lab := W.label(text, UiTheme.FONT_S, UiTheme.TEXT_DIM, true)
		return lab
	var bubble := W.card(W.label("“%s”" % text, UiTheme.FONT_M, UiTheme.TEXT, true), UiTheme.PANEL_HI)
	return bubble


func _reply(reply_id: String) -> void:
	var r: Dictionary
	if _pending:
		r = App.sim.choose(reply_id)
	else:
		r = App.sim.command("reply", [reply_id])
	if not r.get("ok", false):
		add_child(W.label(App.t(r.get("reason", "ui.invalid")), UiTheme.FONT_S, UiTheme.BAD, true))
		return
	for c in get_children():
		if c is Button:
			c.queue_free()
	add_child(W.label(App.t("dlgui." + reply_id), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE, true))
	for l in r.get("lines", []):
		add_child(_line(l))
	var chips := Fmt.gains(r.get("gains", {}))
	if not chips.is_empty():
		var flow := W.flow()
		for c in chips:
			flow.add_child(W.chip(c.text, c.color))
		add_child(flow)
	var ok: bool = r.get("success", true)
	add_child(W.label(App.t("ui.success") if ok else App.t("ui.failure"), UiTheme.FONT_S, UiTheme.GOOD if ok else UiTheme.BAD))
	add_child(W.tinted_button(App.t("ui.continue"), func(): finished.emit(), UiTheme.SYSTEM))


func _end() -> void:
	if _pending:
		App.sim.choose("ok")
	else:
		App.sim.command("end_talk")
	finished.emit()


func _mood_color(npc: Dictionary) -> Color:
	match Persona.mood_band(npc):
		"miserable": return UiTheme.BAD
		"down": return UiTheme.WARN
		"happy": return UiTheme.GOOD
	return UiTheme.TEXT_DIM
