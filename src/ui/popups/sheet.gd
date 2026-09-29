extends Control
## Modal bottom sheet: dimmed backdrop + framed panel anchored to the bottom
## (thumb-friendly). Tap outside or the ✕ button to close.

signal closed

var panel: PanelContainer
var body: VBoxContainer


func setup(title: String, content: Control, system_style: bool = false, dismissible: bool = true) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	if dismissible:
		dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var align := VBoxContainer.new()
	align.alignment = BoxContainer.ALIGNMENT_END
	align.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(align)
	panel = W.system_card() if system_style else W.card(null, UiTheme.BG2)
	align.add_child(panel)
	body = W.vbox(12)
	panel.add_child(body)
	var head := W.hbox(8)
	var t := W.label(title, UiTheme.FONT_L, UiTheme.SYSTEM_EDGE if system_style else UiTheme.GOLD, true)
	head.add_child(t)
	if dismissible:
		var x := Button.new()
		x.text = "✕"
		x.custom_minimum_size = Vector2(72, 72)
		x.pressed.connect(close)
		head.add_child(x)
	body.add_child(head)
	var scroll := W.scroll(content)
	scroll.custom_minimum_size = Vector2(0, 0)
	body.add_child(scroll)
	# Grow with content up to ~78% of the screen, then scroll.
	await get_tree().process_frame
	var max_h := get_viewport_rect().size.y * 0.78
	scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y + 8, max_h)


func close() -> void:
	closed.emit()
	queue_free()
