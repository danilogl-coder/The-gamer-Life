class_name YearPipeline
extends RefCounted
## The exact, ordered processing when the player presses "+1 YEAR".
##
##  CLOSE THE YEAR THAT PASSED (uses this year's actions/counters)
##   1. Finance       salary, taxes, living costs, loans, interest, credit
##   2. Career        performance, promotion/firing, job EXP & stress
##      Special       music / sports / business / influencer yearly ticks
##   3. Education     grades, tuition, graduation / failing a year
##   4. Crime         heat decay, prison sentence countdown
##   5. Gamer         Gamer's Body rest (HP/MP), natural growth / decline
##   6. Health        aging, stress, habits, diseases, DEATH CHECK
##   7. Relations     bond decay, memory fading, romance checks (cheating...)
##      Pets          aging, bond, familiars
##   8. NPCs          relevant NPCs age, mood, marriages, life events (their
##                    own jobs, weddings, babies, illnesses, moves...), die
##      Gossip        people hear about what you did and judge it
##                    by their own values
##  OPEN THE NEW YEAR
##   9. Calendar      age+1, world year+1, milestones
##  10. World         economy cycle, inflation, markets, world events
##      Society       cities, businesses, government & elections, tech eras,
##                    celebrities, sports, newspaper
##  11. Quests        deadlines/failures, new quest offers
##  12. Scheduled     delayed consequences whose time has come
##  13. Random events weighted by data, rarity, cooldowns, conditions
##      Reach-outs    people close to you call you about their lives
##  14. Titles & achievements
##  15. New year budget (free time), auto school enrollment

var _sim


func _init(sim) -> void:
	_sim = sim


func advance() -> void:
	var p: Dictionary = _sim.player()
	_sim.gamer.invalidate()
	_sim.finance.process_year(p)
	_sim.career.process_year(p)
	_sim.special.process_year(p)
	_sim.education.process_year(p)
	_sim.school_life.process_year(p)
	_sim.crime.process_year(p)
	_sim.gamer.process_year(p)
	_sim.health.process_year(p)
	if _sim.is_dead():
		return
	_sim.relations.process_year(p)
	_sim.pets.process_year(p)
	_sim.npcs.process_year(p)
	_sim.society.spread_gossip(p)
	# --- new year ---
	p.age = int(p.age) + 1
	_sim.state.data.world_year = int(_sim.state.data.world_year) + 1
	_milestones(p)
	_sim.world.process_year()
	_sim.society.process_year()
	_sim.gamer.invalidate()
	_sim.quests.process_year()
	_sim.events.process_scheduled()
	_sim.events.roll_year()
	_sim.dialogue.process_year(p)
	_sim.titles_check()
	_sim.achievements.check()
	_sim.skills.check_fusions(p)
	start_year()
	_sim.bus.year_advanced.emit(int(p.age))


func start_year() -> void:
	var p: Dictionary = _sim.player()
	p.year_counters = {}
	_sim.education.auto_enroll(p)
	_sim.activities.start_year(p)
	_sim.quests.offer_new()


func _milestones(p: Dictionary) -> void:
	var age := int(p.age)
	if age == 8:
		_sim.events.queue_special("attic_search")
	if age == int(_sim.data.bal("life.adult_age", 18)):
		_sim.add_log("log.adult", {}, "major")
	elif age % 10 == 0:
		_sim.add_log("log.decade", {"age": age}, "info")
