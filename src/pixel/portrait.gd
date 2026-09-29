class_name Portrait
extends RefCounted
## Procedural 32×32 character portraits built from a tiny genome
## (skin/hair/style/eyes/bg + sex + age + mood). Everything is drawn in code:
## hue-shifted ramps, directional light from the top-left, dithered sky and a
## selective outline. Results are cached by genome key.

const SIZE := 32
static var _cache: Dictionary = {}


static func texture_for(ch: Dictionary) -> ImageTexture:
	var look: Dictionary = ch.get("look", {})
	var age := int(ch.get("age", 20))
	var stage := age_stage(age)
	var mood := 0
	var happy := float(ch.get("attrs", {}).get("happiness", 60))
	if happy >= 70.0:
		mood = 1
	elif happy < 35.0:
		mood = -1
	var dead: bool = not ch.get("alive", true)
	var key := "%s|%s|%d|%d|%s|%s" % [ch.get("sex", "m"), str(look), stage, mood, dead, ch.get("gamer", {}).get("awakened", false) and ch.get("is_player", false)]
	if _cache.has(key):
		return _cache[key]
	var tex := _draw(ch.get("sex", "m"), look, stage, mood, dead, ch.get("is_player", false))
	if _cache.size() > 300:
		_cache.clear()
	_cache[key] = tex
	return tex


## 0 baby, 1 child, 2 teen, 3 adult, 4 middle age, 5 elder
static func age_stage(age: int) -> int:
	if age < 3: return 0
	if age < 12: return 1
	if age < 18: return 2
	if age < 40: return 3
	if age < 62: return 4
	return 5


static func _draw(sex: String, look: Dictionary, stage: int, mood: int, dead: bool, is_player: bool) -> ImageTexture:
	var bg_base: Color = PixelPalette.BG[int(look.get("bg", 0)) % PixelPalette.BG.size()]
	var bg_ramp := PixelPalette.ramp(bg_base, 5, 0.3)
	var back := PixelCanvas.new(SIZE, SIZE)
	back.dither_gradient(bg_ramp[3], bg_ramp[1], 4)
	if is_player:
		_system_glow(back)

	var fig := PixelCanvas.new(SIZE, SIZE)
	var skin := PixelPalette.ramp(PixelPalette.SKIN[int(look.get("skin", 0)) % PixelPalette.SKIN.size()], 4, 0.22)
	var hair_base: Color = PixelPalette.HAIR[int(look.get("hair", 0)) % PixelPalette.HAIR.size()]
	if stage == 5:
		hair_base = Color("d8d8e0")
	elif stage == 4 and int(look.get("hair", 0)) % 3 == 0:
		hair_base = hair_base.lerp(Color("a0a0a8"), 0.45)
	var hair := PixelPalette.ramp(hair_base, 4, 0.26)
	var cloth := PixelPalette.ramp(PixelPalette.CLOTH[(int(look.get("skin", 0)) + int(look.get("hair", 0)) + int(look.get("style", 0))) % PixelPalette.CLOTH.size()], 4, 0.28)
	var eye: Color = PixelPalette.EYES[int(look.get("eyes", 0)) % PixelPalette.EYES.size()]
	var style := int(look.get("style", 0)) % 6

	# Proportions per life stage: babies have big heads, elders slightly smaller.
	var head_r := Vector2(7.5, 8.5)
	var head_c := Vector2(16, 14.5)
	var shoulders_w := 11.0
	match stage:
		0:
			head_r = Vector2(8.5, 8.5); head_c = Vector2(16, 16.5); shoulders_w = 8.0
		1:
			head_r = Vector2(8.0, 8.5); head_c = Vector2(16, 15.5); shoulders_w = 9.0
		2:
			head_r = Vector2(7.5, 8.5); shoulders_w = 10.0

	if style in [2, 3] and stage > 0:
		_long_hair_back(fig, head_c, head_r, hair, style)
	fig.shaded_ellipse(16, 31.5, shoulders_w, 7.5, cloth)
	fig.rect(14, int(head_c.y + head_r.y) - 2, 4, 4, skin[1])
	fig.shaded_ellipse(head_c.x, head_c.y, head_r.x, head_r.y, skin)
	# ears
	fig.put(int(head_c.x - head_r.x), int(head_c.y + 1), skin[1])
	fig.put(int(head_c.x + head_r.x) - 1, int(head_c.y + 1), skin[0])
	_face(fig, head_c, stage, mood, eye, skin, hair, sex)
	if stage > 0:
		_hair_top(fig, head_c, head_r, hair, style, sex, stage)
	else:
		fig.put(16, int(head_c.y - head_r.y) + 1, hair[2])
		fig.put(17, int(head_c.y - head_r.y) + 2, hair[2])
	fig.selective_outline()

	back.img.blend_rect(fig.img, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
	if dead:
		back.img.adjust_bcs(0.9, 1.0, 0.0)
	return back.to_texture()


static func _face(fig: PixelCanvas, c: Vector2, stage: int, mood: int, eye: Color, skin: Array, hair: Array, sex: String) -> void:
	var ey := int(c.y + 1)
	var white := Color("f4f1ea")
	# eyes: white + iris, pupils face inward; highlight pixel on top-left.
	for side in [-1, 1]:
		var ex: int = int(c.x) + side * 3 - (1 if side < 0 else 0)
		fig.put(ex, ey, white)
		fig.put(ex + 1, ey, white)
		var iris_x: int = ex + (1 if side < 0 else 0)
		fig.put(iris_x, ey, eye)
		fig.put(iris_x, ey + 1, eye.darkened(0.45))
		fig.put(ex + (0 if side < 0 else 1), ey + 1, skin[1])
		# brows
		fig.put(ex, ey - 2, hair[0])
		fig.put(ex + 1, ey - 2, hair[0])
	# nose shadow (light from top-left → shadow on the right)
	fig.put(int(c.x) + 1, ey + 3, skin[1])
	# mouth
	var my := ey + 5
	var mouth: Color = skin[0].lerp(Color("a03a3a"), 0.45)
	fig.put(int(c.x) - 1, my, mouth)
	fig.put(int(c.x), my, mouth)
	if mood > 0:
		fig.put(int(c.x) - 2, my - 1, mouth)
		fig.put(int(c.x) + 1, my - 1, mouth)
	elif mood < 0:
		fig.put(int(c.x) - 2, my + 1, mouth)
		fig.put(int(c.x) + 1, my + 1, mouth)
	if stage <= 1:
		fig.put(int(c.x) - 5, ey + 3, Color("f08a8a"))
		fig.put(int(c.x) + 4, ey + 3, Color("f08a8a"))
	if stage >= 4:
		fig.put(int(c.x) - 5, ey - 1, skin[1])
		fig.put(int(c.x) + 4, ey - 1, skin[1])
	if stage >= 3 and sex == "m" and int(skin[0].v * 100) % 3 == 0:
		for x in range(int(c.x) - 3, int(c.x) + 3):
			fig.put(x, my + 2, hair[1])


static func _hair_top(fig: PixelCanvas, c: Vector2, r: Vector2, hair: Array, style: int, sex: String, stage: int) -> void:
	var top := c.y - r.y
	var hairline := c.y - 2.0
	for yy in range(int(top) - 2, int(hairline) + 1):
		for xx in range(int(c.x - r.x) - 2, int(c.x + r.x) + 2):
			var nx := (xx + 0.5 - c.x) / (r.x + 1.0)
			var ny := (yy + 0.5 - (c.y - 1.0)) / (r.y + 1.2)
			if nx * nx + ny * ny > 1.0:
				continue
			# fringe shape per style
			var edge := hairline
			match style:
				0: edge = hairline - 1.0 + (1.0 if absi(xx - int(c.x)) > 5 else 0.0)
				1: edge = hairline - 1.0 + (2.0 if (xx % 3) == 0 else 0.0)
				4: edge = hairline - 2.0
				5: edge = hairline + (1.0 if (xx % 2) == 0 else -1.0)
			if yy > edge:
				continue
			var lum := clampf(0.5 - nx * 0.45 - ny * 0.35, 0.0, 0.999)
			fig.put(xx, yy, hair[int(lum * hair.size())])
	# spikes / bun / curls
	match style:
		1:
			for i in 4:
				fig.put(int(c.x) - 5 + i * 3, int(top) - 2, hair[2])
				fig.put(int(c.x) - 5 + i * 3, int(top) - 3, hair[3])
		4:
			fig.shaded_ellipse(c.x + 1, top - 1.0, 3.2, 2.6, hair)
		5:
			for i in 5:
				fig.put(int(c.x - r.x) + i * 3, int(top), hair[3])
	# side hair locks for longer cuts
	if style in [2, 3, 5] or (sex == "f" and style != 0):
		for yy in range(int(hairline) - 1, int(c.y) + (6 if style == 2 else 3)):
			fig.put(int(c.x - r.x), yy, hair[1])
			fig.put(int(c.x + r.x) - 1, yy, hair[0])


static func _long_hair_back(fig: PixelCanvas, c: Vector2, r: Vector2, hair: Array, style: int) -> void:
	var bottom := c.y + (r.y + 6.0 if style == 2 else r.y)
	for yy in range(int(c.y - 2), int(bottom)):
		for xx in range(int(c.x - r.x) - 1, int(c.x + r.x) + 1):
			fig.put(xx, yy, hair[0] if xx > int(c.x) + 2 else hair[1])


static func _system_glow(back: PixelCanvas) -> void:
	# The System user's portrait carries a faint blue frame glint.
	var glow := Color(0.45, 0.85, 1.0, 1.0)
	for i in SIZE:
		if i % 3 == 0:
			back.put(i, 0, glow)
			back.put(0, i, glow)
		if i % 4 == 0:
			back.put(i, SIZE - 1, glow.darkened(0.3))
			back.put(SIZE - 1, i, glow.darkened(0.3))
