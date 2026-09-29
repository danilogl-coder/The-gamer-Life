class_name PixelPalette
extends RefCounted
## Colour ramps built with HUE SHIFTING (classic pixel-art technique):
## shadows slide towards blue/purple and gain saturation, highlights slide
## towards warm yellow and lose saturation. This avoids the muddy look of
## simply darkening/lightening a colour.

const SHADOW_HUE := 0.70   # blue-violet
const LIGHT_HUE := 0.14    # warm yellow

## Returns `steps` colours from darkest to lightest around `base`.
static func ramp(base: Color, steps: int = 4, spread: float = 0.34) -> Array:
	var out: Array = []
	var mid := (steps - 1) / 2.0
	for i in steps:
		var t := (i - mid) / maxf(mid, 1.0)   # -1 (shadow) .. +1 (light)
		var c := base
		var h := c.h
		if t < 0.0:
			h = _hue_towards(h, SHADOW_HUE, -t * 0.05)
			c = Color.from_hsv(h, clampf(c.s + (-t) * 0.12, 0, 1), clampf(c.v + t * spread, 0.04, 1))
		else:
			h = _hue_towards(h, LIGHT_HUE, t * 0.05)
			c = Color.from_hsv(h, clampf(c.s - t * 0.18, 0, 1), clampf(c.v + t * spread * 0.8, 0, 1))
		out.append(c)
	return out


static func _hue_towards(h: float, target: float, amount: float) -> float:
	var d := target - h
	if d > 0.5:
		d -= 1.0
	elif d < -0.5:
		d += 1.0
	return fposmod(h + d * clampf(amount * 3.0, 0.0, 1.0), 1.0)


## Outline colour for a region: darker, cooler version of its shadow tone.
static func outline_of(c: Color) -> Color:
	return Color.from_hsv(_hue_towards(c.h, SHADOW_HUE, 0.1), clampf(c.s + 0.15, 0, 1), c.v * 0.35)


# Curated base colours (index-addressable so genomes stay tiny ints).
const SKIN := [Color("f6d3b3"), Color("e9b48a"), Color("c98e62"), Color("a5683f"), Color("7a4a2c"), Color("5a3520")]
const HAIR := [Color("2b2220"), Color("5b3a26"), Color("a0662f"), Color("e0b24a"), Color("c44a2c"), Color("dcdcdc"), Color("3b4fa8"), Color("8e3fa8")]
const EYES := [Color("4a3020"), Color("3a78c2"), Color("3f9a5a"), Color("7a5a2a"), Color("9a3fc2")]
const BG := [Color("2d4a7a"), Color("5a3a7a"), Color("2d6a5a"), Color("7a4a2d"), Color("3a3a5a"), Color("6a2d4a")]
const CLOTH := [Color("3a6ec2"), Color("c23a4a"), Color("3aa26a"), Color("c2a23a"), Color("6a4ac2"), Color("3a3a3a")]
