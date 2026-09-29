extends TestBase
## Systems added to reach BitLife-level depth.


func _adult(seed: int) -> LifeSimulation:
	var sim := new_sim(seed)
	drain_events(sim)
	var p := sim.player()
	p.age = 25
	p.finance.cash = 500000.0
	for s in CharacterFactory.STAT_IDS:
		p.gamer.stats[s] = 25.0
	sim.activities.start_year(p)
	return sim


func test_school_clubs_and_popularity() -> void:
	var sim := new_sim(41)
	drain_events(sim)
	var p := sim.player()
	p.age = 13
	p.education.stage = "middle"
	sim.activities.start_year(p)
	check(sim.command("join_club", ["chess"]).ok, "join club")
	for y in 4:
		for i in 3:
			p.time.used = 0
			sim.command("practice_club", ["chess"])
		sim.school_life.process_year(p)
	check(int(p.school.clubs.chess.rank) >= 1, "club rank rises: %s" % [p.school.clubs])
	p.school.popularity = 90.0
	p.gamer.stats.int = 30.0
	var tries := 0
	while p.school.clique == "" and tries < 20:
		tries += 1
		sim.command("join_clique", ["nerds"])
	check(p.school.clique == "nerds", "joined clique")
	check(sim.gamer.mod("study_gain") > 0.0, "clique gives modifiers")


func test_interview_answers_matter() -> void:
	var sim := _adult(42)
	var p := sim.player()
	var good := sim.career.interview_score(p, {"q_weakness": "honest", "q_why_us": "research"})
	var bad := sim.career.interview_score(p, {"q_weakness": "none", "q_why_us": "money"})
	check(good > bad, "good answers score higher (%f vs %f)" % [good, bad])
	check(sim.career.interview_questions().size() == 2, "two questions drawn")


func test_work_hours_change_salary() -> void:
	var sim := _adult(43)
	var p := sim.player()
	sim.career.hire(p, "janitor", true)
	var normal := sim.career.current_salary(p)
	sim.command("set_hours", ["overtime"])
	check(sim.career.current_salary(p) > normal, "overtime pays more")
	sim.activities.start_year(p)
	var over_slots := int(p.time.slots)
	sim.command("set_hours", ["part"])
	sim.activities.start_year(p)
	check(int(p.time.slots) > over_slots, "part-time leaves more free time")


func test_dating_app_flow() -> void:
	var sim := _adult(44)
	var ids: Array = sim.command("dating_candidates").ids
	check(ids.size() == 3, "three profiles")
	var matched := false
	for i in 30:
		if matched:
			break
		sim.player().time.used = 0
		ids = sim.dating.candidates()
		matched = sim.command("dating_pick", [ids[0]]).ok
	check(matched, "eventually matches")
	check(sim.relations.partner_id(sim.player()) != "", "has partner after match")


func test_surrogacy_and_ivf() -> void:
	var sim := _adult(45)
	var p := sim.player()
	var born := 0
	for i in 10:
		born += sim.relations.conceive("", "surrogate")
	check(born >= 5, "surrogacy works for singles (%d)" % born)
	check(sim.relations.count_role(p, "child") == born, "children registered")


func test_will_favorite_child_gets_most() -> void:
	var sim := _adult(46)
	var p := sim.player()
	var partner: Dictionary = sim.factory.spawn_contextual("partner", {"sex": "opposite"})
	var mother := p if p.sex == "f" else partner
	var father := partner if p.sex == "f" else p
	var a: Dictionary = sim.factory.create_child(mother, father)
	var b: Dictionary = sim.factory.create_child(mother, father)
	sim.relations.ensure(a.id, "child", 80)
	sim.relations.ensure(b.id, "child", 80)
	sim.gamer.add_item(p, "lucky_dice")
	sim.command("set_will", ["favorite", b.id])
	p.finance.cash = 1000000.0
	sim.health.kill(p, "cause.event")
	check(sim.state.data.death.has("ribbon"), "ribbon awarded")
	sim.legacy.continue_as(a.id)
	check(float(b.finance.cash) > float(a.finance.cash), "favorite child inherited more")
	check(sim.player().gamer.inventory.has("lucky_dice"), "heirloom passed to heir")


func test_karma_moves_luck() -> void:
	var sim := _adult(47)
	var p := sim.player()
	p.hidden.karma = 90.0
	var good := sim.prob.luck_bonus()
	p.hidden.karma = 10.0
	check(good > sim.prob.luck_bonus(), "karma bends luck")


func test_trial_with_lawyer_choice() -> void:
	var sim := _adult(48)
	var p := sim.player()
	sim.crime.arrest(p, "burglary", 0.9)
	check(sim.has_pending_events() and sim.current_event().id == "trial_lawyer", "trial event queued")
	sim.choose("public")
	check(not p.criminal.has("pending"), "trial resolved")
	check(sim.crime.in_prison(p) or p.criminal.record.is_empty(), "prison or acquittal")


func test_bank_robbery_plan_chain() -> void:
	var sim := _adult(49)
	var r := sim.do_activity("bank_robbery")
	check(r.ok, "robbery started")
	var steps := 0
	while sim.has_pending_events() and steps < 8:
		steps += 1
		var inst := sim.current_event()
		var choices: Array = sim.events.visible_choices(inst)
		sim.choose(choices[0].id)
	check(steps >= 4, "went through the 4 planning steps (%d)" % steps)


func test_prison_life() -> void:
	var sim := _adult(50)
	var p := sim.player()
	sim.crime.imprison(p, 6)
	sim.activities.start_year(p)
	var ids: Array = []
	for e in sim.activities.list("prison"):
		ids.append(e.id)
	for a in ["prison_bribe", "prison_riot", "prison_gang", "prison_escape"]:
		check(ids.has(a), "prison activity %s" % a)
	var joined := false
	for i in 15:
		joined = joined or sim.command("join_gang", ["iron_brotherhood"]).ok
	check(joined, "can join a gang")
	var r := sim.crime.escape_result(p, true)
	check(r.ok and not sim.crime.in_prison(p), "escape minigame success frees you")


func test_parole_for_good_behavior() -> void:
	var sim := _adult(51)
	var p := sim.player()
	sim.crime.imprison(p, 10)
	p.criminal.prison.behavior = 100.0
	var released := false
	for y in 9:
		sim.crime.process_year(p)
		if not sim.crime.in_prison(p):
			released = true
			break
	check(released, "paroled before end of sentence")
	check(sim.state.counter("prison.parole") >= 1, "parole counted")


func test_lawsuit() -> void:
	var sim := _adult(52)
	var won := false
	for i in 20:
		var r := sim.command("sue", ["neighbor", "elite"])
		won = won or r.ok
	check(won, "can win a lawsuit")


func test_rewind_save_point() -> void:
	var sim := _adult(53)
	var age0 := int(sim.player().age)
	live_years(sim, 3)
	if sim.is_dead():
		return
	check(sim.rewind(2), "rewind works")
	check(int(sim.player().age) == age0 + 1, "went back 2 years (age %d)" % sim.player().age)


func test_special_career_texts_exist() -> void:
	var sim := _adult(54)
	var p := sim.player()
	p.attrs.looks = 90.0
	sim.state.set_flag("royal_birth")
	for code in ["pt", "en"]:
		var loc := Localization.new(code)
		for id in sim.special.ids():
			var st: Dictionary = sim.special.career(id).start_state(p)
			st.reigning = true
			for a in sim.special.career(id).actions(p, st):
				check(loc.has("sc.%s.act.%s" % [id, a.id]), "[%s] sc.%s.act.%s" % [code, id, a.id])
