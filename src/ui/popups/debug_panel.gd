extends VBoxContainer
## Developer panel (hidden behind a long-press on the age label). Direct state
## pokes are acceptable here: it's a tool, not gameplay.

var ui
var _out: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sim: LifeSimulation = App.sim
	var g := W.grid(2, 8)
	g.add_child(W.button("+$100K", func(): sim.finance.add_cash(sim.player(), 100000); _done()))
	g.add_child(W.button("+5000 EXP", func(): sim.gamer.add_exp(sim.player(), 5000); _done()))
	g.add_child(W.button("+10 anos", func(): _years(10)))
	g.add_child(W.button("+1 ano", func(): _years(1)))
	g.add_child(W.button("+50 pts", func(): sim.player().gamer.stat_points += 50; _done()))
	g.add_child(W.button("Revelar mundo", func(): sim.state.set_flag("world_revealed"); sim.skills.learn(sim.player(), "id_create"); _done()))
	g.add_child(W.button("Doença (gripe)", func(): sim.health.add_condition(sim.player(), "flu"); _done()))
	g.add_child(W.button("Emprego: programador", func(): sim.career.hire(sim.player(), "programmer", true); _done()))
	g.add_child(W.button("Spawn NPC amigo", func(): var n = sim.factory.spawn_contextual("friend"); sim.relations.ensure(n.id, "friend", 60); _done()))
	g.add_child(W.button("Matar personagem", func(): sim.health.kill(sim.player(), "cause.event"); _done()))
	g.add_child(W.button("Listar flags", func(): _out.text = JSON.stringify(sim.state.data.flags, " ")))
	g.add_child(W.button("Eventos agendados", func(): _out.text = JSON.stringify(sim.state.data.scheduled, " ")))
	add_child(g)
	add_child(W.label("Forçar evento:", UiTheme.FONT_S, UiTheme.TEXT_DIM))
	var flow := W.flow(4)
	var ids: Array = App.data.events.keys()
	ids.sort()
	for id in ids:
		var b := Button.new()
		b.text = id
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(0, 56)
		b.pressed.connect(func(): sim.events.queue_event(id, "", true); ui.close_overlays())
		flow.add_child(b)
	add_child(flow)
	_out = W.label("seed: %s" % sim.rng.seed_value, UiTheme.FONT_S, UiTheme.TEXT_DIM, true)
	add_child(_out)


func _years(n: int) -> void:
	for i in n:
		while App.sim.has_pending_events():
			App.sim.choose(App.sim.events.visible_choices(App.sim.current_event())[0].id)
		App.sim.advance_year()
	_done()


func _done() -> void:
	App.sim.gamer.invalidate()
	App.bus.state_changed.emit()
	_out.text = "ok"
