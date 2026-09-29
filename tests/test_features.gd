extends TestBase
## Special careers, pets/familiars, possessions, challenges, content filter.


func _adult(seed: int) -> LifeSimulation:
	var sim := new_sim(seed)
	drain_events(sim)
	var p := sim.player()
	p.age = 25
	p.finance.cash = 2000000.0
	for s in CharacterFactory.STAT_IDS:
		p.gamer.stats[s] = 30.0
	sim.skills.learn(p, "music")
	p.attrs.looks = 90.0
	p.education.completed.append("uni_physics")
	sim.state.add_counter("crime.total", 6)
	sim.state.set_flag("royal_birth")
	sim.activities.start_year(p)
	return sim


func test_every_special_career_runs() -> void:
	var sim := _adult(31)
	var p := sim.player()
	for id in sim.special.ids():
		var r := sim.command("sc_start", [id])
		check(r.ok, "start %s: %s" % [id, r])
	for id in sim.special.active(p):
		for a in sim.special.actions(p, id):
			p.time.used = 0
			if a.locked == "" and a.id not in ["retire", "sell"]:
				var r := sim.command("sc_action", [id, a.id])
				check(r.ok, "%s/%s: %s" % [id, a.id, r])
		check(not sim.special.career(id).summary(p, p.special[id]).is_empty(), "%s summary" % id)
	var before := float(p.finance.cash)
	sim.special.process_year(p)
	check(float(p.finance.cash) != before, "special careers move money")


func test_business_sell_ends_career() -> void:
	var sim := _adult(32)
	var p := sim.player()
	sim.command("sc_start", ["business"])
	sim.special.process_year(p)
	var r := sim.command("sc_action", ["business", "sell"])
	if r.ok:
		sim.special.process_year(p)
		check(not p.special.has("business"), "sold company closes the career")


func test_pets_and_familiar_naming() -> void:
	var sim := _adult(33)
	var p := sim.player()
	check(sim.command("adopt_pet", ["dog"]).ok, "adopt dog")
	check(sim.pets.alive(p).size() == 1, "one pet")
	var fam: Dictionary = sim.pets.add(p, "slime_fam")
	check(sim.pets.combat_bonus(p) > 0.0, "familiar adds combat power")
	sim.gamer.refill(p)
	var r := sim.command("pet_action", [fam.id, "name"])
	check(r.ok, "naming works: %s" % r)
	check(sim.pets.get_pet(p, fam.id).species == "slime_named", "familiar evolved")
	check(sim.skills.knows(p, "naming"), "learned Naming")
	for i in 20:
		sim.pets.process_year(p)
	check(sim.pets.get_pet(p, sim.pets.pets(p)[0].id).alive == false, "dog dies of old age")


func test_possessions_value_and_sale() -> void:
	var sim := _adult(34)
	var p := sim.player()
	sim.skills.learn(p, "driving")
	check(sim.command("buy_possession", ["sedan"]).ok, "buy sedan")
	check(sim.finance.has_vehicle(p), "has vehicle")
	var v0 := float(p.finance.possessions[0].value)
	sim.finance.process_year(p)
	check(float(p.finance.possessions[0].value) < v0, "car depreciates")
	check(sim.command("sell_possession", [0]).ok, "sell car")
	check(not sim.finance.has_vehicle(p), "no vehicle after sale")


func test_challenge_completes() -> void:
	var sim := new_sim(35, {"challenge": "ch_big_family"})
	drain_events(sim)
	var got := []
	sim.bus.challenge_completed.connect(func(id, reward): got.append([id, reward]))
	var p := sim.player()
	p.age = 30
	var partner: Dictionary = sim.factory.spawn_contextual("partner", {"sex": "opposite"})
	sim.relations.ensure(partner.id, "fiance", 90)
	sim.relations.marry(partner.id)
	for i in 4:
		var c: Dictionary = sim.factory.create_child(p if p.sex == "f" else partner, partner if p.sex == "f" else p)
		sim.relations.ensure(c.id, "child", 80)
	sim.achievements.check()
	check(got.size() == 1 and got[0][0] == "ch_big_family", "challenge completed: %s" % [got])


func test_mature_filter_hides_content() -> void:
	var sim := new_sim(36, {"mature": false})
	drain_events(sim)
	sim.player().age = 20
	var ids: Array = []
	for e in sim.activities.list("leisure"):
		ids.append(e.id)
	check(not ids.has("casino") and not ids.has("party"), "mature activities hidden: %s" % [ids])
	check(not sim.events.is_eligible(data.events.party_stranger, {}), "mature event blocked")


func test_emigration_changes_country_and_job() -> void:
	var sim := _adult(37)
	var p := sim.player()
	sim.career.hire(p, "janitor", true)
	var target := "nortavia" if p.country != "nortavia" else "akitsu"
	var r := {}
	for i in 30:
		p.finance.cash = 2000000.0
		r = sim.command("emigrate", [target])
		if r.ok:
			break
	check(r.ok, "emigrate: %s" % r)
	check(p.country == target, "country changed")
	check(p.career.job == "", "lost job when moving")
