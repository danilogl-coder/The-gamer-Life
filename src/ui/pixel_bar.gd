class_name PixelBar
extends Control
## Segmented pixel progress bar with a light top edge and dark bottom edge.

var value := 0.0
var max_value := 100.0
var color := Color.WHITE
var text := ""


func setup(p_value: float, p_max: float, p_color: Color, p_text: String, height: int) -> void:
	value = p_value
	max_value = maxf(p_max, 0.0001)
	color = p_color
	text = p_text
	custom_minimum_size = Vector2(60, height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var px := 3.0
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("06070f"))
	var inner := r.grow(-px)
	draw_rect(inner, Color("161b33"))
	var t := clampf(value / max_value, 0.0, 1.0)
	var fill_w := floorf(inner.size.x * t / px) * px
	if fill_w > 0.0:
		var ramp := PixelPalette.ramp(color, 3, 0.25)
		var fr := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		draw_rect(fr, ramp[1])
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, px)), ramp[2])
		draw_rect(Rect2(fr.position + Vector2(0, fr.size.y - px), Vector2(fr.size.x, px)), ramp[0])
		# segment ticks every 10%
		for i in range(1, 10):
			var x := inner.position.x + floorf(inner.size.x * i / 10.0 / px) * px
			if x < inner.position.x + fill_w:
				draw_rect(Rect2(Vector2(x, fr.position.y + px), Vector2(px * 0.67, fr.size.y - 2 * px)), Color(ramp[0], 0.5))
	if text != "":
		var font := get_theme_default_font()
		var fs := int(size.y * 0.62)
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := Vector2((size.x - ts.x) / 2.0, (size.y + ts.y * 0.62) / 2.0)
		draw_string(font, pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
