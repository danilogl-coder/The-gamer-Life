extends TestBase
## Living world: personas, contextual dialogue, NPC lives, gossip, society.


func _adult(seed: int) -> LifeSimulation:
	var sim := new_sim(seed)
	drain_events(sim)
	var p := sim.player()
	p.age = 30
	p.finance.cash = 200000.0
	for s in CharacterFactory.STAT_IDS:
		p.gamer.stats[s] = 20.0
	sim.activities.start_year(p)
	return sim


func _friend(sim: LifeSimulation, traits: Array = [], age: int = 40) -> Dictionary:
	var npc := sim.factory.create_npc(sim.player().country, "f", age)
	npc.traits = traits
	Persona.build(npc, sim)
	sim.state.add_npc(npc)
	sim.relations.ensure(npc.id, "friend", 60)
	return npc


func test_personas_exist_and_inherit() -> void:
	var sim := new_sim(501)
	var p := sim.player()
	check(p.has("persona") and p.persona.has("big5"), "player has a persona")
	var mom := sim.state.npc(p.family.mother) if p.family.mother != "" else sim.state.npc(p.family.father)
	check(mom.persona.interests.size() >= 2, "parents have interests")
	check(p.persona.voice == "kid", "a baby talks like a kid")
	p.age = 40
	Persona.refresh_voice(p)
	check(p.persona.voice != "kid", "voice matures with age")
	var kind := _friend(sim, ["kind"])
	var cruel := _friend(sim, ["cruel"])
	check(float(kind.persona.big5.a) > float(cruel.persona.big5.a) - 5.0, "traits shape agreeableness")


func test_dialogue_picks_most_specific_rule() -> void:
	var sim := _adult(502)
	var npc := _friend(sim)
	npc.life_log = [{"e": "fired", "y": sim.state.data.world_year, "p": {}}]
	var facts := sim.dialogue.build_facts(npc, "talk")
	var rule: Dictionary = sim.dialogue.best("talk", npc, facts)
	check(str(rule.get("id", "")).begins_with("ev_fired"), "recent firing becomes the topic (got %s)" % rule.get("id", ""))
	npc.persona.voice = "blunt"
	facts = sim.dialogue.build_facts(npc, "talk")
	rule = sim.dialogue.best("talk", npc, facts)
	check(rule.get("id", "") in ["ev_fired_blunt", "ev_fired_auto"], "a blunt person says it their way (got %s)" % rule.get("id", ""))


func test_same_situation_different_people() -> void:
	var sim := _adult(503)
	var seen := {}
	for i in 12:
		var npc := _friend(sim, [], 25 + i * 4)
		var conv := sim.dialogue.start_conversation(npc.id, "talk")
		var sig := ""
		for l in conv.lines:
			sig += str(l.key) + "|"
		seen[sig] = true
		sim.dialogue.end_conversation()
	check(seen.size() >= 9, "12 different people produce varied scenes (%d distinct)" % seen.size())


func test_reply_odds_depend_on_personality() -> void:
	var sim := _adult(504)
	var def: Dictionary = sim.data.get_def("dialogue_replies", "joke")
	var fun := _friend(sim)
	fun.persona.big5.e = 90.0
	fun.persona.big5.n = 20.0
	var grim := _friend(sim)
	grim.persona.big5.e = 15.0
	grim.persona.big5.n = 85.0
	var a := sim.dialogue.reply_chance(def, sim.dialogue.build_facts(fun, "talk"))
	var b := sim.dialogue.reply_chance(def, sim.dialogue.build_facts(grim, "talk"))
	check(a > b + 0.3, "jokes land with extroverts, not with anxious people (%.2f vs %.2f)" % [a, b])


func test_conversation_reply_changes_bond() -> void:
	var sim := _adult(505)
	var npc := _friend(sim)
	npc.attrs.happiness = 10.0
	var conv := sim.dialogue.start_conversation(npc.id, "talk")
	check(not conv.replies.is_empty(), "there are reply options")
	var before := sim.relations.score(npc.id)
	var r := sim.command("reply", [conv.replies[0].id])
	check(r.ok and not r.lines.is_empty(), "reply returns a reaction")
	check(sim.relations.score(npc.id) != before or not r.success, "the bond moved")
	check(sim.state.data.conversation.is_empty(), "conversation closed")


func test_talk_interaction_opens_scene() -> void:
	var sim := _adult(506)
	var npc := _friend(sim)
	var r := sim.interact(npc.id, "talk")
	check(r.ok and r.has("conversation"), "talking opens a scene")
	check(r.conversation.lines.size() >= 2, "scene has setting and lines")
	var q := sim.interact(npc.id, "compliment")
	check(q.ok and q.has("quote"), "other interactions get an in-character reaction")


func test_gossip_judged_by_values() -> void:
	var sim := _adult(507)
	var devout := _friend(sim, ["kind"])
	devout.hidden.religiousness = 95.0
	var crook := _friend(sim, ["cruel"])
	crook.hidden.religiousness = 5.0
	var b1 := sim.relations.score(devout.id)
	var b2 := sim.relations.score(crook.id)
	sim.player().fame = 80.0
	sim.add_log("log.arrested", {}, "major")
	for i in 3:
		sim.society.spread_gossip(sim.player())
	check(devout.known_marks.has("arrested") and crook.known_marks.has("arrested"), "news of the arrest spreads")
	check(sim.relations.score(devout.id) < b1, "the devout friend thinks less of you")
	check(sim.relations.score(crook.id) > b2, "the cruel friend respects you more")
	var facts := sim.dialogue.build_facts(devout, "talk")
	check(facts.get("sp.knows.arrested", false), "what they know becomes a dialogue fact")


func test_npc_lives_go_on() -> void:
	var sim := new_sim(508)
	live_years(sim, 30)
	var events := 0
	for id in sim.state.data.npcs:
		events += sim.state.data.npcs[id].get("life_log", []).size()
	check(events >= 10, "NPCs have their own life events (%d)" % events)


func test_single_parent_remarries() -> void:
	var sim := new_sim(509)
	drain_events(sim)
	var p := sim.player()
	var parent_id: String = p.family.mother if p.family.mother != "" else p.family.father
	var parent := sim.state.npc(parent_id)
	var old_spouse: String = parent.family.spouse
	if old_spouse != "":
		sim.state.npc(old_spouse).family.spouse = ""
		parent.family.spouse = ""
	sim.npcs.apply_life_event(p, parent, sim.data.get_def("npc_life", "married"))
	check(sim.relations.first_with_role(p, "stepparent") != "", "a stepparent joins the family")


func test_parents_divorce_hits_child() -> void:
	var sim := new_sim(510, {})
	drain_events(sim)
	var p := sim.player()
	if p.family.mother == "" or p.family.father == "":
		return
	var mom := sim.state.npc(p.family.mother)
	mom.family.spouse = p.family.father
	sim.state.npc(p.family.father).family.spouse = mom.id
	var h := float(p.attrs.happiness)
	sim.npcs.apply_life_event(p, mom, sim.data.get_def("npc_life", "divorce"))
	check(p.family_structure == "separated", "family structure changed")
	check(float(p.attrs.happiness) < h, "the child is hurt by it")


func test_society_runs_without_player() -> void:
	var sim := new_sim(511)
	var g0 := sim.society.gov().duplicate(true)
	live_years(sim, 25)
	var g := sim.society.gov()
	check(g.history.size() >= 4, "elections happened (%d)" % g.history.size())
	check(not sim.society.soc().tech.eras.is_empty(), "technology advanced")
	check(sim.society.soc().news.size() > 20, "the newspaper filled up")
	check(sim.society.soc().celebs.size() >= 12, "celebrities keep coming")
	var open := sim.society.city().places.filter(func(x): return x.open).size()
	check(open >= 10, "city has open places (%d)" % open)


func test_vote_counts() -> void:
	var sim := _adult(512)
	var r := sim.command("vote", ["ordem"])
	check(r.ok and sim.player().vote == "ordem", "adult can vote")
	sim.player().age = 10
	check(not sim.command("vote", ["ordem"]).ok, "children can't vote")


func test_automation_cuts_pay() -> void:
	var sim := _adult(513)
	var before := sim.society.job_mult("cashier")
	sim.society.soc().tech.eras.append("automation")
	check(sim.society.job_mult("cashier") < before, "automation lowers cashier pay")
	check(sim.society.job_mult("programmer") > before, "and raises tech pay")


func test_player_crimes_raise_city_crime() -> void:
	var a := _adult(514)
	var b := _adult(514)
	b.player().year_counters["crime.theft"] = 10
	a.society._city_year(a.society.city(), true)
	b.society._city_year(b.society.city(), true)
	check(float(b.society.city().crime) > float(a.society.city().crime), "your crimes make the city more dangerous")


func test_reach_outs_resolve() -> void:
	var sim := _adult(515)
	var npc := _friend(sim)
	sim.relations.change_score(npc.id, 30)
	npc.life_log = [{"e": "promoted", "y": sim.state.data.world_year, "p": {}}]
	sim.state.data.pending_events.append({"id": "__talk", "actor": npc.id, "concept": "reach"})
	var choices := sim.events.visible_choices(sim.current_event())
	check(choices.size() >= 2, "a call comes with replies")
	var r := sim.choose(choices[0].id)
	check(r.ok and not sim.has_pending_events(), "answering the call resolves it")


func test_young_players_get_age_appropriate_talk() -> void:
	var sim := new_sim(516)
	var p := sim.player()
	var mom_id: String = p.family.mother if p.family.mother != "" else p.family.father
	var conv := sim.dialogue.start_conversation(mom_id, "talk")
	check(str(conv.topic).begins_with("baby_"), "parents coo at babies (got %s)" % conv.topic)
	p.age = 7
	sim.world.start_event("recession")
	for i in 6:
		conv = sim.dialogue.start_conversation(mom_id, "talk")
		var def: Dictionary = sim.data.dialogue.get(conv.topic, {})
		check(not DialogueSystem.GROWN_UP_TOPICS.has(def.get("topic", "")), "no grown-up topics with a 7-year-old (%s)" % conv.topic)
		sim.dialogue.end_conversation()


func test_dialogue_texts_complete() -> void:
	var loc := Localization.new("pt")
	var en := Localization.new("en")
	var missing: Array = []
	for id in data.dialogue:
		var r: Dictionary = data.dialogue[id]
		for i in int(r.get("n", 1)):
			var k := "dlg.%s.%d" % [id, i]
			if not loc.has(k) or not en.has(k):
				missing.append(k)
	check(missing.is_empty(), "every dialogue line exists in PT and EN (%s)" % str(missing.slice(0, 5)))
	check(data.dialogue.size() >= 400, "hundreds of rules (%d)" % data.dialogue.size())


func test_save_roundtrip_with_world() -> void:
	var a := new_sim(517)
	live_years(a, 15)
	var snap: Dictionary = SaveSystem.normalize(JSON.parse_string(JSON.stringify(a.snapshot(), "", false, true)))
	var b := LifeSimulation.new(data)
	b.load_state(SaveSystem.migrate(snap))
	live_years(a, 6)
	live_years(b, 6)
	check(a.society.gov().party == b.society.gov().party, "same government after load")
	check(a.society.soc().news.size() == b.society.soc().news.size(), "same newspaper after load")
	check(a.state.data.timeline.size() == b.state.data.timeline.size(), "same life after load")
