class_name EffectExecutor
extends RefCounted
## Executes data-driven effects. New content never needs new code as long as it
## is expressible with these verbs. Each effect is {"type": "...", ...}.
## ctx carries "actor" (NPC dict) and receives "gains" (for result summaries).

var _sim


func _init(sim) -> void:
	_sim = sim


func run_all(list, ctx: Dictionary) -> void:
	if list == null:
		return
	for e in list:
		run(e, ctx)


func run(e: Dictionary, ctx: Dictionary) -> void:
	if e.has("if") and not _sim.cond.check_all(e["if"], ctx):
		return
	var p: Dictionary = _sim.player()
	var actor: Dictionary = ctx.get("actor", {})
	match e.get("type", ""):
		"CHANGE_STAT":
			_change_stat(p, e.stat, _num(e, ctx), ctx)
		"CHANGE_VALUE":
			var path: String = e.path
			var cur = GameState.read_path(p, path, 0.0)
			var v := float(cur) * float(e.get("mult", 1.0)) + _num(e, ctx)
			if e.has("min"): v = maxf(v, float(e.min))
			if e.has("max"): v = minf(v, float(e.max))
			GameState.write_path(p, path, v)
		"CHANGE_MONEY":
			var amount := _num(e, ctx)
			if e.get("scale_income", false):
				amount *= maxf(_sim.finance.yearly_income(p), float(_sim.data.bal("finance.min_income_scale", 5000)))
			_sim.finance.add_cash(p, amount)
			_gain(ctx, "money", amount)
		"CHANGE_RELATIONSHIP":
			var target := _target(e, ctx)
			if target != "":
				_sim.relations.change_score(target, _num(e, ctx))
				_gain(ctx, "rel", _num(e, ctx))
		"ADD_MEMORY":
			var target := _target(e, ctx)
			if target != "":
				_sim.relations.add_memory(target, e.memory, float(e.get("severity", 10)))
		"START_RELATIONSHIP":
			if not actor.is_empty():
				_sim.relations.ensure(actor.id, e.role, float(e.get("score", 50)))
		"END_RELATIONSHIP":
			var target := _target(e, ctx)
			if target != "":
				_sim.relations.end(target, e.get("reason", "cut"))
		"SET_ROLE":
			var target := _target(e, ctx)
			if target != "":
				_sim.relations.set_role(target, e.role)
		"ADD_DISEASE":
			_sim.health.add_condition(p, e.disease)
		"REMOVE_DISEASE":
			_sim.health.remove_condition(p, e.disease)
		"ADD_ITEM":
			_sim.gamer.add_item(p, e.item, int(e.get("qty", 1)))
			_gain(ctx, "item:" + e.item, int(e.get("qty", 1)))
		"REMOVE_ITEM":
			_sim.gamer.remove_item(p, e.item, int(e.get("qty", 1)))
		"START_JOB":
			_sim.career.hire(p, e.job, true)
		"LOSE_JOB":
			_sim.career.fire(p, e.get("reason", "fired"))
		"ADD_CRIMINAL_RECORD":
			_sim.crime.add_record(p, e.crime)
		"TRIGGER_EVENT":
			_sim.events.queue_event(e.event, actor.get("id", ""), true)
		"SCHEDULE_EVENT":
			var years: int = _sim.rng.randi_range(int(e.get("min", 1)), int(e.get("max", e.get("min", 1))))
			_sim.events.schedule(e.event, years, actor.get("id", "") if e.get("keep_actor", true) else "")
		"SET_FLAG":
			_sim.state.set_flag(e.flag, e.get("value", true))
		"CLEAR_FLAG":
			_sim.state.data.flags.erase(e.flag)
		"COUNTER":
			_sim.activities.bump_counter(e.key, int(e.get("amount", 1)))
		"GAIN_EXP":
			var amount := _num(e, ctx)
			if e.get("scale_level", false):
				amount *= 1.0 + float(p.gamer.level) * float(_sim.data.bal("gamer.exp_level_scale", 0.15))
			var gained: int = _sim.gamer.add_exp(p, amount)
			_gain(ctx, "exp", gained)
		"STAT_XP":
			_sim.gamer.add_stat_xp(p, e.stat, _num(e, ctx))
			_gain(ctx, "sxp:" + e.stat, _num(e, ctx))
		"GIVE_STAT_POINTS":
			p.gamer.stat_points = int(p.gamer.stat_points) + int(_num(e, ctx))
			_gain(ctx, "points", int(_num(e, ctx)))
		"SKILL_XP":
			if _sim.skills.knows(p, e.skill):
				_sim.skills.add_xp(p, e.skill, _num(e, ctx))
		"LEARN_SKILL":
			_sim.skills.learn(p, e.skill)
		"GRANT_TITLE":
			_sim.gamer.grant_title(p, e.title)
		"START_QUEST":
			_sim.quests.start(e.quest)
		"FACTION_REP":
			_sim.career.change_faction_rep(p, e.faction, _num(e, ctx))
		"JOIN_FACTION":
			_sim.career.join_faction(p, e.faction)
		"CHANGE_FAME":
			p.fame = clampf(float(p.get("fame", 0)) + _num(e, ctx), 0.0, 100.0)
		"CHANGE_HABIT":
			_sim.health.change_habit(p, e.habit, _num(e, ctx))
		"DISCOVER_HIDDEN":
			_sim.gamer.discover_hidden(p, e.get("hidden", ""))
		"CHANGE_HIDDEN":
			p.hidden[e.hidden] = clampf(float(p.hidden.get(e.hidden, 50)) + _num(e, ctx), 0.0, 100.0)
		"ADD_TRAIT":
			if not p.traits.has(e.trait):
				p.traits.append(e.trait)
				_sim.gamer.invalidate()
		"REMOVE_TRAIT":
			p.traits.erase(e.trait)
			_sim.gamer.invalidate()
		"SPAWN_NPC":
			var npc: Dictionary = _sim.factory.spawn_contextual(e.get("role", "acquaintance"), e)
			_sim.relations.ensure(npc.id, e.get("role", "acquaintance"), float(e.get("score", 45)))
			ctx["actor"] = npc
		"TRIAL":
			var crime_id: String = p.criminal.get("pending", "")
			if crime_id == "":
				crime_id = e.get("crime", "burglary")
			p.criminal.erase("pending")
			_sim.crime.arrest_and_trial(p, crime_id, float(e.get("extra", 0.0)))
		"GO_TO_PRISON":
			_sim.crime.imprison(p, _sim.rng.randi_range(int(e.get("min", 1)), int(e.get("max", 3))))
		"KILL":
			_sim.health.kill(p, e.get("cause", "cause.event"))
		"HEAL":
			_sim.gamer.heal(p, _num(e, ctx), float(e.get("mp", 0)))
		"LOG":
			_sim.add_log(e.key, _log_params(e, ctx), e.get("kind", "info"))
		"NOTIFY":
			_sim.notify(e.get("kind", "system"), e.key, _log_params(e, ctx))
		"CHANCE":
			if _sim.rng.randf() < float(e.get("p", 0.5)):
				run_all(e.get("effects", []), ctx)
			else:
				run_all(e.get("else", []), ctx)
		"MARRY":
			if not actor.is_empty():
				_sim.relations.marry(actor.id)
				if e.get("prenup", false):
					_sim.state.set_flag("prenup_" + actor.id)
		"CHANGE_ACTOR":
			if not actor.is_empty():
				var av := float(GameState.read_path(actor, e.path, 0.0)) + _num(e, ctx)
				if e.has("max"): av = minf(av, float(e.max))
				GameState.write_path(actor, e.path, maxf(float(e.get("min", 0.0)), av))
		"DIVORCE":
			if not actor.is_empty():
				_sim.relations.divorce(actor.id)
		"CONCEIVE":
			if not actor.is_empty():
				var born: bool = _sim.relations.conceive(actor.id)
				_gain(ctx, "baby", 1 if born else 0)
		"OBSERVE":
			if not actor.is_empty():
				_sim.skills.observe(actor)
		"ADD_PET":
			_sim.pets.add(p, e.species)
		"ADD_POSSESSION":
			p.finance.possessions.append({"id": e.possession, "value": float(e.get("value", 1000)), "age": int(e.get("age", 0)), "condition": 60.0})
			_sim.gamer.invalidate()
		"START_SPECIAL":
			if not p.special.has(e.career) and _sim.special.career(e.career) != null:
				p.special[e.career] = _sim.special.career(e.career).start_state(p)
				p.special[e.career].years = 0
				_sim.add_log("log.sc_start", {"career": "@sc." + e.career}, "major")
		"CHANGE_SPECIAL":
			var st: Dictionary = p.special.get(e.career, {})
			if not st.is_empty():
				if e.has("set"):
					st[e.path] = e.set
				else:
					st[e.path] = maxf(0.0, float(st.get(e.path, 0.0)) * float(e.get("mult", 1.0)) + _num(e, ctx))
		"WORLD_EVENT":
			_sim.world.start_event(e.event)
		_:
			push_warning("Unknown effect type: %s" % e)


## Life attributes (0..100) vs Gamer stats (unbounded) share one verb.
func _change_stat(p: Dictionary, stat: String, amount: float, ctx: Dictionary) -> void:
	if p.attrs.has(stat):
		if stat == "stress" and amount > 0.0:
			amount *= maxf(0.1, 1.0 + _sim.gamer.mod("stress_gain"))
		p.attrs[stat] = clampf(float(p.attrs[stat]) + amount, 0.0, 100.0)
		_gain(ctx, "attr:" + stat, amount)
	elif p.gamer.stats.has(stat):
		p.gamer.stats[stat] = maxf(0.0, float(p.gamer.stats[stat]) + amount)
		_sim.gamer.invalidate()
		_gain(ctx, "stat:" + stat, amount)
	else:
		push_warning("CHANGE_STAT unknown stat: " + stat)


func _num(e: Dictionary, ctx: Dictionary) -> float:
	if e.has("min_amount") and e.has("max_amount"):
		return _sim.rng.randf_range(float(e.min_amount), float(e.max_amount))
	var v = e.get("amount", 0)
	if typeof(v) == TYPE_STRING:
		return float(_sim.resolve(v, ctx))
	return float(v)


func _target(e: Dictionary, ctx: Dictionary) -> String:
	var t: String = e.get("target", "actor")
	if t == "actor":
		return ctx.get("actor", {}).get("id", "")
	if t.begins_with("role:"):
		return _sim.relations.first_with_role(_sim.player(), t.substr(5))
	return t


func _log_params(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var params: Dictionary = e.get("params", {}).duplicate()
	var actor: Dictionary = ctx.get("actor", {})
	if not actor.is_empty():
		params["name"] = actor.get("first_name", "")
	return params


static func _gain(ctx: Dictionary, key: String, amount) -> void:
	if not ctx.has("gains"):
		ctx["gains"] = {}
	ctx.gains[key] = ctx.gains.get(key, 0) + amount
