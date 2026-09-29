class_name UiTheme
extends RefCounted
## Pixel-art UI theme generated entirely in code. Frames are drawn at "art
## pixel" resolution and upscaled with nearest filtering (PX screen px per art
## pixel) so every border stays crisp on any phone.

const PX := 3

# Colour tokens
const BG := Color("0b0e1c")
const BG2 := Color("12172b")
const PANEL := Color("1b2242")
const PANEL_HI := Color("283466")
const SYSTEM := Color("0c2c4e")
const SYSTEM_EDGE := Color("5fd8ff")
const TEXT := Color("e9edff")
const TEXT_DIM := Color("8f99c9")
const GOLD := Color("ffcf4d")
const HP := Color("e0475a")
const MP := Color("4f8fe0")
const EXP := Color("8be04f")
const GOOD := Color("6cd26a")
const BAD := Color("ff6a5a")
const WARN := Color("ffa84d")
const PURPLE := Color("b07cff")

const FONT_S := 20
const FONT_M := 24
const FONT_L := 30
const FONT_XL := 40

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_M
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.2))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("normal", "Button", frame(PANEL_HI, false))
	t.set_stylebox("hover", "Button", frame(PANEL_HI.lightened(0.08), false))
	t.set_stylebox("pressed", "Button", frame(PANEL_HI.darkened(0.15), true))
	t.set_stylebox("disabled", "Button", frame(PANEL.darkened(0.2), false))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", frame(PANEL, false))
	t.set_stylebox("panel", "Panel", frame(PANEL, false))
	t.set_stylebox("normal", "LineEdit", frame(BG2, true))
	t.set_stylebox("focus", "LineEdit", frame(BG2, true))
	t.set_color("font_color", "LineEdit", TEXT)
	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Color(1, 1, 1, 0.18)
	t.set_stylebox("grabber", "VScrollBar", scroll)
	t.set_stylebox("grabber_highlight", "VScrollBar", scroll)
	t.set_stylebox("grabber_pressed", "VScrollBar", scroll)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("grabber", "HScrollBar", StyleBoxEmpty.new())
	_theme = t
	return t


## Bevelled pixel frame: light top-left, shadow bottom-right, notched corners.
## `inset` flips the bevel (pressed look).
static func frame(fill: Color, inset: bool, edge: Color = Color(0, 0, 0, 0), alpha: float = 1.0) -> StyleBoxTexture:
	var ramp := PixelPalette.ramp(fill, 4, 0.18)
	var hi: Color = ramp[3] if not inset else ramp[0]
	var lo: Color = ramp[0] if not inset else ramp[3]
	var outline := edge if edge.a > 0.0 else PixelPalette.outline_of(ramp[0])
	var n := 7
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var corner := (x == 0 or x == n - 1) and (y == 0 or y == n - 1)
			if corner:
				continue
			var c := Color(fill.r, fill.g, fill.b, alpha)
			if x == 0 or y == 0 or x == n - 1 or y == n - 1:
				c = outline
			elif x == 1 or y == 1:
				c = Color(hi.r, hi.g, hi.b, maxf(alpha, 0.9))
			elif x == n - 2 or y == n - 2:
				c = Color(lo.r, lo.g, lo.b, maxf(alpha, 0.9))
			img.set_pixel(x, y, c)
	img.resize(n * PX, n * PX, Image.INTERPOLATE_NEAREST)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	var m := 3 * PX
	sb.texture_margin_left = m
	sb.texture_margin_top = m
	sb.texture_margin_right = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = m + 6
	sb.content_margin_right = m + 6
	sb.content_margin_top = m + 2
	sb.content_margin_bottom = m + 2
	return sb


## The Gamer's iconic floating blue status window.
static func system_frame() -> StyleBoxTexture:
	var sb := frame(SYSTEM, false, SYSTEM_EDGE, 0.94)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	return sb


static func flat(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	return sb


static func stat_color(stat: String) -> Color:
	match stat:
		"str": return Color("e05a47")
		"vit": return Color("6cc24a")
		"dex": return Color("f2c14e")
		"int": return Color("4fa3e0")
		"wis": return Color("9b6ee0")
		"luk": return Color("4ee0c1")
		"cha": return Color("e06fb5")
	return TEXT


static func tier_color(tier: String) -> Color:
	match tier:
		"extra": return Color("4fd1ff")
		"unique": return Color("c77dff")
		"ultimate": return GOLD
	return TEXT
