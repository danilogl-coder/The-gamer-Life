extends TestBase
## Life simulation behaviour tests.


func test_year_passes_and_ages() -> void:
	var sim := new_sim(1)
	drain_events(sim)
	sim.advance_year()
	check(int(sim.player().age) == 1, "age 1 after a year")
	check(int(sim.state.data.world_year) == 2001, "world year advanced")


func test_blocked_while_event_pending() -> void:
	var sim := new_sim(2)
	check(sim.has_pending_events(), "welcome event pending")
	var r := sim.advance_year()
	check(not r.ok, "cannot advance with pending event")


func test_school_progression() -> void:
	var sim := new_sim(3)
	live_years(sim, 7)
	if sim.is_dead():
		return
	check(sim.player().education.completed.has("preschool"), "finished preschool by 7: %s" % [sim.player().education])
	check(sim.player().education.stage == "primary", "in primary at 7")
	live_years(sim, 12)
	if sim.is_dead():
		return
	check(sim.player().education.completed.has("middle"), "finished middle by 19: %s" % [sim.player().education])


func test_job_requirements() -> void:
	var sim := new_sim(4)
	var p := sim.player()
	p.age = 30
	check(sim.career.block_reason(p, "doctor") == "job.block.education", "doctor needs residency")
	check(sim.career.block_reason(p, "janitor") == "", "janitor open to adults")
	p.age = 10
	check(sim.career.block_reason(p, "janitor") == "job.block.age", "kids can't be janitors")


func test_economy_adult_pays_expenses() -> void:
	var sim := new_sim(5)
	drain_events(sim)
	var p := sim.player()
	p.age = 25
	p.finance.cash = 0.0
	sim.career.hire(p, "programmer", true)
	var report := sim.finance.process_year(p)
	check(report.tax > 0.0, "taxes charged")
	check(report.expenses > 0.0, "expenses charged")
	check(float(p.finance.cash) < report.income, "net below gross")
	p.career.job = ""
	p.finance.cash = 0.0
	sim.finance.process_year(p)
	check(float(p.finance.debt) > 0.0, "unemployed adult goes into debt")


func test_minor_has_no_living_costs() -> void:
	var sim := new_sim(6)
	var p := sim.player()
	p.age = 10
	var report := sim.finance.process_year(p)
	check(is_equal_approx(report.expenses, sim.health.habit_costs(p)), "kids only pay habits")


func test_fertility_by_age() -> void:
	var sim := new_sim(7)
	var a: Dictionary = sim.factory.create_npc("brava", "f", 25)
	var b: Dictionary = sim.factory.create_npc("brava", "m", 27)
	check(sim.relations.fertility_chance(a, b) > 0.0, "fertile at 25")
	a.age = 55
	check(sim.relations.fertility_chance(a, b) == 0.0, "no fertility at 55")


func test_death_and_heir() -> void:
	var sim := new_sim(8)
	drain_events(sim)
	var p := sim.player()
	p.age = 40
	var partner: Dictionary = sim.factory.spawn_contextual("partner", {"age_rel": 0, "sex": "opposite"})
	sim.relations.ensure(partner.id, "spouse", 80)
	p.family.spouse = partner.id
	var mother := p if p.sex == "f" else partner
	var father := partner if p.sex == "f" else p
	var child: Dictionary = sim.factory.create_child(mother, father)
	child.age = 15
	sim.relations.ensure(child.id, "child", 80)
	p.finance.cash = 100000.0
	p.gamer.stats.str = 100.0
	sim.health.kill(p, "cause.event")
	check(sim.is_dead(), "player dead")
	check(not sim.state.data.death.is_empty(), "summary built")
	check(sim.legacy.heirs().has(child.id), "child is heir")
	var ok := sim.legacy.continue_as(child.id)
	check(ok, "continue as heir")
	check(sim.player().id == child.id, "heir is player")
	check(not sim.is_dead(), "alive again")
	check(float(sim.player().finance.cash) > 50000.0, "heir inherited money")
	check(float(sim.player().gamer.stats.str) >= 12.0, "heir inherited stats")
	check(int(sim.state.data.generation) == 2, "generation 2")
	check(sim.relations.role_of(p.id) in ["mother", "father"], "old player is parent")


func test_scheduled_events_fire() -> void:
	var sim := new_sim(9)
	drain_events(sim)
	sim.events.schedule("wallet_owner", 1)
	sim.advance_year()
	var found := false
	for inst in sim.state.data.pending_events:
		found = found or inst.id == "wallet_owner"
	check(found or sim.state.data.event_history.has("wallet_owner"), "scheduled event queued")


func test_skill_learned_by_repetition() -> void:
	var sim := new_sim(10)
	drain_events(sim)
	var p := sim.player()
	p.age = 10
	for i in 6:
		p.time.used = 0
		sim.do_activity("study")
	check(sim.skills.knows(p, "speed_reading"), "study x6 creates Speed Reading")


func test_level_up_gives_points() -> void:
	var sim := new_sim(11)
	var p := sim.player()
	sim.gamer.add_exp(p, 1000.0)
	check(int(p.gamer.level) > 1, "leveled up")
	check(int(p.gamer.stat_points) >= 5, "got stat points")
	var before := float(p.gamer.stats.int)
	check(sim.allocate_stat("int", 1), "allocate ok")
	check(float(p.gamer.stats.int) == before + 1.0, "int increased")


func test_dungeon_run() -> void:
	var sim := new_sim(12)
	drain_events(sim)
	var p := sim.player()
	p.age = 16
	sim.skills.learn(p, "id_create")
	p.gamer.stats.str = 30.0
	p.gamer.stats.vit = 30.0
	sim.gamer.refill(p)
	sim.activities.start_year(p)
	var r := sim.do_activity("dungeon", {"dungeon": "slime_cave"})
	check(r.ok, "dungeon ran: %s" % r)
	check(sim.state.counter("dungeon.runs") == 1, "run counted")
	check(sim.state.counter("kill.total") > 0, "killed monsters")


func test_crime_can_imprison() -> void:
	var sim := new_sim(13)
	drain_events(sim)
	var p := sim.player()
	p.age = 25
	sim.crime.imprison(p, 2)
	check(sim.crime.in_prison(p), "in prison")
	sim.activities.start_year(p)
	var cats := sim.activities.list("prison")
	check(not cats.is_empty(), "prison activities visible")
	check(sim.activities.list("body").is_empty(), "normal activities hidden in prison")
	live_years(sim, 3)
	if not sim.is_dead():
		check(not sim.crime.in_prison(sim.player()), "released after sentence")


func test_full_lives_complete() -> void:
	for seed in [101, 202, 303]:
		var sim := new_sim(seed)
		live_years(sim, 130)
		check(sim.is_dead(), "life %d ended by 130 years (age %d)" % [seed, sim.player().age])
