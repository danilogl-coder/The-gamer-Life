extends Control
## The System window for life events. Shows the actor's portrait, the text,
## and each choice with its success odds (the System shows you the numbers).
## After choosing, the outcome replaces the choices, then it closes.

signal closed

const ConversationView := preload("res://src/ui/popups/conversation_view.gd")

var _inst: Dictionary
var _body: VBoxContainer


func setup(inst: Dictionary) -> void:
	_inst = inst
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.08, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := W.system_card()
	card.custom_minimum_size = Vector2(minf(get_viewport_rect().size.x - 40, 680), 0)
	center.add_child(card)
	_body = W.vbox(14)
	card.add_child(_body)
	_render_question()
	card.scale = Vector2(0.92, 0.92)
	card.pivot_offset = card.custom_minimum_size / 2.0
	create_tween().tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)


func _render_question() -> void:
	W.clear(_body)
	var sim: LifeSimulation = App.sim
	if _inst.id == "__talk":
		sim.events.visible_choices(_inst)
		_body.add_child(W.label(App.t("ui.calls_you", {"name": sim.state.npc(_inst.actor).get("first_name", "")}), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
		var view = ConversationView.new()
		view.setup(sim.state.data.get("conversation", {}), true)
		view.finished.connect(_close)
		_body.add_child(view)
		return
	var params := sim.events.params_for(_inst)
	var head := W.hbox(14)
	var actor: Dictionary = sim.state.npc(_inst.get("actor", ""))
	if not actor.is_empty():
		head.add_child(W.portrait(actor, 3))
	var titles := W.vbox(2)
	titles.add_child(W.label(App.t("ui.system_tag"), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	titles.add_child(W.label(App.t("ev.%s.title" % _inst.id, params), UiTheme.FONT_L, UiTheme.TEXT, true))
	head.add_child(titles)
	_body.add_child(head)
	_body.add_child(W.label(_resolve_params("ev.%s.desc" % _inst.id, params), UiTheme.FONT_M, UiTheme.TEXT, true))

	for choice in sim.events.visible_choices(_inst):
		var text := App.t("ev.%s.%s" % [_inst.id, choice.id], params) if choice.id != "ok" else App.t("ui.continue")
		var odds := sim.events.choice_chance(_inst, choice)
		if odds >= 0.0:
			text += "   [%s]" % Fmt.pct(odds)
		_body.add_child(W.tinted_button(text, _choose.bind(choice.id), UiTheme.PANEL_HI))


func _choose(choice_id: String) -> void:
	var result: Dictionary = App.sim.choose(choice_id)
	if result.get("key", "") == "":
		_close()
		return
	W.clear(_body)
	var ok: bool = result.get("success", true)
	_body.add_child(W.label(App.t("ui.success") if ok else App.t("ui.failure"), UiTheme.FONT_S, UiTheme.GOOD if ok else UiTheme.BAD))
	_body.add_child(W.label(_resolve_params(result.key, result.params), UiTheme.FONT_M, UiTheme.TEXT, true))
	var flow := W.flow()
	for c in Fmt.gains(result.get("gains", {})):
		flow.add_child(W.chip(c.text, c.color))
	_body.add_child(flow)
	_body.add_child(W.tinted_button(App.t("ui.continue"), _close, UiTheme.SYSTEM))


func _resolve_params(key: String, params: Dictionary) -> String:
	return App.tr_entry({"key": key, "params": params})


func _close() -> void:
	closed.emit()
	queue_free()
