class_name CreatureArt
extends RefCounted
## 20×20 procedural creatures for pets and familiars: a shaded body shape,
## species features (ears, horns, wings, legs) and big readable eyes.

const SIZE := 20
const LOOK := {
	"dog": {"color": "b07a45", "shape": "quad", "ears": "floppy"},
	"cat": {"color": "e0a050", "shape": "quad", "ears": "pointy"},
	"parrot": {"color": "3fbf5a", "shape": "bird"},
	"hamster": {"color": "e8c89a", "shape": "blob", "ears": "round"},
	"slime_fam": {"color": "4fb8ff", "shape": "slime"},
	"slime_named": {"color": "7ad8ff", "shape": "slime", "crown": true},
	"goblin_fam": {"color": "6fae3a", "shape": "humanoid", "ears": "pointy"},
	"hobgoblin_named": {"color": "3f6e2a", "shape": "humanoid", "ears": "pointy", "horns": true},
	"wolf_fam": {"color": "8a8fa8", "shape": "quad", "ears": "pointy"},
	"tempest_wolf": {"color": "3a4a8a", "shape": "quad", "ears": "pointy", "horns": true, "glow": "5fd8ff"},
	"spider_fam": {"color": "5a3a6a", "shape": "spider"},
	"arachne": {"color": "8a3a9a", "shape": "spider", "crown": true},
	"wyvern_fam": {"color": "b04a3a", "shape": "dragon"},
	"storm_dragon": {"color": "3a6ac2", "shape": "dragon", "horns": true, "glow": "ffe066"},
}

static var _cache: Dictionary = {}


static func texture(species: String, scale: int = 4) -> ImageTexture:
	var key := species + str(scale)
	if _cache.has(key):
		return _cache[key]
	var look: Dictionary = LOOK.get(species, LOOK.slime_fam)
	var ramp := PixelPalette.ramp(Color(look.color), 4, 0.28)
	var c := PixelCanvas.new(SIZE, SIZE)
	match look.shape:
		"slime":
			c.shaded_ellipse(10, 13, 7.5, 5.5, ramp)
			c.shaded_ellipse(10, 10, 5, 4, ramp)
		"blob":
			c.shaded_ellipse(10, 12, 6.5, 5.5, ramp)
		"quad":
			c.shaded_ellipse(11, 13, 6.5, 3.8, ramp)
			for x in [6, 9, 13, 15]:
				c.rect(x, 16, 1, 3, ramp[0])
			c.shaded_ellipse(6, 9, 4, 3.6, ramp)
		"humanoid":
			c.shaded_ellipse(10, 15, 4.5, 4, ramp)
			c.shaded_ellipse(10, 8, 4.5, 4.2, ramp)
		"bird":
			c.shaded_ellipse(10, 12, 4.5, 5.5, ramp)
			c.put(15, 11, Color("f2c14e"))
			c.put(16, 11, Color("f2c14e"))
		"spider":
			c.shaded_ellipse(10, 12, 5.5, 4.5, ramp)
			for i in 4:
				c.rect(2 + i, 9 + i, 1, 1, ramp[0])
				c.rect(17 - i, 9 + i, 1, 1, ramp[0])
				c.rect(3 + i, 15 + i % 2, 1, 1, ramp[0])
				c.rect(16 - i, 15 + i % 2, 1, 1, ramp[0])
		"dragon":
			c.shaded_ellipse(11, 13, 6, 4.5, ramp)
			c.shaded_ellipse(6, 8, 3.8, 3.4, ramp)
			for i in 5:
				c.put(12 + i, 8 - i / 2, ramp[3])
				c.put(12 + i, 9 - i / 2, ramp[2])
	var head := Vector2i(6, 8) if look.shape in ["quad", "dragon"] else Vector2i(10, 9 if look.shape != "humanoid" else 8)
	match look.get("ears", ""):
		"pointy":
			c.put(head.x - 3, head.y - 4, ramp[2]); c.put(head.x - 3, head.y - 3, ramp[1])
			c.put(head.x + 2, head.y - 4, ramp[1]); c.put(head.x + 2, head.y - 3, ramp[0])
		"floppy":
			c.rect(head.x - 4, head.y - 2, 1, 3, ramp[0]); c.rect(head.x + 3, head.y - 2, 1, 3, ramp[0])
		"round":
			c.put(head.x - 4, head.y - 4, ramp[2]); c.put(head.x + 3, head.y - 4, ramp[1])
	if look.get("horns", false):
		c.put(head.x - 2, head.y - 5, Color("f4f1ea")); c.put(head.x + 1, head.y - 5, Color("f4f1ea"))
	if look.get("crown", false):
		for x in range(head.x - 2, head.x + 3):
			c.put(x, head.y - 5, Color("ffcf4d"))
		c.put(head.x - 2, head.y - 6, Color("ffcf4d")); c.put(head.x, head.y - 6, Color("ffcf4d")); c.put(head.x + 2, head.y - 6, Color("ffcf4d"))
	var eye := Color(look.get("glow", "1a1a24"))
	c.put(head.x - 2, head.y, Color.WHITE); c.put(head.x - 1, head.y, eye)
	c.put(head.x + 1, head.y, Color.WHITE); c.put(head.x + 2, head.y, eye)
	c.selective_outline()
	c.img.resize(SIZE * scale, SIZE * scale, Image.INTERPOLATE_NEAREST)
	var tex := c.to_texture()
	_cache[key] = tex
	return tex
