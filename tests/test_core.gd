extends TestBase
## Core services and data integrity.


func test_rng_is_deterministic() -> void:
	var a := RngService.new(123)
	var b := RngService.new(123)
	for i in 50:
		check(a.randf() == b.randf(), "rng diverged at %d" % i)
	var state := a.get_state()
	var x := a.randf()
	a.set_state(state)
	check(a.randf() == x, "rng state restore failed")


func test_conditions() -> void:
	var sim := new_sim()
	var p := sim.player()
	check(sim.cond.check({"path": "player.age", "op": "==", "value": 0}, {}), "age == 0")
	check(sim.cond.check({"all": [{"path": "player.age", "op": ">=", "value": 0}, {"not": {"path": "player.age", "op": ">", "value": 5}}]}, {}), "all/not")
	check(sim.cond.check({"any": [{"path": "player.age", "op": ">", "value": 99}, {"path": "calc.level", "op": ">=", "value": 1}]}, {}), "any")
	check(sim.cond.check({"path": "player.gamer.skills", "op": "has", "value": "observe"}, {}), "has skill dict key")
	check(not sim.cond.check({"path": "flag.nope", "op": "==", "value": true}, {}), "missing flag false")
	check(sim.cond.check({"path": "skill.observe", "op": ">=", "value": 1}, {}), "skill path")
	check(p.gamer.level == 1, "starts at level 1")


func test_probability_bounds() -> void:
	var sim := new_sim()
	var p := sim.prob.compute({"base": 2.0, "max": 0.9})
	check(p <= 0.9, "clamped max")
	p = sim.prob.compute({"base": -1.0, "min": 0.05})
	check(p >= 0.05, "clamped min")


func test_save_load_roundtrip_is_deterministic() -> void:
	var a := new_sim(777)
	live_years(a, 12)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(a.snapshot()))
	snap = SaveSystem.normalize(snap)
	var b := LifeSimulation.new(data)
	b.load_state(SaveSystem.migrate(snap))
	live_years(a, 8)
	live_years(b, 8)
	check(a.player().age == b.player().age, "age matches after load")
	check(is_equal_approx(float(a.player().finance.cash), float(b.player().finance.cash)), "cash matches after load")
	check(a.player().gamer.level == b.player().gamer.level, "level matches after load")
	check(a.state.data.timeline.size() == b.state.data.timeline.size(), "timeline matches after load")


func test_migration_runs() -> void:
	var d := {"save_version": 0}
	SaveSystem.migrate(d)
	check(int(d.save_version) == GameState.SAVE_VERSION, "migrated to current version")


func test_data_references_are_valid() -> void:
	var skills := data.table("skills")
	var items := data.table("items")
	for id in data.table("activities"):
		var a: Dictionary = data.table("activities")[id]
		for s in a.get("skill_xp", {}):
			check(skills.has(s), "activity %s -> unknown skill %s" % [id, s])
		if a.has("crime"):
			check(data.table("crimes").has(a.crime), "activity %s -> unknown crime" % id)
	for id in data.table("monsters"):
		var m: Dictionary = data.table("monsters")[id]
		for d in m.get("drops", []):
			check(items.has(d.item), "monster %s -> unknown item %s" % [id, d.item])
		if m.has("absorb"):
			check(skills.has(m.absorb), "monster %s -> unknown absorb skill" % id)
	for id in data.table("dungeons"):
		for mid in data.table("dungeons")[id].monsters:
			check(data.table("monsters").has(mid), "dungeon %s -> unknown monster %s" % [id, mid])
	for id in skills:
		var s: Dictionary = skills[id]
		if s.has("evolves_to"):
			check(skills.has(s.evolves_to), "skill %s evolves to unknown" % id)
		for src in s.get("fusion", {}).get("from", []):
			check(skills.has(src), "fusion %s unknown source %s" % [id, src])
	for id in data.table("jobs"):
		for e in data.table("jobs")[id].get("education", []):
			check(e == "any_university" or data.table("education").has(e), "job %s unknown education %s" % [id, e])
	_check_effect_refs()


func _check_effect_refs() -> void:
	var lists: Array = []
	for id in data.events:
		var ev: Dictionary = data.events[id]
		lists.append(ev.get("effects", []))
		for c in ev.get("choices", []):
			lists.append(c.get("effects", []))
			lists.append(c.get("success", {}).get("effects", []))
			lists.append(c.get("fail", {}).get("effects", []))
	for t in ["activities", "quests", "items", "interactions"]:
		for id in data.table(t):
			var def: Dictionary = data.table(t)[id]
			for key in ["effects", "rewards", "penalty", "use"]:
				lists.append(def.get(key, []))
			lists.append(def.get("success", {}).get("effects", []))
			lists.append(def.get("fail", {}).get("effects", []))
	var stack := lists.duplicate()
	while not stack.is_empty():
		var list = stack.pop_back()
		for e in list:
			match e.get("type", ""):
				"TRIGGER_EVENT", "SCHEDULE_EVENT":
					check(data.events.has(e.event), "unknown event ref %s" % e.event)
				"LEARN_SKILL", "SKILL_XP":
					check(data.table("skills").has(e.skill), "unknown skill ref %s" % e.skill)
				"ADD_ITEM":
					check(data.table("items").has(e.item), "unknown item ref %s" % e.item)
				"ADD_DISEASE", "REMOVE_DISEASE":
					check(data.table("diseases").has(e.disease), "unknown disease ref %s" % e.disease)
				"START_JOB":
					check(data.table("jobs").has(e.job), "unknown job ref %s" % e.job)
				"START_QUEST":
					check(data.table("quests").has(e.quest), "unknown quest ref %s" % e.quest)
				"GRANT_TITLE":
					check(data.table("titles").has(e.title), "unknown title ref %s" % e.title)
				"JOIN_FACTION", "FACTION_REP":
					check(data.table("factions").has(e.faction), "unknown faction %s" % e.faction)
				"CHANCE":
					stack.append(e.get("effects", []))
					stack.append(e.get("else", []))


func test_locale_keys_exist() -> void:
	for code in ["pt", "en"]:
		var loc := Localization.new(code)
		for id in data.events:
			for k in ["title", "desc"]:
				check(loc.has("ev.%s.%s" % [id, k]), "[%s] missing ev.%s.%s" % [code, id, k])
		for t in ["skills", "titles", "jobs", "activities", "items", "diseases", "monsters", "dungeons", "education", "traits", "crimes", "achievements", "quests", "world_events", "properties", "factions", "countries", "interactions"]:
			var prefix: String = {"skills": "skill", "titles": "title", "jobs": "job", "activities": "act", "items": "item",
				"diseases": "disease", "monsters": "mon", "dungeons": "dng", "education": "edu", "traits": "trait",
				"crimes": "crime", "achievements": "ach", "quests": "quest", "world_events": "wevent",
				"properties": "prop", "factions": "faction", "countries": "country", "interactions": "int"}[t]
			for id in data.table(t):
				var key := "%s.%s" % [prefix, id]
				if t in ["achievements", "quests", "world_events"]:
					key += ".title"
				check(loc.has(key), "[%s] missing %s" % [code, key])
