class_name W
extends RefCounted
## Small UI factory so screens stay declarative and consistent.
## Touch targets are never smaller than MIN_TOUCH px (viewport is 720 wide).

const MIN_TOUCH := 84


static func label(text: String, size: int = UiTheme.FONT_M, color: Color = UiTheme.TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func rich(bbcode: String, size: int = UiTheme.FONT_M) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", UiTheme.TEXT)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, cb: Callable, min_h: int = MIN_TOUCH, size: int = UiTheme.FONT_M) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", size)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


static func icon_button(icon_name: String, color: Color, text: String, cb: Callable, min_h: int = MIN_TOUCH) -> Button:
	var b := button(text, cb, min_h)
	b.icon = PixelIcons.texture(icon_name, color)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 36)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


static func tinted_button(text: String, cb: Callable, fill: Color, min_h: int = MIN_TOUCH) -> Button:
	var b := button(text, cb, min_h)
	b.add_theme_stylebox_override("normal", UiTheme.frame(fill, false))
	b.add_theme_stylebox_override("hover", UiTheme.frame(fill.lightened(0.1), false))
	b.add_theme_stylebox_override("pressed", UiTheme.frame(fill.darkened(0.15), true))
	return b


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


static func grid(cols: int, sep: int = 10) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


static func card(child: Control = null, fill: Color = UiTheme.PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.frame(fill, false))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if child:
		p.add_child(child)
	return p


static func system_card(child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.system_frame())
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if child:
		p.add_child(child)
	return p


static func section(text: String) -> Label:
	var l := label("◆ " + text.to_upper(), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE)
	l.add_theme_constant_override("line_spacing", 0)
	return l


static func chip(text: String, color: Color, size: int = UiTheme.FONT_S) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.18)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text, size, color))
	return p


static func flow(sep: int = 6) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


static func portrait(ch: Dictionary, px: int = 4) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Portrait.texture_for(ch)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = Vector2(Portrait.SIZE * px, Portrait.SIZE * px)
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func icon(name: String, color: Color, px: int = 3) -> TextureRect:
	var t := TextureRect.new()
	t.texture = PixelIcons.texture(name, color, px)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = Vector2(12 * px, 12 * px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func bar(value: float, max_value: float, color: Color, text: String = "", height: int = 26) -> PixelBar:
	var b := PixelBar.new()
	b.setup(value, max_value, color, text, height)
	return b


static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func spacer(h: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
