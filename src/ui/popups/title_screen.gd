extends Control
## Title / new-life screen: continue, start a new life (name, sex, country)
## and spend Soul Points on reincarnation perks. Also the language switch.

var ui
var _body: VBoxContainer
var _opts := {"sex": "", "country": "", "perks": [], "challenge": ""}
var _name_edit: LineEdit


func setup(p_ui) -> void:
	ui = p_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TextureRect.new()
	var c := PixelCanvas.new(72, 128)
	c.dither_gradient(Color("24306a"), Color("07091a"), 7)
	for i in 40:
		c.put((i * 37) % 72, (i * 53) % 90, Color(1, 1, 1, 0.7 if i % 3 else 1.0))
	bg.texture = c.to_texture()
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	_body = W.vbox(16)
	margin.add_child(W.scroll(_body))
	_render_home()


func _logo() -> void:
	_body.add_child(W.spacer(40))
	var t := W.label("THE GAMER", 64, UiTheme.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_shadow_color", Color("7a3a00"))
	t.add_theme_constant_override("shadow_offset_x", 4)
	t.add_theme_constant_override("shadow_offset_y", 4)
	_body.add_child(t)
	var s := W.label("L I F E", 40, UiTheme.SYSTEM_EDGE)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(s)
	var tag := W.label(App.t("ui.tagline"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(tag)
	_body.add_child(W.spacer(20))


func _render_home() -> void:
	W.clear(_body)
	_logo()
	var hero := CenterContainer.new()
	var demo := {"sex": "m", "age": 17, "look": {"skin": 1, "hair": 0, "style": 1, "eyes": 1, "bg": 0}, "attrs": {"happiness": 80}, "is_player": true, "gamer": {"awakened": true}}
	hero.add_child(W.portrait(demo, 6))
	_body.add_child(hero)
	_body.add_child(W.spacer(20))
	if App.has_save():
		_body.add_child(W.tinted_button(App.t("ui.continue_life"), _continue, UiTheme.SYSTEM, 100))
	_body.add_child(W.tinted_button(App.t("ui.new_life"), _render_new_life, UiTheme.PANEL_HI, 100))
	var lang := W.hbox(10)
	lang.add_child(W.button("Português", func(): App.set_locale("pt"); _render_home()))
	lang.add_child(W.button("English", func(): App.set_locale("en"); _render_home()))
	_body.add_child(lang)
	_body.add_child(W.button(App.t("ui.challenges"), _render_challenges))
	var mature := W.button(App.t("ui.mature_on") if App.meta.mature else App.t("ui.mature_off"), func(): App.set_mature(not App.meta.mature); _render_home())
	_body.add_child(mature)
	_body.add_child(W.label(App.t("ui.soul_points", {"n": int(App.meta.soul_points)}), UiTheme.FONT_S, UiTheme.PURPLE))
	_body.add_child(W.label(App.t("ui.ribbons_count", {"n": App.meta.get("ribbons", {}).size(), "t": App.data.table("ribbons").size()}), UiTheme.FONT_S, UiTheme.GOLD))


func _render_challenges() -> void:
	W.clear(_body)
	_body.add_child(W.label(App.t("ui.challenges"), UiTheme.FONT_XL, UiTheme.GOLD))
	for id in App.data.table("challenges"):
		var def: Dictionary = App.data.get_def("challenges", id)
		var done: bool = App.meta.challenges.has(id)
		var box := W.vbox(6)
		box.add_child(W.label(("✔ " if done else "") + App.t("ch.%s.title" % id), UiTheme.FONT_M, UiTheme.GOLD if done else UiTheme.TEXT, true))
		box.add_child(W.label(App.t("ch.%s.desc" % id), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		box.add_child(W.label(App.t("ui.reward_soul", {"n": int(def.reward)}), 18, UiTheme.PURPLE))
		box.add_child(W.tinted_button(App.t("ui.accept_challenge"), func(): _opts.challenge = id; _opts.merge(def.get("options", {}), true); _render_new_life(), UiTheme.SYSTEM, 72))
		_body.add_child(W.card(box))
	_body.add_child(W.button(App.t("ui.back"), _render_home))


func _continue() -> void:
	if App.continue_life():
		queue_free()
		if App.sim.is_dead():
			ui._show_death()


func _render_new_life() -> void:
	W.clear(_body)
	_body.add_child(W.label(App.t("ui.new_life"), UiTheme.FONT_XL, UiTheme.GOLD))
	if _opts.challenge != "":
		_body.add_child(W.chip(App.t("ch.%s.title" % _opts.challenge), UiTheme.GOLD))
	var card := W.vbox(12)
	card.add_child(W.label(App.t("ui.name_optional"), UiTheme.FONT_S, UiTheme.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(0, 80)
	_name_edit.add_theme_font_size_override("font_size", UiTheme.FONT_L)
	_name_edit.placeholder_text = App.t("ui.random")
	card.add_child(_name_edit)
	card.add_child(W.label(App.t("ui.sex"), UiTheme.FONT_S, UiTheme.TEXT_DIM))
	card.add_child(_choice_row("sex", ["", "m", "f"], func(v): return App.t("ui.random") if v == "" else App.t("sex." + v)))
	card.add_child(W.label(App.t("ui.country"), UiTheme.FONT_S, UiTheme.TEXT_DIM))
	var countries: Array = [""] + App.data.table("countries").keys()
	card.add_child(_choice_row("country", countries, func(v): return App.t("ui.random") if v == "" else App.t("country." + v)))
	_body.add_child(W.card(card))
	_body.add_child(W.section(App.t("ui.perks") + " — " + App.t("ui.soul_points", {"n": _points_left()})))
	var perks := W.vbox(8)
	for id in App.data.table("items"):
		var def: Dictionary = App.data.get_def("items", id)
		if not def.get("perk", false):
			continue
		var owned: bool = _opts.perks.has(id)
		var b := W.tinted_button("%s  (%d ✦)%s" % [App.t("item." + id), int(def.cost), "  ✔" if owned else ""], _toggle_perk.bind(id), UiTheme.SYSTEM if owned else UiTheme.PANEL, 76)
		b.disabled = not owned and int(def.cost) > _points_left()
		perks.add_child(b)
	_body.add_child(perks)
	_body.add_child(W.tinted_button(App.t("ui.be_born"), _start, Color("2f7a3a"), 110))
	_body.add_child(W.button(App.t("ui.back"), _render_home))


func _choice_row(key: String, values: Array, label_fn: Callable) -> HFlowContainer:
	var row := W.flow(8)
	for v in values:
		var sel: bool = _opts[key] == v
		var b := W.tinted_button(label_fn.call(v), func(): _opts[key] = v; _render_new_life(), UiTheme.SYSTEM if sel else UiTheme.PANEL, 72)
		b.size_flags_horizontal = Control.SIZE_FILL
		b.custom_minimum_size.x = 150
		row.add_child(b)
	return row


func _points_left() -> int:
	var spent := 0
	for id in _opts.perks:
		spent += int(App.data.get_def("items", id).cost)
	return int(App.meta.soul_points) - spent


func _toggle_perk(id: String) -> void:
	if _opts.perks.has(id):
		_opts.perks.erase(id)
	elif int(App.data.get_def("items", id).cost) <= _points_left():
		_opts.perks.append(id)
	_render_new_life()


func _start() -> void:
	var options := {"perks": _opts.perks.duplicate(), "challenge": _opts.challenge}
	if _opts.has("wealth"):
		options.wealth = _opts.wealth
	if _opts.sex != "":
		options.sex = _opts.sex
	if _opts.country != "":
		options.country = _opts.country
	if _name_edit and _name_edit.text.strip_edges() != "":
		options.first_name = _name_edit.text.strip_edges()
	App.meta.soul_points = _points_left()
	App.save_meta()
	App.start_new_life(options)
	queue_free()
