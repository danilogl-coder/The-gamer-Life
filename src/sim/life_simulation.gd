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
	var player := factory.create_newborn_player(options)
	state.data.player_id = player.id
	legacy.apply_start_perks(options.get("perks", []))
	gamer.on_player_created()
	events.queue_special("sys_welcome")
	pipeline.start_year()
	bus.new_life_started.emit()
	bus.state_changed.emit()


func load_state(saved: Dictionary) -> void:
	state = GameState.new()
	state.data = saved
	rng.reseed(int(saved.get("seed", 1)))
	rng.set_state(int(str(saved.get("rng_state", "0"))))
	gamer.invalidate()
	bus.state_changed.emit()


func snapshot() -> Dictionary:
	state.data.rng_state = str(rng.get_state())
	state.data.seed = str(rng.seed_value)
	return state.data


# =========================================================================
# Public actions (the only doors the UI uses)
# =========================================================================

func advance_year() -> Dictionary:
	if is_dead() or has_pending_events():
		return {"ok": false, "reason": "ui.blocked"}
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
		"apply_job": result = career.apply(p, args[0])
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
	bus.notification.emit(kind, JSON.stringify({"key": key, "params": params}))


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

func titles_check() -> void:
	gamer.check_titles(player())


## Hidden talents speed up related skills: a born musician learns music faster.
func hidden_talent_bonus(skill_def: Dictionary) -> float:
	var talent: String = skill_def.get("talent", "")
	if talent == "":
		return 0.0
	return (float(player().hidden.get(talent, 50)) - 50.0) / 100.0
