extends Control
## Stacked System notifications at the top of the screen ("LEVEL UP!",
## "New skill!", activity results). Non-blocking; each fades after a moment.

const MAX_VISIBLE := 3
const KIND_STYLE := {
	"level": ["star", Color("ffcf4d")],
	"stat": ["star", Color("8be04f")],
	"skill": ["bolt", Color("5fd8ff")],
	"evolve": ["bolt", Color("c77dff")],
	"title": ["star", Color("ffcf4d")],
	"quest": ["system", Color("5fd8ff")],
	"achievement": ["star", Color("ffcf4d")],
	"world": ["system", Color("ffa84d")],
	"warn": ["lock", Color("ff6a5a")],
	"system": ["system", Color("5fd8ff")],
	"result": ["clock", Color("e9edff")],
}

var _stack: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_bottom", 250)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_stack = W.vbox(6)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_stack)


func push(kind: String, text: String, chips: Array) -> void:
	if text == "" and chips.is_empty():
		return
	var style: Array = KIND_STYLE.get(kind, KIND_STYLE.system)
	var row := W.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(W.icon(style[0], style[1], 2))
	var col := W.vbox(4)
	if text != "":
		col.add_child(W.label(text, UiTheme.FONT_S, style[1] if kind != "result" else UiTheme.TEXT, true))
	if not chips.is_empty():
		var flow := W.flow(4)
		for c in chips:
			flow.add_child(W.chip(c.text, c.color, 17))
		col.add_child(flow)
	row.add_child(col)
	var card := W.system_card(row)
	var sb: StyleBoxTexture = card.get_theme_stylebox("panel")
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = 0.0
	_stack.add_child(card)
	while _stack.get_child_count() > MAX_VISIBLE:
		var old := _stack.get_child(0)
		_stack.remove_child(old)
		old.queue_free()
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.12)
	tw.tween_interval(1.6 + text.length() * 0.02)
	tw.tween_property(card, "modulate:a", 0.0, 0.35)
	tw.tween_callback(card.queue_free)
