extends Control
## Root of the mobile UI. Layout: [screen host] + [bottom tab bar], inside the
## device safe area. Overlays: modal sheets, System event windows, toasts.
## The UI only DISPLAYS state and REQUESTS actions from App.sim.

const TABS := [
	{"id": "life", "icon": "life", "color": Color("e0475a"), "script": preload("res://src/ui/screens/home_screen.gd")},
	{"id": "system", "icon": "system", "color": Color("5fd8ff"), "script": preload("res://src/ui/screens/system_screen.gd")},
	{"id": "relations", "icon": "people", "color": Color("e06fb5"), "script": preload("res://src/ui/screens/relations_screen.gd")},
	{"id": "activities", "icon": "bolt", "color": Color("ffcf4d"), "script": preload("res://src/ui/screens/activities_screen.gd")},
	{"id": "career", "icon": "case", "color": Color("c98e62"), "script": preload("res://src/ui/screens/career_screen.gd")},
	{"id": "assets", "icon": "coin", "color": Color("f2c14e"), "script": preload("res://src/ui/screens/assets_screen.gd")},
]

const EventPopup := preload("res://src/ui/popups/event_popup.gd")
const Sheet := preload("res://src/ui/popups/sheet.gd")
const ToastLayer := preload("res://src/ui/popups/toast_layer.gd")
const TitleScreen := preload("res://src/ui/popups/title_screen.gd")
const DeathScreen := preload("res://src/ui/popups/death_screen.gd")
const DebugPanel := preload("res://src/ui/popups/debug_panel.gd")

var safe: MarginContainer
var host: Control
var tab_bar: HBoxContainer
var overlay: Control
var toasts
var screens: Dictionary = {}
var tab_buttons: Dictionary = {}
var current_tab := ""
var _dirty := true
var _event_open := false


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	safe = MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	var col := W.vbox(0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe.add_child(col)
	host = Control.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	col.add_child(host)
	tab_bar = W.hbox(4)
	tab_bar.custom_minimum_size = Vector2(0, 108)
	col.add_child(tab_bar)
	for tab in TABS:
		_add_tab(tab)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	toasts = ToastLayer.new()
	add_child(toasts)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	App.bus.state_changed.connect(func(): _dirty = true)
	App.bus.system_notice.connect(_on_notice)
	App.bus.character_died.connect(func(_s): _show_death.call_deferred())
	App.bus.new_life_started.connect(func(): select_tab("life"))
	_show_title()


func _process(_delta: float) -> void:
	toasts.set_top(overlay.get_child_count() > 0)
	if _dirty:
		_dirty = false
		refresh()
	if not _event_open and App.sim.has_pending_events() and overlay.get_child_count() == 0:
		show_next_event()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_background() -> void:
	var bg := TextureRect.new()
	var c := PixelCanvas.new(90, 160)
	c.dither_gradient(Color("141a36"), UiTheme.BG, 6)
	bg.texture = c.to_texture()
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)


func _apply_safe_area() -> void:
	var win := DisplayServer.window_get_size()
	var safe_rect := DisplayServer.get_display_safe_area()
	var vp := get_viewport_rect().size
	var margin := {"left": 12, "right": 12, "top": 12, "bottom": 8}
	if win.x > 0 and win.y > 0 and OS.has_feature("mobile"):
		var sx := vp.x / win.x
		var sy := vp.y / win.y
		margin.left = maxi(12, int(safe_rect.position.x * sx))
		margin.top = maxi(12, int(safe_rect.position.y * sy))
		margin.right = maxi(12, int((win.x - safe_rect.end.x) * sx))
		margin.bottom = maxi(8, int((win.y - safe_rect.end.y) * sy))
	for side in margin:
		safe.add_theme_constant_override("margin_" + side, margin[side])


func _add_tab(tab: Dictionary) -> void:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 104)
	b.icon = PixelIcons.texture(tab.icon, tab.color)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 42)
	b.add_theme_font_size_override("font_size", 17)
	b.text = App.t("tab." + tab.id)
	b.pressed.connect(select_tab.bind(tab.id))
	tab_bar.add_child(b)
	tab_buttons[tab.id] = b


func select_tab(id: String) -> void:
	if not screens.has(id):
		var def: Dictionary = {}
		for t in TABS:
			if t.id == id:
				def = t
		var screen: Control = def.script.new()
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.set("ui", self)
		host.add_child(screen)
		screens[id] = screen
	for k in screens:
		screens[k].visible = k == id
	current_tab = id
	for k in tab_buttons:
		var sel: bool = k == id
		tab_buttons[k].add_theme_stylebox_override("normal", UiTheme.frame(UiTheme.SYSTEM if sel else UiTheme.PANEL, false, UiTheme.SYSTEM_EDGE if sel else Color(0, 0, 0, 0)))
	_dirty = true


func refresh() -> void:
	for id in tab_buttons:
		tab_buttons[id].text = App.t("tab." + id)
	if screens.has(current_tab) and App.sim.player().size() > 0:
		screens[current_tab].refresh()


# ---------------------------------------------------------------------------
# Overlays
# ---------------------------------------------------------------------------

func open_sheet(title: String, content: Control, system_style: bool = false) -> Control:
	var sheet = Sheet.new()
	overlay.add_child(sheet)
	sheet.setup(title, content, system_style)
	return sheet


func close_overlays() -> void:
	W.clear(overlay)


func show_next_event() -> void:
	if not App.sim.has_pending_events():
		return
	_event_open = true
	var popup = EventPopup.new()
	overlay.add_child(popup)
	popup.setup(App.sim.current_event())
	popup.closed.connect(func(): _event_open = false; _dirty = true)


## Shows the outcome of an action: short outcomes become toasts, long ones
## (dungeon logs, failures with reasons) open a System window.
func show_result(result: Dictionary) -> void:
	if not result.get("ok", false):
		toasts.push("warn", App.t(result.get("reason", "ui.invalid")), [])
		return
	var text := App.tr_entry(result) if result.get("key", "") != "" else ""
	var chips := Fmt.gains(result.get("gains", {}))
	if result.has("log"):
		var box := W.vbox(6)
		for line in result.log:
			box.add_child(W.label(App.tr_entry(line), UiTheme.FONT_S, UiTheme.TEXT, true))
		var flow := W.flow()
		for c in chips:
			flow.add_child(W.chip(c.text, c.color))
		box.add_child(flow)
		open_sheet(text, box, true)
		return
	toasts.push("result", text, chips)


func _on_notice(kind: String, payload: String) -> void:
	var entry = JSON.parse_string(payload)
	if typeof(entry) == TYPE_DICTIONARY:
		toasts.push(kind, App.tr_entry(entry), [])


func _show_title() -> void:
	close_overlays()
	var t = TitleScreen.new()
	overlay.add_child(t)
	t.setup(self)


func _show_death() -> void:
	close_overlays()
	var d = DeathScreen.new()
	overlay.add_child(d)
	d.setup(self)


func open_debug() -> void:
	var panel = DebugPanel.new()
	panel.ui = self
	open_sheet("DEV", panel)
