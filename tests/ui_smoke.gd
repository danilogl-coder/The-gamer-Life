extends SceneTree
## UI smoke test + screenshots (needs a display, e.g. xvfb-run):
##   xvfb-run godot --path . -s res://tests/ui_smoke.gd -- <out_dir>
## Starts a life, plays some years, visits every tab and saves screenshots.

var out_dir := "user://shots"
var main: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	await _shot("00_title")
	var app = root.get_node("App")
	app.start_new_life({"seed": 4242, "sex": "m", "country": "hanseong"})
	main.close_overlays()
	await _frames(5)
	await _shot("01_event")
	for age in 16:
		await _resolve_events()
		for i in 3:
			app.sim.do_activity(["study", "gym", "meditate", "play", "observe_self"][(age + i) % 5])
		app.sim.advance_year()
		await _frames(1)
	await _resolve_events()
	app.sim.state.set_flag("world_revealed")
	app.sim.skills.learn(app.sim.player(), "id_create")
	app.sim.gamer.add_exp(app.sim.player(), 3000)
	app.sim.activities.start_year(app.sim.player())
	app.bus.state_changed.emit()
	await _frames(4)
	for tab in ["life", "system", "relations", "activities", "career", "assets"]:
		main.select_tab(tab)
		await _frames(4)
		await _shot("02_" + tab)
	main.screens["system"]._sub = "skills"
	main.select_tab("system")
	await _frames(4)
	await _shot("03_skills")
	var r: Dictionary = app.sim.do_activity("dungeon", {"dungeon": "slime_cave"})
	main.show_result(r)
	await _frames(6)
	await _shot("04_dungeon")
	main.close_overlays()
	main.select_tab("relations")
	await _frames(3)
	var ids: Array = app.sim.player().rels.keys()
	main.screens["relations"].open_npc(ids[0])
	await _frames(6)
	await _shot("05_npc")
	main.close_overlays()
	app.sim.health.kill(app.sim.player(), "cause.event")
	await _frames(8)
	await _shot("06_death")
	print("UI smoke OK")
	quit(0)


func _resolve_events() -> void:
	var app = root.get_node("App")
	main.close_overlays()
	while app.sim.has_pending_events():
		var c: Array = app.sim.events.visible_choices(app.sim.current_event())
		app.sim.choose(c[0].id)
	await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
