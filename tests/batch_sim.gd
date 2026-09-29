extends SceneTree
## Automated balance simulation. Plays N complete lives with a simple bot and
## prints aggregate statistics to catch broken balance.
##   godot --headless --path . -s res://tests/batch_sim.gd -- 1000 [grinder]

var data: DataRegistry


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 200
	var grinder := args.size() > 1 and args[1] == "grinder"
	data = DataRegistry.new().load_all()
	var st := {"death_age": 0.0, "worth": 0.0, "married": 0, "children": 0.0, "crime": 0, "prison": 0,
		"level18": 0.0, "level40": 0.0, "level_end": 0.0, "rank1": 0, "rank2": 0, "revealed": 0,
		"unemployed40": 0, "alive40": 0, "worths": [], "special": {}, "uni": 0, "dungeon_deaths": 0, "jobs": {}, "causes": {}, "events": 0}
	var t0 := Time.get_ticks_msec()
	for i in n:
		_life(1000 + i, grinder, st)
	var f := float(n)
	print("=== %d lives (%s) in %.1fs ===" % [n, "grinder" if grinder else "casual", (Time.get_ticks_msec() - t0) / 1000.0])
	print("avg death age      %.1f" % (st.death_age / f))
	st.worths.sort()
	print("net worth avg %.0f  median %.0f" % [st.worth / f, st.worths[st.worths.size() / 2]])
	print("married            %.0f%%" % (st.married * 100.0 / f))
	print("avg children       %.2f" % (st.children / f))
	print("university grads   %.0f%%" % (st.uni * 100.0 / f))
	print("unemployed at 40   %.0f%% (of alive)" % (st.unemployed40 * 100.0 / maxf(1, st.alive40)))
	print("committed crime    %.0f%%  prison %.0f%%" % [st.crime * 100.0 / f, st.prison * 100.0 / f])
	print("level @18 %.1f  @40 %.1f  @death %.1f" % [st.level18 / f, st.level40 / maxf(1, st.alive40), st.level_end / f])
	print("rank1 %.0f%%  rank2 %.0f%%  world revealed %.0f%%" % [st.rank1 * 100.0 / f, st.rank2 * 100.0 / f, st.revealed * 100.0 / f])
	print("dungeon deaths     %.1f%%" % (st.dungeon_deaths * 100.0 / f))
	print("events per life    %.1f" % (st.events / f))
	print("causes: ", _top(st.causes, 8))
	print("jobs:   ", _top(st.jobs, 12))
	print("special:", _top(st.special, 12))
	quit()


func _top(d: Dictionary, k: int) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	var parts: Array = []
	for key in keys.slice(0, k):
		parts.append("%s=%d" % [key, d[key]])
	return ", ".join(parts)


func _life(seed: int, grinder: bool, st: Dictionary) -> void:
	var sim := LifeSimulation.new(data)
	sim.new_life(seed)
	var bot := RandomNumberGenerator.new()
	bot.seed = seed * 7
	var guard := 0
	while not sim.is_dead() and guard < 140:
		guard += 1
		_resolve(sim, bot)
		_play_year(sim, bot, grinder)
		_resolve(sim, bot)
		var p := sim.player()
		if int(p.age) == 18:
			st.level18 += p.gamer.level
		if int(p.age) == 40:
			st.alive40 += 1
			st.level40 += p.gamer.level
			if p.career.job == "":
				st.unemployed40 += 1
		sim.advance_year()
	var p := sim.player()
	st.death_age += p.age
	st.worth += sim.finance.net_worth(p)
	st.worths.append(sim.finance.net_worth(p))
	st.married += 1 if sim.state.counter("social.marriages") > 0 else 0
	st.children += sim.state.counter("family.children")
	st.crime += 1 if sim.state.counter("crime.total") > 0 else 0
	st.prison += 1 if sim.state.counter("prison.sentences") > 0 else 0
	st.level_end += p.gamer.level
	st.rank1 += 1 if int(p.gamer.rank) >= 1 else 0
	st.rank2 += 1 if int(p.gamer.rank) >= 2 else 0
	st.revealed += 1 if sim.state.flag("world_revealed", false) else 0
	st.uni += 1 if sim.education.has_completed(p, "any_university") else 0
	st.events += sim.state.counter("events.resolved")
	var cause: String = p.get("death_cause", "?")
	st.causes[cause] = int(st.causes.get(cause, 0)) + 1
	if cause == "cause.dungeon":
		st.dungeon_deaths += 1
	for k in ["music.albums", "sport.titles", "biz.sold", "pets.pet", "pets.familiar", "pets.named"]:
		st.special[k] = int(st.special.get(k, 0)) + sim.state.counter(k)
	for k in sim.state.data.counters:
		if str(k).begins_with("sc.start."):
			st.special[k] = int(st.special.get(k, 0)) + 1
	for h in p.career.history:
		st.jobs[h.job] = int(st.jobs.get(h.job, 0)) + 1


func _resolve(sim: LifeSimulation, bot: RandomNumberGenerator) -> void:
	var guard := 0
	while sim.has_pending_events() and guard < 30:
		guard += 1
		var c: Array = sim.events.visible_choices(sim.current_event())
		sim.choose(c[bot.randi_range(0, c.size() - 1)].id)


func _play_year(sim: LifeSimulation, bot: RandomNumberGenerator, grinder: bool) -> void:
	var p := sim.player()
	sim.command("auto_allocate")
	var age := int(p.age)
	if age >= 18 and p.career.job == "" and not sim.crime.in_prison(p):
		if p.education.stage == "" and not sim.education.has_completed(p, "any_university") and bot.randf() < 0.35:
			var unis: Array = []
			for id in data.table("education"):
				if sim.education.enroll_block_reason(p, id) == "":
					unis.append(id)
			if not unis.is_empty():
				sim.command("enroll", [unis[bot.randi_range(0, unis.size() - 1)]])
		if p.education.stage == "" or age >= 23:
			var open: Array = []
			for id in data.table("jobs"):
				if sim.career.block_reason(p, id) == "":
					open.append(id)
			open.sort_custom(func(a, b): return float(data.get_def("jobs", a).salary) > float(data.get_def("jobs", b).salary))
			for id in open.slice(0, 4):
				if sim.command("apply_job", [id]).ok:
					break
	_romance(sim, bot, p)
	_special(sim, bot, p)
	var cats := ["system", "mind", "body", "leisure", "love", "work", "health", "crime", "prison"]
	var guard := 0
	while sim.activities.free_slots(p) > 0 and guard < 20 and not sim.is_dead() and not sim.has_pending_events():
		guard += 1
		if grinder and sim.skills.knows(p, "id_create") and float(p.gamer.mp) >= 20.0:
			var best := ""
			for d in sim.dungeons.available(p):
				if int(d.danger) <= 1:
					best = d.id
			if best != "":
				sim.do_activity("dungeon", {"dungeon": best})
				if float(p.gamer.hp) < sim.gamer.max_hp(p) * 0.4 and sim.activities.free_slots(p) > 0:
					sim.do_activity("sleep_well")
				continue
		var options: Array = []
		for c in cats:
			for e in sim.activities.list(c):
				if e.locked == "" and not str(e.id).begins_with("crime_") or bot.randf() < 0.01:
					if e.locked == "" and e.id != "dungeon":
						options.append(e.id)
		if options.is_empty():
			break
		sim.do_activity(options[bot.randi_range(0, options.size() - 1)])


func _special(sim: LifeSimulation, bot: RandomNumberGenerator, p: Dictionary) -> void:
	if sim.special.active(p).is_empty() and bot.randf() < 0.04:
		var ids := sim.special.ids()
		sim.command("sc_start", [ids[bot.randi_range(0, ids.size() - 1)]])
	if int(p.age) >= 8 and sim.pets.alive(p).is_empty() and bot.randf() < 0.05:
		sim.command("adopt_pet", ["dog" if bot.randf() < 0.5 else "cat"])
	for id in sim.special.active(p):
		var acts: Array = sim.special.actions(p, id).filter(func(a): return a.locked == "" and a.id not in ["retire", "sell", "fire"])
		if not acts.is_empty() and bot.randf() < 0.7:
			sim.command("sc_action", [id, acts[bot.randi_range(0, acts.size() - 1)].id])


func _romance(sim: LifeSimulation, bot: RandomNumberGenerator, p: Dictionary) -> void:
	for id in p.rels.keys():
		if not sim.state.has_npc(id):
			continue
		var role: String = p.rels[id].role
		var action := ""
		match role:
			"partner": action = "date" if bot.randf() < 0.6 else "propose"
			"fiance": action = "marry"
			"spouse": action = "try_baby" if bot.randf() < 0.4 else "date"
			"mother", "father", "child", "best_friend": action = "spend_time" if bot.randf() < 0.3 else "talk"
		if action != "" and sim.relations.available_interactions(id).has(action):
			sim.interact(id, action)
