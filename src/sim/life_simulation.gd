class_name LifeSimulation
extends RefCounted
## Orchestrator. Owns the state, services and systems, and exposes the small
## public API the UI (and tests/bots) use. It contains no rules of its own:
## every rule lives in a system with a single responsibility.


var data: DataRegistry
var bus: EventBus
var rng: RngService
var state: GameState
var prob: ProbabilityService
var cond: ConditionEvaluator
var effects: EffectExecutor

# --- systems -------------------------------------------------------------
var factory: CharacterFactory
var gamer: GamerSystem
var skills: SkillSystem
var world: WorldSystem
var finance: FinanceSystem
var education: EducationSystem
var career: CareerSystem
var health: HealthSystem
var relations: RelationshipSystem
var npcs: NpcSystem
var quests: QuestSystem
var dungeons: DungeonSystem
var crime: CrimeSystem
var events: EventEngine
var activities: ActivitySystem
var achievements: AchievementSystem
var legacy: LegacySystem
var pets: PetSystem
var special: SpecialCareerSystem
var school_life: SchoolLifeSystem
var dating: DatingSystem
var society: SocietySystem
var dialogue: DialogueSystem
var pipeline: YearPipeline


func _init(p_data: DataRegistry, p_bus: EventBus = null) -> void:
	data = p_data
	bus = p_bus if p_bus else EventBus.new()
	rng = RngService.new(1)
	state = GameState.create_empty(1)
	prob = ProbabilityService.new(self)
	cond = ConditionEvaluator.new(self)
	effects = EffectExecutor.new(self)
	factory = CharacterFactory.new(self)
	gamer = GamerSystem.new(self)
	skills = SkillSystem.new(self)
	world = WorldSystem.new(self)
	finance = FinanceSystem.new(self)
	education = EducationSystem.new(self)
	career = CareerSystem.new(self)
	health = HealthSystem.new(self)
	relations = RelationshipSystem.new(self)
	npcs = NpcSystem.new(self)
	quests = QuestSystem.new(self)
	dungeons = DungeonSystem.new(self)
	crime = CrimeSystem.new(self)
	events = EventEngine.new(self)
	activities = ActivitySystem.new(self)
	achievements = AchievementSystem.new(self)
	legacy = LegacySystem.new(self)
	pets = PetSystem.new(self)
	special = SpecialCareerSystem.new(self)
	school_life = SchoolLifeSystem.new(self)
	dating = DatingSystem.new(self)
	society = SocietySystem.new(self)
	dialogue = DialogueSystem.new(self)
	pipeline = YearPipeline.new(self)


# =========================================================================
# Lifecycle
# =========================================================================

## Starts a brand new first-generation life. `options` may carry legacy perks,
## a fixed country, sex, etc.
func new_life(p_seed: int, options: Dictionary = {}) -> void:
	rng.reseed(p_seed)
	var meta_legacy: Dictionary = options.get("legacy", {})
	state = GameState.create_empty(p_seed)
	if not meta_legacy.is_empty():
		state.data.legacy.merge(meta_legacy.duplicate(true), true)
		state.data.legacy.perks = []
	world.init_world()
	society.init_society()
	state.data.challenge = options.get("challenge", "")
	state.data.settings = {"mature": bool(options.get("mature", true))}
	var player := factory.create_newborn_player(options)
	state.data.player_id = player.id
	legacy.apply_start_perks(options.get("perks", []))
	_maybe_royal_birth(player, options)
	gamer.on_player_created()
	events.queue_special("sys_welcome")
	pipeline.start_year()
	bus.new_life_started.emit()
	bus.state_changed.emit()


## Rare royal births in monarchies (or forced by a challenge/option).
func _maybe_royal_birth(p: Dictionary, options: Dictionary) -> void:
	var monarchy: bool = data.get_def("countries", p.country).get("monarchy", false)
	if not options.get("royal", false) and not (monarchy and rng.randf() < float(data.bal("life.royal_chance", 0.02))):
		return
	state.set_flag("royal_birth")
	p.wealth = "elite"
	p.finance.cash = 0.0
	for role in ["mother", "father"]:
		var id := relations.first_with_role(p, role)
		if id != "":
			state.npc(id).finance.cash = float(state.npc(id).finance.cash) + 50000000.0
	p.special["royalty"] = special.career("royalty").start_state(p)
	p.special.royalty.years = 0
	add_log("log.royal_birth", {"country": "@country." + p.country}, "major")


func load_state(saved: Dictionary) -> void:
	state = GameState.new()
	state.data = saved
	rng.reseed(int(saved.get("seed", 1)))
	rng.set_state(int(str(saved.get("rng_state", "0"))))
	gamer.invalidate()
	bus.state_changed.emit()


func can_rewind(years: int) -> bool:
	return years >= 1 and years <= save_points.size()


## Rewinds N years (1..5). Returns false if no save point exists.
func rewind(years: int) -> bool:
	if not can_rewind(years):
		return false
	var raw: String = save_points[save_points.size() - years]
	save_points = save_points.slice(0, save_points.size() - years)
	var saved = JSON.parse_string(raw)
	load_state(SaveSystem.normalize(saved))
	add_log("log.rewind", {"n": years}, "system")
	bus.new_life_started.emit()
	return true


func snapshot() -> Dictionary:
	state.data.rng_state = str(rng.get_state())
	state.data.seed = str(rng.seed_value)
	return state.data


# =========================================================================
# Public actions (the only doors the UI uses)
# =========================================================================

## Save points ("time machine"): the System quietly keeps the last few
## years so a death can be undone for a price in Soul Points.
const SAVE_POINTS := 5
var save_points: Array = []


func advance_year() -> Dictionary:
	if is_dead() or has_pending_events():
		return {"ok": false, "reason": "ui.blocked"}
	save_points.append(JSON.stringify(snapshot(), "", false, true))
	if save_points.size() > SAVE_POINTS:
		save_points.pop_front()
	pipeline.advance()
	bus.state_changed.emit()
	return {"ok": true}


func do_activity(activity_id: String, params: Dictionary = {}) -> Dictionary:
	gamer.invalidate()
	var result := activities.perform(activity_id, params)
	bus.state_changed.emit()
	return result


func interact(npc_id: String, interaction_id: String) -> Dictionary:
	gamer.invalidate()
	var result := relations.interact(npc_id, interaction_id)
	bus.state_changed.emit()
	return result


func choose(choice_id: String) -> Dictionary:
	gamer.invalidate()
	var result := events.resolve_current(choice_id)
	bus.state_changed.emit()
	return result


func allocate_stat(stat: String, amount: int = 1) -> bool:
	var ok := gamer.allocate(stat, amount)
	bus.state_changed.emit()
	return ok


## Generic door for system-level commands issued by the UI. Keeps the UI free
## of rules: it names an intent, the owning system decides the outcome.
func command(name: String, args: Array = []) -> Dictionary:
	if is_dead():
		return {"ok": false, "reason": "ui.blocked"}
	gamer.invalidate()
	var p := player()
	var result = null
	match name:
		"reply":
			result = dialogue.reply(args[0])
		"end_talk":
			dialogue.end_conversation()
			result = {"ok": true}
		"vote":
			if int(p.age) < 18 or crime.in_prison(p):
				result = {"ok": false, "reason": "ui.blocked"}
			else:
				p.vote = args[0]
				activities.bump_counter("civic.votes")
				result = {"ok": true, "key": "log.voted", "params": {"party": "@party." + str(args[0])}}
		"apply_job": result = career.apply(p, args[0], career.interview_score(p, args[1]) if args.size() > 1 else 0.0)
		"quit_job":
			career.fire(p, "quit")
			result = {"ok": true}
		"retire": result = career.retire(p)
		"ask_raise": result = career.ask_raise(p)
		"enroll": result = education.enroll(p, args[0])
		"drop_out":
			education.drop_out(p)
			result = {"ok": true}
		"buy_property": result = finance.buy_property(p, args[0], args[1])
		"sell_property": result = finance.sell_property(p, args[0])
		"toggle_rent":
			finance.toggle_rent(p, args[0])
			result = {"ok": true}
		"invest": result = finance.invest(p, args[0], args[1])
		"sell_investment": result = finance.sell_investment(p, args[0])
		"take_loan": result = finance.take_loan(p, args[0])
		"pay_debt":
			finance.pay_debt(p)
			result = {"ok": true}
		"lifestyle":
			finance.set_lifestyle(p, args[0])
			result = {"ok": true}
		"use_item": result = gamer.use_item(p, args[0])
		"sell_item":
			var got := gamer.sell_item(p, args[0], int(args[1]) if args.size() > 1 else 1)
			result = {"ok": got > 0.0, "key": "ui.sold", "params": {"value": int(got)}}
		"unequip":
			gamer.unequip(p, args[0])
			result = {"ok": true}
		"equip_title":
			gamer.equip_title(p, args[0])
			result = {"ok": true}
		"treat": result = health.treat(p, args[0])
		"adopt": result = relations.adopt()
		"favorite":
			activities.toggle_favorite(args[0])
			result = {"ok": true}
		"adopt_pet": result = pets.adopt(p, args[0])
		"pet_action": result = pets.interact(p, args[0], args[1])
		"sc_start": result = special.start(p, args[0])
		"sc_quit": result = special.quit(p, args[0])
		"sc_action": result = special.perform(p, args[0], args[1])
		"buy_possession": result = finance.buy_possession(p, args[0])
		"sell_possession": result = finance.sell_possession(p, args[0])
		"emigrate": result = finance.emigrate(p, args[0])
		"join_clique": result = school_life.join_clique(p, args[0])
		"leave_clique":
			school_life.leave_clique(p)
			result = {"ok": true}
		"join_club": result = school_life.join_club(p, args[0])
		"quit_club":
			school_life.quit_club(p, args[0])
			result = {"ok": true}
		"practice_club": result = school_life.practice(p, args[0])
		"dating_candidates": result = {"ok": true, "ids": dating.candidates()}
		"dating_pick": result = dating.pick(args[0])
		"set_hours": result = career.set_hours(p, args[0])
		"renovate": result = finance.renovate(p, args[0])
		"join_gang": result = crime.join_gang(p, args[0])
		"sue": result = crime.sue(p, args[0], args[1])
		"set_will": result = legacy.set_will(p, args[0], args[1] if args.size() > 1 else "")
		"auto_allocate":
			result = {"ok": gamer.auto_allocate(p)}
		_:
			push_warning("Unknown command " + name)
			result = {"ok": false, "reason": "ui.invalid"}
	titles_check()
	quests.check_completion()
	bus.state_changed.emit()
	return result


# =========================================================================
# Queries
# =========================================================================

func player() -> Dictionary:
	return state.player()


func is_dead() -> bool:
	return bool(state.data.get("dead", false))


func has_pending_events() -> bool:
	return not state.data.pending_events.is_empty()


func current_event() -> Dictionary:
	return state.data.pending_events[0] if has_pending_events() else {}


func notify(kind: String, key: String, params: Dictionary = {}) -> void:
	bus.system_notice.emit(kind, JSON.stringify({"key": key, "params": params}))


func add_log(key: String, params: Dictionary = {}, kind: String = "info") -> void:
	var entry := state.add_log(key, params, kind)
	bus.log_added.emit(entry)


## Resolves a data path used by conditions, chance modifiers and UI.
func resolve(path: String, ctx: Dictionary = {}):
	var dot := path.find(".")
	var head := path if dot < 0 else path.substr(0, dot)
	var rest := "" if dot < 0 else path.substr(dot + 1)
	var p := player()
	match head:
		"stat":
			return gamer.effective_stat(p, rest)
		"skill":
			return skills.level(p, rest)
		"mod":
			return gamer.mod(rest)
		"counter":
			return state.counter(rest)
		"yc":
			return int(p.get("year_counters", {}).get(rest, 0))
		"flag":
			return state.flag(rest)
		"rel":
			return relations.resolve_rel(rest, ctx)
		"calc":
			return _calc(rest, ctx)
		"world":
			return GameState.read_path(state.data.world, rest)
		"player":
			return GameState.read_path(p, rest)
		"actor":
			return GameState.read_path(ctx.get("actor", {}), rest)
		"state":
			return GameState.read_path(state.data, rest)
		"rand":
			return rng.randf()
	return GameState.read_path(ctx, path)


func _calc(key: String, ctx: Dictionary):
	var p := player()
	match key:
		"net_worth": return finance.net_worth(p)
		"income": return finance.yearly_income(p)
		"employed": return career.is_employed(p)
		"in_school": return education.in_school(p)
		"in_prison": return crime.in_prison(p)
		"married": return relations.spouse_id(p) != ""
		"has_partner": return relations.partner_id(p) != ""
		"children": return relations.count_role(p, "child")
		"friends": return relations.count_role(p, "friend") + relations.count_role(p, "best_friend")
		"adult": return int(p.age) >= int(data.bal("life.adult_age", 18))
		"level": return int(p.gamer.level)
		"rank": return int(p.gamer.get("rank", 0))
		"free_time": return activities.free_slots(p)
		"generation": return int(state.data.generation)
		"skills_known": return p.gamer.skills.size()
		"titles": return p.gamer.titles.size()
		"pets": return pets.alive(p).size()
		"familiars": return pets.alive(p).filter(func(x): return pets.species(x).get("kind", "") == "familiar").size()
		"has_vehicle": return finance.has_vehicle(p)
		"special_active": return special.active(p).size()
		"fame": return float(p.get("fame", 0))
		"popularity": return school_life.popularity(p)
		"karma": return float(p.hidden.get("karma", 50))
		"zodiac": return CharacterFactory.zodiac_of(p)
		"captain": return school_life.has_captaincy(p)
		"compat":
			return relations.compatibility(ctx.get("actor", {}))
		"actor_age_gap":
			return absi(int(ctx.get("actor", {}).get("age", 0)) - int(p.age))
		"actor_level_gap":
			return int(ctx.get("actor", {}).get("gamer", {}).get("level", 1)) - int(p.gamer.level)
	push_warning("Unknown calc: " + key)
	return null


# =========================================================================
# Small cross-system helpers
# =========================================================================

## Content rating: items tagged "mature" (alcohol, gambling, flings) are
## hidden when the player disables mature content.
func allows(tags: Array) -> bool:
	return not tags.has("mature") or bool(state.data.get("settings", {}).get("mature", true))


func titles_check() -> void:
	gamer.check_titles(player())


## Hidden talents speed up related skills: a born musician learns music faster.
func hidden_talent_bonus(skill_def: Dictionary) -> float:
	var talent: String = skill_def.get("talent", "")
	if talent == "":
		return 0.0
	return (float(player().hidden.get(talent, 50)) - 50.0) / 100.0
