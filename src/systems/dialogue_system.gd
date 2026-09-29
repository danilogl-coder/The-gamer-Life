class_name DialogueSystem
extends RefCounted
## Context-driven dialogue (rule database with fuzzy best-match, in the
## spirit of Valve's "AI-driven Dynamic Dialog", GDC 2012).
##
## 1. FACTS   Every time someone speaks we build a flat dictionary of facts
##            about the speaker (role, age band, mood, Big Five, voice, traits,
##            interests, politics, job, recent life events, what they know
##            about you, what they remember), about you (age, job, grades,
##            level, fame, money, prison, marriage...), about the world
##            (economy, world events, government, tech era, news, city crime)
##            and about the scene (location, weather, time of day).
## 2. RULES   data/dialogue/*.json: {"id", "concept", "crit": [[fact, op, v]],
##            "w", "n", "reply", "cd", "once", "fx", "place"}. A rule matches
##            when all criteria hold. Score = number of criteria, so the most
##            specific line wins and generic lines are fall-backs.
## 3. PICK    Among the best-scoring rules (plus a near tier for variety) we
##            pick by weight, skipping rules this NPC used recently. Lines are
##            localization keys dlg.<rule>.<i> with {params}.
## 4. REMEMBER Rules may write facts back (per-NPC "said" memory, cooldowns,
##            one-shot lines) so running jokes and follow-ups happen.
##
## A "talk" becomes a scene: setting line → greeting → topic (often about the
## speaker's own life, the news, or what they heard about you) → your reply
## options → their reaction. Replies (data/dialogue_replies.json) succeed or
## fail by the speaker's personality, and change the bond, their mood and
## what they remember.

## Topics adults don't discuss with small children.
const GROWN_UP_TOPICS := ["politics", "news", "money", "city", "work", "gossip", "love", "faith", "grudge"]
const OPS := {"=": "==", "==": "==", "!=": "!=", "<": "<", ">": ">", "<=": "<=", ">=": ">=", "in": "in", "!in": "not_in"}

var _sim
var _by_concept: Dictionary = {}
var _replies: Dictionary = {}


func _init(sim) -> void:
	_sim = sim
	_index()


func _index() -> void:
	_by_concept.clear()
	var rules: Dictionary = _sim.data.dialogue
	var ids: Array = rules.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = rules[id]
		var c: String = r.get("concept", "talk")
		if not _by_concept.has(c):
			_by_concept[c] = []
		_by_concept[c].append(r)
	_replies = _sim.data.table("dialogue_replies")


# ---------------------------------------------------------------------------
# Facts
# ---------------------------------------------------------------------------

## Facts about any character from their own point of view ("sp." prefix when
## speaking, "npc." when used by the NPC life simulation).
func character_facts(ch: Dictionary, prefix: String, out: Dictionary) -> void:
	Persona.ensure(ch, _sim)
	var pz: Dictionary = ch.persona
	var age := int(ch.get("age", 0))
	out[prefix + "age"] = age
	out[prefix + "band." + Persona.age_band(age)] = true
	out[prefix + "sex"] = ch.get("sex", "m")
	out[prefix + "mood"] = Persona.mood(ch)
	out[prefix + "mood." + Persona.mood_band(ch)] = true
	out[prefix + "stress"] = float(ch.attrs.get("stress", 20))
	out[prefix + "health"] = float(ch.attrs.get("health", 80))
	out[prefix + "voice"] = pz.get("voice", "calm")
	out[prefix + "voice." + str(pz.get("voice", "calm"))] = true
	for k in Persona.BIG5:
		out[prefix + k] = float(pz.big5[k])
	for t in ch.get("traits", []):
		out[prefix + "trait." + t] = true
	for i in pz.get("interests", []):
		out[prefix + "likes." + i] = true
	out[prefix + "aspires." + str(pz.get("aspiration", "peace"))] = true
	out[prefix + "pol"] = float(pz.get("politics", 0))
	out[prefix + "pol." + Persona.politics_label(float(pz.get("politics", 0)))] = true
	out[prefix + "faith"] = float(ch.hidden.get("religiousness", 50))
	if float(ch.hidden.get("religiousness", 50)) >= 65:
		out[prefix + "devout"] = true
	out[prefix + "quirk." + str(pz.get("quirk", ""))] = true
	var job: String = ch.career.get("job", "")
	out[prefix + "job"] = job
	if job != "":
		out[prefix + "employed"] = true
		var cat = str(_sim.data.get_def("jobs", job).get("cat", ""))
		out[prefix + "jobcat"] = cat
		out[prefix + "jobcat." + cat] = true
	elif age >= 66:
		out[prefix + "retired"] = true
	elif age >= 18 and not ch.get("is_player", false):
		out[prefix + "unemployed"] = true
	var cash := float(ch.finance.get("cash", 0))
	out[prefix + "cash"] = cash
	out[prefix + "wealth." + str(ch.get("wealth", "middle"))] = true
	if cash > 500000:
		out[prefix + "rich"] = true
	elif cash < 300 and age >= 18:
		out[prefix + "broke"] = true
	if ch.gamer.get("awakened", false) and not ch.get("is_player", false):
		out[prefix + "awakened"] = true
	for cid in ch.health.get("conditions", {}):
		out[prefix + "sick"] = true
		out[prefix + "cond." + cid] = true
	if ch.family.get("spouse", "") != "":
		out[prefix + "married"] = true
	out[prefix + "kids"] = ch.family.get("children", []).size()
	var year = int(_sim.state.data.world_year)
	for e in ch.get("life_log", []):
		var ago: int = year - int(e.y)
		if ago <= 2:
			out[prefix + "ev." + str(e.e)] = true
		if ago <= 0:
			out[prefix + "ev_now." + str(e.e)] = true
	for m in ch.get("known_marks", []):
		out[prefix + "knows." + str(m)] = true
	var team: String = str(pz.get("team", ""))
	if team != "":
		out[prefix + "fan"] = true
		if not _sim.player().is_empty() and int(team) == int(_sim.society.nation().get("champion", -1)):
			out[prefix + "team_won"] = true
	if ch.has("marriage"):
		out[prefix + "marriage"] = float(ch.marriage)


func build_facts(npc: Dictionary, concept: String, extra: Dictionary = {}) -> Dictionary:
	var p: Dictionary = _sim.player()
	var f := {"concept": concept}
	character_facts(npc, "sp.", f)
	var role: String = _sim.relations.role_of(npc.id)
	f["role"] = role
	f["role." + role] = true
	if RelationshipSystem.FAMILY_ROLES.has(role):
		f["family"] = true
	f["bond"] = _sim.relations.score(npc.id)
	f["compat"] = _sim.relations.compatibility(npc)
	if npc.sex == p.sex:
		f["same_sex"] = true
	var mems := {}
	for m in npc.get("memory", []):
		mems[m.m] = float(mems.get(m.m, 0)) + float(m.sev)
		f["mem." + str(m.m)] = true
	f["grudge"] = _sim.relations.memory_weight(npc.id)
	var said: Dictionary = npc.get("said", {})
	f["talks"] = int(said.get("_n", 0))
	for k in said:
		f["said." + str(k)] = true
	_player_facts(p, f)
	var ppol := float(p.get("persona", {}).get("politics", 0.0))
	var spol := float(npc.persona.get("politics", 0.0))
	if absf(ppol) > 20 and absf(spol) > 20:
		f["aligned" if signf(ppol) == signf(spol) else "misaligned"] = true
	_world_facts(f)
	_scene_facts(npc, role, f)
	f.merge(extra, true)
	return f


func _player_facts(p: Dictionary, f: Dictionary) -> void:
	var age := int(p.age)
	f["p.age"] = age
	f["p.band." + Persona.age_band(age)] = true
	f["p.sex"] = p.sex
	f["p.level"] = int(p.gamer.level)
	f["p.rank"] = int(p.gamer.get("rank", 0))
	f["p.fame"] = float(p.get("fame", 0))
	if float(p.get("fame", 0)) >= 40:
		f["p.famous"] = true
	f["p.looks"] = float(p.attrs.looks)
	f["p.happy"] = float(p.attrs.happiness)
	f["p.stress"] = float(p.attrs.stress)
	f["p.health"] = float(p.attrs.health)
	if float(p.attrs.health) < 40:
		f["p.ill"] = true
	var cash := float(p.finance.cash)
	f["p.cash"] = cash
	if cash > 1000000:
		f["p.rich"] = true
	elif cash < 500 and age >= 18:
		f["p.broke"] = true
	if float(p.finance.get("debt", 0)) > 20000:
		f["p.debt"] = true
	var job: String = p.career.get("job", "")
	f["p.job"] = job
	if job != "":
		f["p.employed"] = true
		f["p.jobcat." + str(_sim.data.get_def("jobs", job).get("cat", ""))] = true
	elif age >= 18 and p.education.get("stage", "") == "":
		f["p.unemployed"] = true
	var stage: String = p.education.get("stage", "")
	if stage != "":
		f["p.student"] = true
		f["p.stage." + stage] = true
		f["p.grades"] = float(p.education.get("grades", 50))
	for c in p.education.get("completed", []):
		f["p.done." + str(c)] = true
	if _sim.crime.in_prison(p):
		f["p.prison"] = true
	if not p.criminal.get("record", []).is_empty():
		f["p.record"] = true
	for hid in p.health.get("habits", {}):
		if float(p.health.habits[hid]) >= 50:
			f["p.addict." + hid] = true
			f["p.addict"] = true
	if p.family.get("spouse", "") != "":
		f["p.married"] = true
	elif _sim.relations.partner_id(p) != "":
		f["p.dating"] = true
	elif age >= 18:
		f["p.single"] = true
	f["p.kids"] = p.family.get("children", []).size()
	if not p.get("pets", []).is_empty():
		f["p.pet"] = true
	var sp: Dictionary = p.get("special", {})
	for k in sp:
		f["p.special." + str(k)] = true
	f["p.pop"] = float(p.get("school", {}).get("popularity", 30))
	for e in p.get("life_log", []):
		if int(_sim.state.data.world_year) - int(e.y) <= 1:
			f["p.ev." + str(e.e)] = true


func _world_facts(f: Dictionary) -> void:
	var w: Dictionary = _sim.state.data.world
	var econ := float(w.get("economy", 0))
	f["w.economy"] = econ
	if econ < -0.35:
		f["w.bad_economy"] = true
	elif econ > 0.35:
		f["w.good_economy"] = true
	for id in w.get("events", {}):
		f["we." + str(id)] = true
	_sim.society.world_facts(f)


## Where and when the conversation happens. Deterministic per NPC and year so
## the same scene does not flicker when re-opened.
func _scene_facts(npc: Dictionary, role: String, f: Dictionary) -> void:
	var p: Dictionary = _sim.player()
	var loc := "home"
	if _sim.crime.in_prison(p):
		loc = "prison"
	elif (role in ["classmate", "teacher"] and p.education.get("stage", "") != "") or (role in ["friend", "best_friend", "rival"] and int(p.age) < 18 and _sim.rng.randf() < 0.5):
		loc = "school"
	elif role in ["coworker", "boss"]:
		loc = "work"
	elif role in ["friend", "best_friend", "partner", "ex", "acquaintance", "rival", "enemy", "classmate", "teacher"]:
		loc = _sim.rng.pick(["cafe", "bar", "park", "street", "phone"]) if int(p.age) >= 16 else _sim.rng.pick(["park", "street", "phone"])
	elif role in ["mother", "father", "stepparent", "grandparent", "sibling", "child", "grandchild", "spouse"]:
		loc = _sim.rng.pick(["kitchen", "living_room", "car", "phone", "table"]) if not p.get("moved_out", int(p.age) >= 18) or role in ["spouse", "child"] else _sim.rng.pick(["phone", "visit", "table"])
	if _sim.state.data.world.get("events", {}).has("epidemic") and loc not in ["home", "kitchen", "living_room", "prison"]:
		loc = "video_call"
	if int(npc.age) >= 75 and float(npc.attrs.health) < 35:
		loc = "hospital_bed"
	f["loc"] = loc
	f["loc." + loc] = true
	f["weather." + _sim.rng.pick(["sun", "sun", "rain", "cold", "hot", "wind", "storm"])] = true
	f["time." + _sim.rng.pick(["morning", "afternoon", "night"])] = true


# ---------------------------------------------------------------------------
# Rule matching
# ---------------------------------------------------------------------------

static func truthy(v) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		TYPE_STRING:
			return v != ""
	return true


func matches(rule: Dictionary, facts: Dictionary) -> bool:
	for c in rule.get("crit", []):
		if not _crit(c, facts):
			return false
	return true


func _crit(c: Array, facts: Dictionary) -> bool:
	var key: String = c[0]
	if c.size() == 1:
		return truthy(facts.get(key, false))
	var op: String = c[1]
	if op == "!":
		return not truthy(facts.get(key, false))
	var v = c[2] if c.size() > 2 else true
	if not facts.has(key):
		return op == "!=" or op == "!in"
	return ConditionEvaluator.compare(facts[key], OPS.get(op, op), v)


## Best rule for a concept, or {} when nothing matches.
func best(concept: String, npc: Dictionary, facts: Dictionary) -> Dictionary:
	var said: Dictionary = npc.get("said", {})
	var year := int(_sim.state.data.world_year)
	var young := int(_sim.player().get("age", 30)) < 12
	var scored: Array = []
	var top := -1
	for r in _by_concept.get(concept, []):
		if not _sim.allows(r.get("tags", [])):
			continue
		var last := int(said.get(r.id, -9999))
		if r.get("once", false) and last > -9999:
			continue
		if year - last < int(r.get("cd", 0)):
			continue
		if young and GROWN_UP_TOPICS.has(r.get("topic", "")) and not r.get("kid_ok", false):
			continue
		if not matches(r, facts):
			continue
		var s: int = r.get("crit", []).size() + int(r.get("bonus", 0))
		# Recently said lines step aside so people don't repeat themselves.
		if year - last <= 3 and r.get("crit", []).size() > 0:
			s -= 2
		scored.append([r, s])
		top = maxi(top, s)
	if scored.is_empty():
		return {}
	var recent: Array = npc.get("said_recent", [])
	var pool: Array = []
	var weights: Array = []
	for pair in scored:
		var s: int = pair[1]
		if s < top - 1:
			continue
		var w := float(pair[0].get("w", 1.0)) * (3.0 if s == top else 1.0)
		if recent.has(pair[0].id):
			w *= 0.05
		pool.append(pair[0])
		weights.append(w)
	return _sim.rng.pick_weighted(pool, weights)


func _remember(npc: Dictionary, rule: Dictionary) -> void:
	if not npc.has("said"):
		npc.said = {}
	npc.said[rule.id] = int(_sim.state.data.world_year)
	var recent: Array = npc.get("said_recent", [])
	recent.append(rule.id)
	if recent.size() > 12:
		recent.pop_front()
	npc.said_recent = recent
	for k in rule.get("remember", []):
		npc.said[k] = int(_sim.state.data.world_year)


## Renders a rule into a timeline-style entry {key, params}.
func line(rule: Dictionary, npc: Dictionary, facts: Dictionary) -> Dictionary:
	var n := maxi(1, int(rule.get("n", 1)))
	var idx: int = _sim.rng.randi_range(0, n - 1)
	var key := "dlg.%s.%d" % [rule.id, idx]
	_remember(npc, rule)
	return {"key": key, "params": params_for(npc, facts, rule), "rule": rule.id}


## Say something for a concept. Returns {} when no rule matches.
func say(concept: String, npc: Dictionary, facts: Dictionary) -> Dictionary:
	var r := best(concept, npc, facts)
	if r.is_empty():
		return {}
	return line(r, npc, facts)


# ---------------------------------------------------------------------------
# Parameters (text substitutions)
# ---------------------------------------------------------------------------

func params_for(npc: Dictionary, facts: Dictionary, rule: Dictionary = {}) -> Dictionary:
	var p: Dictionary = _sim.player()
	var pt: bool = p.sex == "f"
	var st: bool = npc.get("sex", "m") == "f"
	var prm := {
		"name": npc.get("first_name", ""), "player": p.first_name, "surname": p.last_name,
		"o": "a" if pt else "o", "sp_o": "a" if st else "o", "sp_o_up": "A" if st else "O",
		"ele": "ela" if pt else "ele", "sp_ele": "ela" if st else "ele",
		"filho": "filha" if pt else "filho", "son": "daughter" if pt else "son",
		"neto": "neta" if pt else "neto", "grandkid": "granddaughter" if pt else "grandson",
		"irmao": "irmã" if pt else "irmão", "sib": "sister" if pt else "brother",
		"querido": "querida" if pt else "querido",
		"mano": "mana" if pt else "mano",
		"campeao": "campeã" if pt else "campeão",
		"outro_pai": "sua mãe" if npc.get("sex", "m") == "m" else "seu pai",
		"other_parent": "your mom" if npc.get("sex", "m") == "m" else "your dad",
		"age": p.age, "sp_age": npc.get("age", 0), "level": p.gamer.level,
		"job": "@job." + str(p.career.job) if p.career.get("job", "") != "" else "—",
		"sp_job": "@job." + str(npc.career.job) if npc.career.get("job", "") != "" else "—",
		"interest": "@interest." + str(npc.persona.interests[0]),
		"interest2": "@interest." + str(npc.persona.interests[-1]),
		"quirk": "@quirk." + str(npc.persona.get("quirk", "late")),
		"voice_catch": "@dlgcatch.%s.%d" % [npc.persona.get("voice", "calm"), int(npc.persona.get("catch", 0))],
	}
	prm.merge(_sim.society.text_params(npc, rule.get("place", "")), true)
	var pref: String = _sim.factory._preferred_sex(p) if p.get("sexuality", "straight") != "bi" else ("m" if p.sex == "f" else "f")
	prm.pref_o = "a" if pref == "f" else "o"
	prm.pref_art = prm.pref_o
	prm.Pref_art = prm.pref_o.to_upper()
	prm.nephew = "niece" if pref == "f" else "nephew"
	prm.pref_kid = "daughter" if pref == "f" else "son"
	var spouse = _sim.relations.spouse_id(p)
	prm.spouse = _sim.state.npc(spouse).get("first_name", "") if spouse != "" else ""
	var partner = _sim.relations.partner_id(p)
	prm.partner = _sim.state.npc(partner).get("first_name", "") if partner != "" else ""
	var kids: Array = p.family.get("children", [])
	prm.child = _sim.state.npc(kids[0]).get("first_name", "") if not kids.is_empty() and _sim.state.has_npc(kids[0]) else ""
	var sib = _sim.relations.first_with_role(p, "sibling")
	prm.sibling = _sim.state.npc(sib).get("first_name", "") if sib != "" and sib != npc.id else prm.name
	var top_skill := ""
	var top_lvl := -1
	for sid in p.gamer.get("skills", {}):
		var lv := int(p.gamer.skills[sid].get("level", 0))
		if lv > top_lvl:
			top_lvl = lv
			top_skill = sid
	prm.skill = "@skill." + top_skill + ".name" if top_skill != "" else "—"
	var ev := _latest_life_event(npc)
	for k in ev.get("p", {}):
		prm["ev_" + str(k)] = ev.p[k]
	if npc.has("city"):
		prm.npc_city = npc.city
	var their: String = npc.family.get("spouse", "")
	prm.their_spouse = _sim.state.npc(their).get("first_name", "") if their != "" else ""
	prm.sign = "@zodiac." + CharacterFactory.zodiac_of(p)
	prm.merge(facts.get("_params", {}), true)
	return prm


func _latest_life_event(npc: Dictionary) -> Dictionary:
	var log: Array = npc.get("life_log", [])
	return log[-1] if not log.is_empty() else {}


# ---------------------------------------------------------------------------
# Conversations (scenes)
# ---------------------------------------------------------------------------

## Builds a full scene. concept: "talk" (player initiated) or "reach" (the NPC
## called you). Returns {npc, lines: [{key, params, kind}], replies: [...]}.
func start_conversation(npc_id: String, concept: String = "talk", extra: Dictionary = {}) -> Dictionary:
	var npc: Dictionary = _sim.state.npc(npc_id)
	if npc.is_empty():
		return {}
	var facts := build_facts(npc, concept, extra)
	var lines: Array = []
	var setting := say("setting", npc, facts)
	if not setting.is_empty():
		setting.kind = "narration"
		lines.append(setting)
	var greet := say("greet", npc, facts)
	if not greet.is_empty():
		greet.kind = "quote"
		lines.append(greet)
	if int(_sim.player().age) < 4:
		concept = "baby"
	var topic_rule := best(concept, npc, facts)
	if topic_rule.is_empty():
		topic_rule = best("talk", npc, facts)
	var replies: Array = []
	if not topic_rule.is_empty():
		var tl := line(topic_rule, npc, facts)
		tl.kind = "quote"
		lines.append(tl)
		if _sim.rng.randf() < 0.22:
			var c := say("catch", npc, facts)
			if not c.is_empty():
				c.kind = "quote"
				lines.append(c)
		replies = _reply_options(topic_rule, npc, facts)
	if not npc.has("said"):
		npc.said = {}
	npc.said["_n"] = int(npc.said.get("_n", 0)) + 1
	var conv := {"npc": npc_id, "concept": concept, "topic": topic_rule.get("id", ""), "lines": lines, "replies": replies, "facts": _slim(facts)}
	_sim.state.data.conversation = conv
	return conv


func _slim(facts: Dictionary) -> Dictionary:
	var out := {}
	for k in facts:
		if typeof(facts[k]) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			out[k] = facts[k]
	return out


func _reply_options(rule: Dictionary, npc: Dictionary, facts: Dictionary) -> Array:
	var group: String = rule.get("reply", "")
	if group == "":
		group = "chat"
	var out: Array = []
	for rid in _sim.data.table("dialogue_replies"):
		var def: Dictionary = _replies[rid]
		if not def.get("groups", []).has(group):
			continue
		if not _crit_all(def.get("crit", []), facts):
			continue
		out.append({"id": rid, "chance": reply_chance(def, facts), "cost": float(def.get("cost", 0))})
	out.sort_custom(func(a, b): return int(_replies[a.id].get("order", 50)) < int(_replies[b.id].get("order", 50)))
	return out


func _crit_all(crits: Array, facts: Dictionary) -> bool:
	for c in crits:
		if not _crit(c, facts):
			return false
	return true


## How likely the speaker is to take this reply well. Mods: [fact, per, offset]
## numeric, or [fact, bonus] for boolean tags.
func reply_chance(def: Dictionary, facts: Dictionary) -> float:
	var ch := float(def.get("base", 0.6))
	for m in def.get("mods", []):
		var v = facts.get(m[0], null)
		if m.size() == 2:
			if truthy(v):
				ch += float(m[1])
		elif v != null:
			ch += (float(v) - float(m[2])) * float(m[1])
	ch += _sim.gamer.mod("social_gain") * 0.2
	return clampf(ch, 0.03, 0.97)


## Player picks a reply in the current conversation.
func reply(reply_id: String) -> Dictionary:
	var conv: Dictionary = _sim.state.data.get("conversation", {})
	if conv.is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	var opt: Dictionary = {}
	for r in conv.replies:
		if r.id == reply_id:
			opt = r
	if opt.is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	var def: Dictionary = _replies[reply_id]
	var p: Dictionary = _sim.player()
	if float(def.get("cost", 0)) > 0.0:
		if float(p.finance.cash) < float(def.cost):
			return {"ok": false, "reason": "ui.no_money"}
	var npc: Dictionary = _sim.state.npc(conv.npc)
	var good: bool = _sim.prob.roll_neutral(float(opt.chance))
	if not npc.has("said"):
		npc.said = {}
	npc.said["r_" + reply_id] = int(_sim.state.data.world_year)
	var facts := build_facts(npc, "react", {"reply": reply_id, "reply." + reply_id: true, "good": good, "topic": conv.topic, "topic." + str(conv.topic): true})
	var ctx := {"actor": npc}
	var branch: Dictionary = def.get("good" if good else "bad", {})
	_sim.effects.run_all(branch.get("effects", []), ctx)
	var mood := float(branch.get("mood", 0))
	npc.attrs.happiness = clampf(float(npc.attrs.happiness) + mood, 0, 100)
	if branch.has("memory"):
		_sim.relations.add_memory(npc.id, branch.memory, float(branch.get("sev", 10)))
	var topic_rule: Dictionary = _sim.data.dialogue.get(conv.topic, {})
	if good:
		_sim.effects.run_all(topic_rule.get("fx_good", {}).get(reply_id, []), ctx)
	var out_lines: Array = []
	var react := say("react", npc, facts)
	if not react.is_empty():
		react.kind = "quote"
		out_lines.append(react)
	var outcome := {"key": "dlgui.%s.%s" % [reply_id, "good" if good else "bad"], "params": params_for(npc, facts), "kind": "narration"}
	out_lines.append(outcome)
	_sim.activities.bump_counter("social.replies")
	if good:
		_sim.activities.bump_counter("social.good_replies")
	_sim.gamer.add_stat_xp(p, "cha", 3.0 if good else 1.0)
	if _sim.skills.knows(p, "negotiation"):
		_sim.skills.add_xp(p, "negotiation", 2.0)
	_sim.state.data.conversation = {}
	_sim.add_log("log.talked", {"name": npc.first_name, "topic": "@dlgtopic." + str(topic_rule.get("topic", "chat")), "mood": "@dlgui.mood_" + ("good" if good else "bad")}, "social")
	return {"ok": true, "success": good, "lines": out_lines, "gains": ctx.get("gains", {})}


## Plain "Continue" (no reply groups) still closes the conversation.
func end_conversation() -> void:
	var conv: Dictionary = _sim.state.data.get("conversation", {})
	if conv.is_empty():
		return
	var npc: Dictionary = _sim.state.npc(conv.npc)
	if not npc.is_empty():
		_sim.relations.change_score(npc.id, 1.0)
	_sim.state.data.conversation = {}


## Short in-character reaction after any social interaction.
func react_to_interaction(npc: Dictionary, interaction_id: String, success: bool) -> Dictionary:
	var facts := build_facts(npc, "int", {"int": interaction_id, "int." + interaction_id: true, "good": success})
	var concept := "int.%s.%s" % [interaction_id, "ok" if success else "fail"]
	var r := say(concept, npc, facts)
	if r.is_empty():
		r = say("int.any.%s" % ("ok" if success else "fail"), npc, facts)
	return r


## A one-line reaction when an event involves this NPC.
func react_to_event(npc: Dictionary, tags: Array) -> Dictionary:
	var extra := {}
	for t in tags:
		extra["evtag." + str(t)] = true
	var facts := build_facts(npc, "event", extra)
	return say("event", npc, facts)


# ---------------------------------------------------------------------------
# NPCs reaching out (they call you)
# ---------------------------------------------------------------------------

## Each year a few people close to you get in touch on their own, because of
## something in their life, yours, or the world. The scene is queued as a
## pending "talk" the player must answer (like an event).
func process_year(p: Dictionary) -> void:
	if int(p.age) < 5:
		return
	var budget: int = _sim.rng.pick_weighted([0, 1, 1, 2, 2, 3], [1, 2, 2, 2, 1, 1])
	var ids: Array = p.get("rels", {}).keys()
	ids.sort()
	var cands: Array = []
	var weights: Array = []
	for id in ids:
		var npc: Dictionary = _sim.state.npc(id)
		if npc.is_empty() or not npc.alive or int(npc.age) < 5:
			continue
		var bond = _sim.relations.score(id)
		var w: float = 0.3 + bond / 50.0
		if not npc.get("life_log", []).is_empty() and int(_sim.state.data.world_year) - int(npc.life_log[-1].y) <= 1:
			w += 2.0
		if RelationshipSystem.FAMILY_ROLES.has(_sim.relations.role_of(id)):
			w += 0.8
		cands.append(id)
		weights.append(w)
	var queued := 0
	var guard := 0
	while queued < budget and not cands.is_empty() and guard < 8:
		guard += 1
		var id = _sim.rng.pick_weighted(cands, weights)
		var i := cands.find(id)
		cands.remove_at(i)
		weights.remove_at(i)
		var npc: Dictionary = _sim.state.npc(id)
		var facts := build_facts(npc, "reach")
		if best("reach", npc, facts).is_empty():
			continue
		_sim.state.data.pending_events.append({"id": "__talk", "actor": id, "concept": "reach"})
		queued += 1
