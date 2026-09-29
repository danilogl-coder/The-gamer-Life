class_name Fmt
extends RefCounted
## Display formatting helpers (numbers, money, gains). Pure presentation.


static func money(v: float) -> String:
	var sign := "-" if v < 0.0 else ""
	var a := absf(v)
	if a >= 1.0e9:
		return "%s$%.2fB" % [sign, a / 1.0e9]
	if a >= 1.0e6:
		return "%s$%.2fM" % [sign, a / 1.0e6]
	if a >= 1.0e4:
		return "%s$%.1fK" % [sign, a / 1.0e3]
	return "%s$%d" % [sign, int(a)]


static func num(v: float) -> String:
	var a := absf(v)
	if a >= 1.0e9:
		return "%.2fB" % (v / 1.0e9)
	if a >= 1.0e6:
		return "%.2fM" % (v / 1.0e6)
	if a >= 1.0e4:
		return "%.1fK" % (v / 1.0e3)
	return str(int(v))


static func signed(v: float) -> String:
	return ("+" if v >= 0.0 else "") + num(v)


static func pct(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))


## Turns an action/event "gains" dictionary into short coloured chips.
## Returns [{text, color}].
static func gains(g: Dictionary) -> Array:
	var out: Array = []
	for k in g:
		var v = g[k]
		if typeof(v) in [TYPE_INT, TYPE_FLOAT] and absf(float(v)) < 0.01:
			continue
		var key: String = k
		if key == "exp":
			out.append({"text": "EXP %s" % signed(v), "color": UiTheme.EXP})
		elif key == "money":
			out.append({"text": money(v), "color": UiTheme.GOLD if v >= 0 else UiTheme.BAD})
		elif key == "points":
			out.append({"text": App.t("ui.points_gain", {"n": int(v)}), "color": UiTheme.GOLD})
		elif key.begins_with("sxp:"):
			var s := key.substr(4)
			out.append({"text": "%s xp+%d" % [App.t("stat." + s), int(v)], "color": UiTheme.stat_color(s)})
		elif key.begins_with("stat:"):
			var s := key.substr(5)
			out.append({"text": "%s %s" % [App.t("stat." + s), signed(v)], "color": UiTheme.stat_color(s)})
		elif key.begins_with("attr:"):
			var a := key.substr(5)
			var good := float(v) > 0.0 if a != "stress" else float(v) < 0.0
			out.append({"text": "%s %s" % [App.t("attr." + a), signed(v)], "color": UiTheme.GOOD if good else UiTheme.BAD})
		elif key.begins_with("item:"):
			out.append({"text": "+%d %s" % [int(v), App.t("item." + key.substr(5))], "color": UiTheme.PURPLE})
		elif key == "rel":
			out.append({"text": "♥ %s" % signed(v), "color": UiTheme.GOOD if v > 0 else UiTheme.BAD})
		elif key == "baby" and int(v) > 0:
			out.append({"text": App.t("ui.baby"), "color": UiTheme.GOLD})
	return out


## Localized description of a modifier table, e.g. "+4% estudo".
static func mods(m: Dictionary, scale: float = 1.0) -> String:
	var parts: Array = []
	for k in m:
		var v := float(m[k]) * scale
		var key: String = k
		if key.begins_with("statpct."):
			var s := key.substr(8)
			var label := App.t("ui.all_stats") if s == "all" else App.t("stat." + s)
			parts.append("%s %s" % [label, _pct_signed(v)])
		elif key.begins_with("stat."):
			parts.append("%s %s" % [App.t("stat." + key.substr(5)), ("+" if v >= 0 else "") + ("%.1f" % v).trim_suffix(".0")])
		elif key.begins_with("train_gain."):
			parts.append("%s %s %s" % [App.t("mod.train_gain"), App.t("stat." + key.substr(11)), _pct_signed(v)])
		elif key in ["atk", "def", "mind_immune", "death_save", "time_slots"]:
			parts.append("%s %s" % [App.t("mod." + key), ("+" if v >= 0 else "") + str(int(v)) if key in ["atk", "def", "time_slots"] else ""])
		else:
			parts.append("%s %s" % [App.t("mod." + key), _pct_signed(v)])
	return ", ".join(parts)


static func _pct_signed(v: float) -> String:
	return ("+" if v >= 0 else "") + ("%.1f%%" % (v * 100.0)).replace(".0%", "%")
