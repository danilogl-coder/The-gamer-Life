extends VBoxContainer
## RELAÇÕES — every persistent NPC bond, grouped. Tap a person to open their
## sheet: what the Observe skill reveals, their memories of you, and actions.

const GROUPS := {
	"family": ["spouse", "mother", "father", "stepparent", "sibling", "child", "grandchild", "grandparent", "late_spouse"],
	"love": ["partner", "fiance", "ex"],
	"friends": ["best_friend", "friend", "mentor"],
	"work": ["boss", "coworker", "teacher", "classmate", "inmate"],
	"others": ["rival", "enemy", "acquaintance"],
}

var ui
var _list: VBoxContainer
var _sheet


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_list = W.vbox(8)
	add_child(W.scroll(_list))


func refresh() -> void:
	W.clear(_list)
	var sim: LifeSimulation = App.sim
	var p := sim.player()
	_render_pets(sim, p)
	for group in GROUPS:
		var ids: Array = []
		for role in GROUPS[group]:
			ids.append_array(_with_role(p, role))
		if ids.is_empty():
			continue
		_list.add_child(W.section(App.t("rolegroup." + group)))
		for id in ids:
			_list.add_child(_npc_row(sim, id))
	if int(p.age) >= 21:
		_list.add_child(W.button(App.t("ui.adopt"), func(): ui.show_result(App.sim.command("adopt")), 76, UiTheme.FONT_S))


func _render_pets(sim: LifeSimulation, p: Dictionary) -> void:
	var living := sim.pets.alive(p)
	if living.is_empty() and int(p.age) < 6:
		return
	_list.add_child(W.section(App.t("ui.pets")))
	for x in living:
		var def := sim.pets.species(x)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_open_pet.bind(x.id))
		var row := W.hbox(12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		var art := TextureRect.new()
		art.texture = CreatureArt.texture(x.species, 4)
		art.custom_minimum_size = Vector2(80, 80)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
		var col := W.vbox(2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag := " ✦" if x.named else ""
		col.add_child(W.label("%s%s" % [x.name, tag], UiTheme.FONT_M, UiTheme.GOLD if def.kind == "familiar" else UiTheme.TEXT))
		var sub := "%s · %s" % [App.t("pet." + x.species), App.t("ui.years_old", {"n": x.age})]
		if def.kind == "familiar":
			sub += " · Lv.%d" % int(x.level)
		col.add_child(W.label(sub, 17, UiTheme.TEXT_DIM))
		col.add_child(W.bar(float(x.bond), 100, UiTheme.GOOD, "", 12))
		row.add_child(col)
		b.add_child(row)
		_list.add_child(b)
	if int(p.age) >= 6:
		_list.add_child(W.button(App.t("ui.adopt_pet"), _open_pet_shop, 72, UiTheme.FONT_S))


func _open_pet_shop() -> void:
	var box := W.vbox(8)
	for id in App.data.table("pets"):
		var def: Dictionary = App.data.get_def("pets", id)
		if def.kind != "pet":
			continue
		var row := W.hbox(10)
		var art := TextureRect.new()
		art.texture = CreatureArt.texture(id, 3)
		art.custom_minimum_size = Vector2(60, 60)
		row.add_child(art)
		row.add_child(W.button("%s · %s" % [App.t("pet." + id), Fmt.money(float(def.cost))], func(): ui.close_overlays(); ui.show_result(App.sim.command("adopt_pet", [id])), 72, UiTheme.FONT_S))
		box.add_child(row)
	box.add_child(W.label(App.t("ui.familiar_hint"), 18, UiTheme.SYSTEM_EDGE, true))
	ui.open_sheet(App.t("ui.adopt_pet"), box)


func _open_pet(pet_id: String) -> void:
	var sim: LifeSimulation = App.sim
	var x := sim.pets.get_pet(sim.player(), pet_id)
	var def := sim.pets.species(x)
	var box := W.vbox(10)
	var head := W.hbox(14)
	var art := TextureRect.new()
	art.texture = CreatureArt.texture(x.species, 6)
	art.custom_minimum_size = Vector2(120, 120)
	head.add_child(art)
	var col := W.vbox(4)
	col.add_child(W.label(App.t("pet." + x.species), UiTheme.FONT_M, UiTheme.SYSTEM_EDGE))
	col.add_child(W.label(App.t("ui.years_old", {"n": x.age}), UiTheme.FONT_S))
	col.add_child(W.bar(float(x.health), 100, UiTheme.HP, App.t("attr.health"), 20))
	col.add_child(W.bar(float(x.bond), 100, UiTheme.GOOD, App.t("ui.relationship"), 20))
	if def.kind == "familiar":
		col.add_child(W.label("Lv.%d · ATK %s" % [int(x.level), Fmt.num(float(def.get("atk", 0)) * (1.0 + float(x.level) * float(def.get("growth", 0.15))))], UiTheme.FONT_S, UiTheme.GOLD))
		if def.has("mods"):
			col.add_child(W.label(Fmt.mods(def.mods), 17, UiTheme.TEXT_DIM, true))
	head.add_child(col)
	box.add_child(head)
	var grid := W.grid(2, 8)
	for action in ["play", "vet", "name", "release"]:
		if action == "name" and (def.kind != "familiar" or x.named or not def.has("named")):
			continue
		var label := App.t("pet.act." + action)
		if action == "name":
			label += " (MP %d)" % int(sim.gamer.max_mp(sim.player()) * 0.8)
		grid.add_child(W.button(label, func(): ui.close_overlays(); ui.show_result(App.sim.command("pet_action", [pet_id, action])), 76, UiTheme.FONT_S))
	box.add_child(grid)
	ui.open_sheet(x.name, box, def.kind == "familiar")


func _with_role(p: Dictionary, role: String) -> Array:
	var out: Array = []
	for id in p.rels:
		if p.rels[id].role == role and App.sim.state.has_npc(id):
			out.append(id)
	out.sort()
	return out


func _npc_row(sim: LifeSimulation, id: String) -> Control:
	var npc: Dictionary = sim.state.npc(id)
	var rel: Dictionary = sim.player().rels[id]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(open_npc.bind(id))
	var row := W.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.add_child(W.portrait(npc, 2))
	var col := W.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dead := "" if npc.alive else " ✝"
	col.add_child(W.label("%s %s%s" % [npc.first_name, npc.last_name, dead], UiTheme.FONT_M, UiTheme.TEXT))
	var lvl := ""
	if int(npc.get("observed", 0)) >= 1 and npc.gamer.get("awakened", false):
		lvl = "  · Lv.%d" % int(npc.gamer.level)
	col.add_child(W.label("%s · %s%s" % [App.t("role." + rel.role), App.t("ui.years_old", {"n": npc.age}), lvl], 17, UiTheme.TEXT_DIM))
	var score := float(rel.score)
	col.add_child(W.bar(score, 100, UiTheme.GOOD if score >= 60 else (UiTheme.WARN if score >= 30 else UiTheme.BAD), "", 14))
	row.add_child(col)
	b.add_child(row)
	return b


func open_npc(id: String) -> void:
	if _sheet and is_instance_valid(_sheet):
		_sheet.close()
	var sim: LifeSimulation = App.sim
	var npc: Dictionary = sim.state.npc(id)
	var box := W.vbox(10)
	var head := W.hbox(14)
	head.add_child(W.portrait(npc, 4))
	var col := W.vbox(4)
	col.add_child(W.label(App.t("role." + sim.relations.role_of(id)), UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	col.add_child(W.label(App.t("ui.years_old", {"n": npc.age}) + (" ✝" if not npc.alive else ""), UiTheme.FONT_S, UiTheme.TEXT))
	var job: String = npc.career.get("job", "")
	col.add_child(W.label(App.t("job." + job) if job != "" else "—", UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	col.add_child(W.bar(sim.relations.score(id), 100, UiTheme.GOOD, App.t("ui.relationship") + " %d" % int(sim.relations.score(id)), 22))
	head.add_child(col)
	box.add_child(head)
	box.add_child(_observe_window(sim, npc))
	var mems: Array = npc.get("memory", [])
	if not mems.is_empty():
		var flow := W.flow()
		for m in mems.slice(-4):
			flow.add_child(W.chip(App.t("mem." + m.m), UiTheme.BAD if float(m.sev) > 0 else UiTheme.GOOD, 16))
		box.add_child(W.label(App.t("ui.remembers"), 17, UiTheme.TEXT_DIM))
		box.add_child(flow)
	var grid := W.grid(2, 8)
	for iid in sim.relations.available_interactions(id):
		var def: Dictionary = App.data.get_def("interactions", iid)
		var label := App.t("int." + iid)
		if int(def.get("time", 0)) > 0:
			label += " ⏱"
		if float(def.get("cost", 0)) > 0:
			label += " " + Fmt.money(float(def.cost))
		if def.has("chance"):
			label += " [%s]" % Fmt.pct(sim.prob.compute(def.chance, {"actor": npc}))
		grid.add_child(W.button(label, _interact.bind(id, iid), 76, UiTheme.FONT_S))
	box.add_child(grid)
	_sheet = ui.open_sheet("%s %s" % [npc.first_name, npc.last_name], box)


## What the Observe skill reveals depends on its level (The Gamer style).
func _observe_window(sim: LifeSimulation, npc: Dictionary) -> Control:
	var lvl := int(npc.get("observed", 0))
	var box := W.vbox(4)
	box.add_child(W.label("[ OBSERVAR ]" if App.loc.locale == "pt" else "[ OBSERVE ]", UiTheme.FONT_S, UiTheme.SYSTEM_EDGE))
	if lvl <= 0:
		box.add_child(W.label(App.t("ui.observe_hint"), UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
		return W.system_card(box)
	var awakened: bool = npc.gamer.get("awakened", false)
	box.add_child(W.label("Lv. %d %s" % [int(npc.gamer.level), App.t("ui.awakened_tag") if awakened else ""], UiTheme.FONT_M, UiTheme.GOLD if awakened else UiTheme.TEXT))
	if lvl >= 2:
		var stats := W.flow(4)
		for s in CharacterFactory.STAT_IDS:
			stats.add_child(W.chip("%s %d" % [App.t("stat." + s), int(npc.gamer.stats[s])], UiTheme.stat_color(s), 16))
		box.add_child(stats)
	if lvl >= 3:
		box.add_child(W.label(App.t("ui.compat", {"n": int(sim.relations.compatibility(npc))}), UiTheme.FONT_S, UiTheme.PURPLE))
	if lvl >= 4:
		var tr := W.flow(4)
		for t in npc.traits:
			tr.add_child(W.chip(App.t("trait." + t), UiTheme.TEXT_DIM, 16))
		box.add_child(tr)
	if lvl >= 6:
		box.add_child(W.label("%s %d · %s %d · %s %s" % [App.t("hidden.loyalty"), int(npc.hidden.loyalty), App.t("hidden.ambition"), int(npc.hidden.ambition), App.t("ui.money"), Fmt.money(float(npc.finance.cash))], UiTheme.FONT_S, UiTheme.TEXT_DIM, true))
	return W.system_card(box)


func _interact(id: String, iid: String) -> void:
	var r: Dictionary = App.sim.interact(id, iid)
	ui.show_result(r)
	if r.get("ok", false) and App.sim.state.has_npc(id) and App.sim.player().rels.has(id) and not App.sim.has_pending_events():
		open_npc(id)
	elif _sheet and is_instance_valid(_sheet):
		_sheet.close()
