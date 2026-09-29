class_name PixelCanvas
extends RefCounted
## Tiny software rasterizer for procedural pixel art. Draw shapes into an
## Image, then `to_texture()` (nearest-neighbour friendly).

var w: int
var h: int
var img: Image


func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))


func put(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < w and y < h:
		img.set_pixel(x, y, c)


func get_px(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= w or y >= h:
		return Color(0, 0, 0, 0)
	return img.get_pixel(x, y)


func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
	for yy in range(y, y + rh):
		for xx in range(x, x + rw):
			put(xx, yy, c)


## Filled ellipse shaded by a light coming from the top-left. `ramp` is dark→light.
## Directional shading (not "pillow shading") keeps the volume readable.
func shaded_ellipse(cx: float, cy: float, rx: float, ry: float, ramp: Array, light := Vector2(-0.6, -0.8)) -> void:
	for yy in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for xx in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var nx := (xx + 0.5 - cx) / rx
			var ny := (yy + 0.5 - cy) / ry
			var d := nx * nx + ny * ny
			if d > 1.0:
				continue
			var nz := sqrt(maxf(0.0, 1.0 - d))
			var lum := clampf((nx * light.x + ny * light.y) * 0.5 + nz * 0.55 + 0.05, 0.0, 0.999)
			put(xx, yy, ramp[clampi(int(lum * ramp.size()), 0, ramp.size() - 1)])


func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for yy in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for xx in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var nx := (xx + 0.5 - cx) / rx
			var ny := (yy + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				put(xx, yy, c)


## Ordered (Bayer 4x4) dithered vertical gradient — the classic retro sky.
func dither_gradient(top: Color, bottom: Color, steps: int = 5) -> void:
	const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	for yy in h:
		var t := float(yy) / maxf(1.0, h - 1.0) * (steps - 1)
		var band := floorf(t)
		var frac := t - band
		for xx in w:
			var threshold: float = (BAYER[(yy % 4) * 4 + (xx % 4)] + 0.5) / 16.0
			var level := band + (1.0 if frac > threshold else 0.0)
			put(xx, yy, top.lerp(bottom, level / maxf(1.0, steps - 1.0)))


## Selective outline ("sel-out"): transparent pixels touching the sprite take a
## dark, hue-shifted version of the neighbour, not a flat black line.
func selective_outline(only_below: int = 999) -> void:
	var src := img.duplicate()
	for yy in h:
		for xx in w:
			if src.get_pixel(xx, yy).a > 0.0 or yy > only_below:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = xx + d.x
				var ny: int = yy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n: Color = src.get_pixel(nx, ny)
				if n.a > 0.0:
					put(xx, yy, PixelPalette.outline_of(n))
					break


## Stamps a character-grid sprite. `legend` maps chars to colours; "." is empty.
func stamp(rows: Array, ox: int, oy: int, legend: Dictionary) -> void:
	for yy in rows.size():
		var row: String = rows[yy]
		for xx in row.length():
			var ch := row[xx]
			if legend.has(ch):
				put(ox + xx, oy + yy, legend[ch])


func to_texture() -> ImageTexture:
	return ImageTexture.create_from_image(img)
