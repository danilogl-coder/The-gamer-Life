class_name EventEngine
extends RefCounted
## Generic, data-driven event engine. An event definition (data/events/*.json):
## {
##   "id": "school_bully", "tags": ["school"], "rarity": "common",
##   "weight": 10, "cooldown": 3, "once": false, "min_age": 7, "max_age": 17,
##   "conditions": [...],                       # see ConditionEvaluator
##   "actor": {"role": ["friend", "classmate"]} # or {"new": {spawn spec}}
##   "actor_conditions": [...],                 # evaluated per candidate
##   "effects": [...],                          # applied on show (auto events)
##   "choices": [{"id": "fight", "conditions": [...], "chance": {...},
##                "effects": [...], "success": {"effects": [...]},
##                "fail": {"effects": [...]}}],
##   "special": true                            # only via trigger/schedule
## }
## Texts come from keys: ev.<id>.title / .desc / .<choice> / .<choice>.ok|fail|res
## Chains are built with TRIGGER_EVENT / SCHEDULE_EVENT effects + flags.

var _sim


func _init(sim) -> void:
	_sim = sim


func pending() -> Array:
	return _sim.state.data.pending_events


# ---------------------------------------------------------------------------
# Queueing
# ---------------------------------------------------------------------------

## System messages / forced events: queued without checking conditions.
func queue_special(id: String, actor_id: String = "") -> void:
	queue_event(id, actor_id, true)


func queue_event(id: String, actor_id: String = "", force: bool = false) -> bool:
	var def: Dictionary = _sim.data.events.get(id, {})
	if def.is_empty() or _sim.is_dead():
		return false
	for inst in pending():
		if inst.id == id:
			return false
	var actor: Dictionary = _sim.state.npc(actor_id) if actor_id != "" else {}
	if actor.is_empty() and def.has("actor"):
		actor = _pick_actor(def, true)
		if actor.is_empty() and not force:
			return false
	if not force and not is_eligible(def, actor):
		return false
	var inst := {"id": id, "actor": actor.get("id", "")}
	pending().append(inst)
	_mark_seen(id)
	_sim.effects.run_all(def.get("effects", []), {"actor": actor})
	_sim.bus.event_queued.emit(inst)
	return true


func schedule(id: String, years: int, actor_id: String = "") -> void:
	_sim.state.data.scheduled.append({"id": id, "due": int(_sim.player().age) + maxi(1, years), "actor": actor_id})


## Scheduled events whose time has come are queued if still valid.
func process_scheduled() -> void:
	var age := int(_sim.player().age)
	var keep: Array = []
	for s in _sim.state.data.scheduled:
		if int(s.due) > age:
			keep.append(s)
			continue
		var actor_id: String = s.get("actor", "")
		if actor_id != "" and (not _sim.state.has_npc(actor_id) or not _sim.state.npc(actor_id).alive):
			continue
		queue_event(s.id, actor_id, false)
	_sim.state.data.scheduled = keep


## Yearly random events: weighted by data weight × rarity, respecting
## cooldowns, "once", age ranges and conditions.
func roll_year() -> void:
	var count: int = _sim.rng.pick_weighted([0, 1, 2, 3], _sim.data.bal("events.count_weights", [15, 45, 30, 10]))
	for i in count:
		var candidates: Array = []
		var weights: Array = []
		var ids: Array = _sim.data.events.keys()
		ids.sort()
		for id in ids:
			var def: Dictionary = _sim.data.events[id]
			if def.get("special", false) or not is_eligible(def, {}):
				continue
			if def.has("actor") and _pick_actor(def, false).is_empty() and not def.actor.has("new"):
				continue
			candidates.append(id)
			var rarity: float = _sim.data.bal("events.rarity." + def.get("rarity", "common"), 1.0)
			weights.append(float(def.get("weight", 10)) * rarity)
		var chosen = _sim.rng.pick_weighted(candidates, weights)
		if chosen == null:
			return
		queue_event(chosen)


func is_eligible(def: Dictionary, actor: Dictionary) -> bool:
	var p: Dictionary = _sim.player()
	var age := int(p.age)
	if age < int(def.get("min_age", 0)) or age > int(def.get("max_age", 999)):
		return false
	var hist: Dictionary = _sim.state.data.event_history.get(def.id, {})
	if def.get("once", false) and not hist.is_empty():
		return false
	if not hist.is_empty() and age - int(hist.get("last", -999)) < int(def.get("cooldown", 2)):
		return false
	if _sim.crime.in_prison(p) != def.get("tags", []).has("prison"):
		return false
	if not _sim.allows(def.get("tags", [])):
		return false
	return _sim.cond.check_all(def.get("conditions", []), {"actor": actor})


func _pick_actor(def: Dictionary, spawn: bool) -> Dictionary:
	var spec: Dictionary = def.actor
	if spec.has("new"):
		if not spawn:
			return {}
		var npc: Dictionary = _sim.factory.spawn_contextual(spec.new.get("role", "acquaintance"), spec.new)
		_sim.relations.ensure(npc.id, spec.new.get("role", "acquaintance"), float(spec.new.get("score", 40)))
		return npc
	var roles = spec.get("role", [])
	if typeof(roles) == TYPE_STRING:
		roles = [roles]
	var candidates: Array = []
	for role in roles:
		for id in _sim.relations.all_with_role(_sim.player(), role):
			var npc: Dictionary = _sim.state.npc(id)
			if _sim.cond.check_all(def.get("actor_conditions", []), {"actor": npc}):
				candidates.append(npc)
	return _sim.rng.pick(candidates) if not candidates.is_empty() else {}


func _mark_seen(id: String) -> void:
	var hist: Dictionary = _sim.state.data.event_history.get(id, {"count": 0})
	hist.count = int(hist.get("count", 0)) + 1
	hist.last = int(_sim.player().get("age", 0))
	_sim.state.data.event_history[id] = hist


# ---------------------------------------------------------------------------
# Presentation & resolution
# ---------------------------------------------------------------------------

func context_for(inst: Dictionary) -> Dictionary:
	return {"actor": _sim.state.npc(inst.get("actor", ""))}


func params_for(inst: Dictionary) -> Dictionary:
	var p: Dictionary = _sim.player()
	var actor: Dictionary = _sim.state.npc(inst.get("actor", ""))
	var params := {"player": p.get("first_name", ""), "age": p.get("age", 0), "level": p.gamer.level}
	params.o = "a" if p.get("sex", "m") == "f" else "o"
	params.merge(_sim.society.text_params(actor if not actor.is_empty() else p, ""), false)
	if not actor.is_empty():
		params.name = actor.first_name
		params.actor_level = actor.gamer.level
		params.role = "@role." + _sim.relations.role_of(actor.id)
	return params


func visible_choices(inst: Dictionary) -> Array:
	if inst.id == "__talk":
		return _talk_choices(inst)
	var def: Dictionary = _sim.data.events.get(inst.id, {})
	var ctx := context_for(inst)
	var out: Array = []
	for c in def.get("choices", []):
		if _sim.cond.check_all(c.get("conditions", []), ctx):
			out.append(c)
	if out.is_empty():
		out.append({"id": "ok"})
	return out


## A pending conversation started by an NPC: the scene is built once, the
## replies are the choices.
func _talk_choices(inst: Dictionary) -> Array:
	var conv: Dictionary = _sim.state.data.get("conversation", {})
	if conv.is_empty() or conv.get("npc", "") != inst.actor:
		conv = _sim.dialogue.start_conversation(inst.actor, inst.get("concept", "reach"))
	var out: Array = []
	for r in conv.get("replies", []):
		out.append({"id": r.id, "p": r.chance})
	if out.is_empty():
		out.append({"id": "ok"})
	return out


## Chance shown to the player for a choice (the System shows odds!).
func choice_chance(inst: Dictionary, choice: Dictionary) -> float:
	if choice.has("p"):
		return float(choice.p)
	if not choice.has("chance"):
		return -1.0
	return _sim.prob.compute(choice.chance, context_for(inst))


func resolve_current(choice_id: String) -> Dictionary:
	if pending().is_empty():
		return {"ok": false}
	var inst: Dictionary = pending()[0]
	if inst.id == "__talk":
		_talk_choices(inst)
		if choice_id == "ok":
			pending().pop_front()
			_sim.dialogue.end_conversation()
			return {"ok": true, "key": ""}
		var res: Dictionary = _sim.dialogue.reply(choice_id)
		if res.get("ok", false):
			pending().pop_front()
		return res
	var def: Dictionary = _sim.data.events.get(inst.id, {})
	var choice: Dictionary = {}
	for c in visible_choices(inst):
		if c.id == choice_id:
			choice = c
	if choice.is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	pending().pop_front()
	var ctx := context_for(inst)
	var params := params_for(inst)
	_sim.effects.run_all(choice.get("effects", []), ctx)
	var suffix := "res"
	var success := true
	if choice.has("chance"):
		success = _sim.prob.roll_spec(choice.chance, ctx)
		suffix = "ok" if success else "fail"
		_sim.effects.run_all(choice.get("success" if success else "fail", {}).get("effects", []), ctx)
	var key := "ev.%s.%s.%s" % [inst.id, choice.id, suffix]
	if choice.id == "ok" and not def.has("choices"):
		if def.get("log", true):
			_sim.add_log("ev.%s.desc" % inst.id, params, def.get("log_kind", "event"))
		key = ""
	elif def.get("log", true):
		_sim.add_log(key, params, def.get("log_kind", "event"))
	_sim.activities.bump_counter("events.resolved")
	_sim.titles_check()
	return {"ok": true, "success": success, "key": key, "params": params, "gains": ctx.get("gains", {})}
