extends SceneTree
## Renders a sheet of procedural portraits for visual review:
##   godot --headless --path . -s res://tests/portrait_sheet.gd -- /tmp/portraits.png
func _initialize():
	var sheet := Image.create(32 * 6 * 4, 32 * 4 * 4, false, Image.FORMAT_RGBA8)
	var i := 0
	for row in 4:
		for col in 6:
			var ch := {"sex": "m" if (i % 2) == 0 else "f", "age": [1, 8, 15, 25, 50, 75][col], "alive": true,
				"look": {"skin": i % 6, "hair": (i * 3) % 8, "style": (i + row) % 6, "eyes": i % 5, "bg": i % 6},
				"attrs": {"happiness": [80, 50, 20, 60][row]}}
			var img: Image = Portrait.texture_for(ch).get_image()
			img.resize(128, 128, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(img, Rect2i(0, 0, 128, 128), Vector2i(col * 128, row * 128))
			i += 1
	sheet.save_png(OS.get_cmdline_user_args()[0])
	quit()
