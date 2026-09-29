class_name CharacterFactory
extends RefCounted
## Builds coherent characters (player, family, contextual NPCs). Coherence rules:
## ages match roles, jobs match ages/education, children inherit genes from
## parents, wealth class shapes parents' careers.

const STAT_IDS := ["str", "vit", "dex", "int", "wis", "luk", "cha"]
const HIDDEN_IDS := [
	"fertility", "talent_music", "talent_sport", "talent_art", "academic",
	"aggression", "impulsivity", "courage", "empathy", "ambition", "loyalty",
	"greed", "addiction_resist", "disease_risk", "stress_tolerance", "longevity",
	"mana_affinity", "karma", "willpower", "generosity", "craziness", "religiousness",
	"professionalism", "athleticism",
]
const ZODIAC := ["capricorn", "aquarius", "pisces", "aries", "taurus", "gemini", "cancer",
	"leo", "virgo", "libra", "scorpio", "sagittarius"]
const ZODIAC_ELEMENT := {"aries": "fire", "leo": "fire", "sagittarius": "fire", "taurus": "earth",
	"virgo": "earth", "capricorn": "earth", "gemini": "air", "libra": "air", "aquarius": "air",
	"cancer": "water", "scorpio": "water", "pisces": "water"}
const WEALTH_CLASSES := ["poor", "working", "middle", "upper", "elite"]

var _sim


func _init(sim) -> void:
	_sim = sim


# ---------------------------------------------------------------------------
# Player
# ---------------------------------------------------------------------------

func create_newborn_player(options: Dictionary) -> Dictionary:
	var countries: Array = _sim.data.table("countries").keys()
	countries.sort()
	var country: String = options.get("country", _sim.rng.pick(countries))
	var cdef: Dictionary = _sim.data.get_def("countries", country)
	var wealth: String = options.get("wealth", _sim.rng.pick_weighted(WEALTH_CLASSES, cdef.get("wealth_weights", [2, 3, 3, 1.5, 0.5])))
	var structure: String = _pick_family_structure()
	var family := _create_parents(country, wealth, structure)
	var mother: Dictionary = family.get("mother", {})
	var father: Dictionary = family.get("father", {})

	var sex: String = options.get("sex", _sim.rng.pick(["m", "f"]))
	var last_name: String = father.get("last_name", mother.get("last_name", _random_last(country)))
	var p := _base_character(country, sex, 0)
	p.last_name = last_name
	p.first_name = options.get("first_name", _random_first(country, sex))
	p.is_player = true
	p.wealth = wealth
	p.family_structure = structure
	_inherit_genes(p, mother, father)
	_add_player_fields(p)
	_sim.state.add_npc(p)
	_sim.state.data.player_id = p.id
	_sim.state.data.legacy.dynasty = last_name if _sim.state.data.legacy.dynasty == "" else _sim.state.data.legacy.dynasty

	# Link family.
	for role in family:
		var member: Dictionary = family[role]
		_sim.state.add_npc(member)
		_sim.relations.ensure(member.id, role, _sim.rng.randf_range(55, 85))
		member.family.children.append(p.id)
	p.family.mother = mother.get("id", "")
	p.family.father = father.get("id", "")
	_create_siblings(p, mother, father)
	_create_grandparents(p, mother, father)
	_sim.add_log("log.born", {"name": p.first_name + " " + p.last_name, "country": "@country." + country, "wealth": "@wealth." + wealth}, "major")
	if structure != "married":
		_sim.add_log("log.family_" + structure, {}, "info")
	return p


## Turns an existing NPC (heir) into a playable character.
func promote_to_player(npc: Dictionary) -> void:
	npc.is_player = true
	_add_player_fields(npc)


func _add_player_fields(p: Dictionary) -> void:
	p.merge({
		"year_counters": {},
		"time": {"slots": 0, "used": 0},
		"quests": {"active": {}, "done": [], "failed": []},
		"discovered": [],
		"rels": {},
		"criminal": {"record": [], "heat": 0.0, "prison": {}},
		"fame": 0.0,
		"faction": {"id": "", "rank": 0, "rep": {}},
		"recent_actions": [],
		"favorites": [],
		"special": {},
		"pets": [],
		"school": {"popularity": 30.0, "clique": "", "clubs": {}},
		"will": {"mode": "equal", "favorite": ""},
		"licenses": [],
		"job_hours": "normal",
		"surgeries": {},
	}, false)
	p.gamer.merge({"awakened": true, "exp": 0.0, "stat_points": 0, "stat_xp": {},
		"skills": {}, "titles": [], "title": "", "inventory": {}, "equipment": {}}, false)
	p.finance.merge({"debt": 0.0, "credit": 650.0, "loans": [], "properties": [], "investments": {}, "lifestyle": "normal", "possessions": []}, false)


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

## Generic NPC relative to the player (classmate, coworker, date, rival...).
## spec: {"role", "age_min", "age_max", "age_rel": offset from player,
##        "sex": "opposite"/"same"/..., "awakened": bool}
func spawn_contextual(role: String, spec: Dictionary = {}) -> Dictionary:
	var p: Dictionary = _sim.player()
	var page := int(p.get("age", 20))
	var age: int
	if spec.has("age_min"):
		age = _sim.rng.randi_range(int(spec.age_min), int(spec.age_max))
	else:
		var spread := int(spec.get("age_spread", 2))
		age = maxi(0, page + int(spec.get("age_rel", 0)) + _sim.rng.randi_range(-spread, spread))
	var sex: String = _sim.rng.pick(["m", "f"])
	match spec.get("sex", ""):
		"opposite": sex = "f" if p.sex == "m" else "m"
		"same": sex = p.sex
		"m", "f": sex = spec.sex
		"pref": sex = _preferred_sex(p)
	var npc := create_npc(p.country, sex, age, spec.get("wealth", ""))
	npc.origin_role = role
	if spec.get("awakened", false):
		make_awakened(npc, int(spec.get("level_min", maxi(1, int(p.gamer.level) - 5))), int(spec.get("level_max", int(p.gamer.level) + 8)))
	_sim.state.add_npc(npc)
	return npc


func create_npc(country: String, sex: String, age: int, wealth: String = "") -> Dictionary:
	var npc := _base_character(country, sex, age)
	npc.first_name = _random_first(country, sex)
	npc.last_name = _random_last(country)
	npc.wealth = wealth if wealth != "" else _sim.rng.pick_weighted(WEALTH_CLASSES, [2, 3, 3, 1.5, 0.5])
	_grow_to_age(npc)
	_sim.career.assign_npc_job(npc)
	npc.finance.cash = _sim.finance.npc_starting_cash(npc)
	return npc


func create_child(mother: Dictionary, father: Dictionary) -> Dictionary:
	var base: Dictionary = mother if not mother.is_empty() else father
	var npc := _base_character(base.get("country", "brava"), _sim.rng.pick(["m", "f"]), 0)
	npc.first_name = _random_first(npc.country, npc.sex)
	npc.last_name = father.get("last_name", mother.get("last_name", _random_last(npc.country)))
	npc.wealth = base.get("wealth", "middle")
	_inherit_genes(npc, mother, father)
	npc.family.mother = mother.get("id", "")
	npc.family.father = father.get("id", "")
	# Children of a System user may carry a dormant spark of it.
	var pgamer: Dictionary = _sim.player().get("gamer", {})
	if (mother.get("is_player", false) or father.get("is_player", false)) and int(pgamer.get("level", 1)) > 1:
		npc.gamer.bloodline = true
	_sim.state.add_npc(npc)
	for parent in [mother, father]:
		if not parent.is_empty():
			parent.family.children.append(npc.id)
	return npc


func make_awakened(npc: Dictionary, lvl_min: int, lvl_max: int) -> void:
	var lvl := maxi(1, _sim.rng.randi_range(lvl_min, lvl_max))
	npc.gamer.level = lvl
	npc.gamer.awakened = true
	var pts := lvl * int(_sim.data.bal("gamer.points_per_level", 5))
	for i in pts:
		var s: String = _sim.rng.pick(STAT_IDS)
		npc.gamer.stats[s] = float(npc.gamer.stats[s]) + 1.0


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _base_character(country: String, sex: String, age: int) -> Dictionary:
	var id: String = _sim.state.new_id("c")
	var hidden := {}
	for h in HIDDEN_IDS:
		hidden[h] = clampf(_sim.rng.randn(50, 16), 1, 99)
	hidden.karma = 50.0
	var stats := {}
	for s in STAT_IDS:
		stats[s] = float(_sim.rng.randi_range(1, 3))
	var ch := {
		"id": id, "first_name": "", "last_name": "", "sex": sex, "age": age,
		"alive": true, "is_player": false, "country": country, "wealth": "middle",
		"look": {
			"skin": _sim.rng.randi_range(0, 5), "hair": _sim.rng.randi_range(0, 7),
			"style": _sim.rng.randi_range(0, 5), "eyes": _sim.rng.randi_range(0, 4),
			"bg": _sim.rng.randi_range(0, 5),
		},
		"attrs": {
			"health": _sim.rng.randf_range(75, 100), "happiness": _sim.rng.randf_range(55, 90),
			"stress": _sim.rng.randf_range(5, 25), "looks": clampf(_sim.rng.randn(50, 18), 5, 99),
			"discipline": clampf(_sim.rng.randn(45, 15), 5, 95), "reputation": 50.0,
		},
		"hidden": hidden,
		"traits": _random_traits(),
		"gamer": {"level": 1, "stats": stats, "hp": 1.0, "mp": 1.0, "rank": 0, "awakened": false},
		"education": {"stage": "", "years": 0, "grades": 50.0, "completed": [], "major": "", "absences": 0},
		"career": {"job": "", "level": 0, "years": 0, "performance": 50.0, "salary": 0.0, "history": []},
		"finance": {"cash": 0.0},
		"health": {"conditions": {}, "fitness": 30.0, "habits": {}, "weight": 0.0},
		"family": {"mother": "", "father": "", "spouse": "", "children": [], "siblings": []},
		"memory": [],
		"sexuality": _sim.rng.pick_weighted(["straight", "gay", "bi"], [88, 6, 6]),
		"birth_month": _sim.rng.randi_range(1, 12),
		"life_log": [],
		"known_marks": [],
	}
	Persona.build(ch, _sim)
	return ch


static func zodiac_of(ch: Dictionary) -> String:
	return ZODIAC[(int(ch.get("birth_month", 1)) - 1) % 12]


func _random_traits() -> Array:
	var all: Array = _sim.data.table("traits").keys()
	all.sort()
	var chosen: Array = []
	var n: int = _sim.rng.randi_range(2, 3)
	var guard := 0
	while chosen.size() < n and guard < 30:
		guard += 1
		var t: String = _sim.rng.pick(all)
		if chosen.has(t):
			continue
		var conflict := false
		for c in chosen:
			if _sim.data.get_def("traits", c).get("opposite", "") == t:
				conflict = true
		if not conflict:
			chosen.append(t)
	return chosen


func _pick_family_structure() -> String:
	var opts := ["married", "separated", "single_mother", "single_father", "adopted"]
	return _sim.rng.pick_weighted(opts, _sim.data.bal("family.structure_weights", [62, 16, 13, 4, 5]))


func _create_parents(country: String, wealth: String, structure: String) -> Dictionary:
	var out := {}
	var mom_age: int = _sim.rng.randi_range(19, 40)
	var mother := create_npc(country, "f", mom_age, wealth)
	var father := create_npc(country, "m", clampi(mom_age + _sim.rng.randi_range(-3, 7), 19, 55), wealth)
	match structure:
		"single_mother":
			out.mother = mother
		"single_father":
			out.father = father
		_:
			out.mother = mother
			out.father = father
			if structure == "married" or structure == "adopted":
				mother.family.spouse = father.id
				father.family.spouse = mother.id
				father.last_name = father.last_name
				mother.last_name = father.last_name
	return out


func _create_siblings(p: Dictionary, mother: Dictionary, father: Dictionary) -> void:
	var count: int = _sim.rng.pick_weighted([0, 1, 2, 3], [30, 40, 20, 10])
	var parent_age := int(mother.get("age", father.get("age", 30)))
	for i in count:
		var age: int = _sim.rng.randi_range(1, clampi(parent_age - 18, 1, 14))
		var sib := create_child(mother, father)
		sib.age = age
		_grow_to_age(sib)
		p.family.siblings.append(sib.id)
		sib.family.siblings.append(p.id)
		_sim.relations.ensure(sib.id, "sibling", _sim.rng.randf_range(45, 80))


func _create_grandparents(p: Dictionary, mother: Dictionary, father: Dictionary) -> void:
	for parent in [mother, father]:
		if parent.is_empty() or not _sim.prob.roll_neutral(0.6):
			continue
		var sex: String = _sim.rng.pick(["m", "f"])
		var gp := create_npc(parent.country, sex, int(parent.age) + _sim.rng.randi_range(20, 32), parent.wealth)
		gp.last_name = parent.last_name
		gp.career.job = ""
		gp.family.children.append(parent.id)
		_sim.state.add_npc(gp)
		_sim.relations.ensure(gp.id, "grandparent", _sim.rng.randf_range(55, 90))


## Coherent aging for generated NPCs: stats, education and wealth by age.
func _grow_to_age(npc: Dictionary) -> void:
	var age := int(npc.age)
	var growth := minf(age, 18) * 0.6 + maxf(0, age - 18) * 0.05
	for s in STAT_IDS:
		npc.gamer.stats[s] = roundf(float(npc.gamer.stats[s]) + growth * _sim.rng.randf_range(0.6, 1.3))
	_sim.education.assign_npc_education(npc)
	npc.attrs.health = clampf(float(npc.attrs.health) - maxf(0, age - 45) * 0.8, 10, 100)


func _inherit_genes(child: Dictionary, mother: Dictionary, father: Dictionary) -> void:
	var parents: Array = []
	for par in [mother, father]:
		if not par.is_empty():
			parents.append(par)
	if parents.is_empty():
		return
	for key in ["skin", "hair", "eyes"]:
		child.look[key] = _sim.rng.pick(parents).look[key]
	for h in HIDDEN_IDS:
		var avg := 0.0
		for par in parents:
			avg += float(par.hidden.get(h, 50))
		avg /= parents.size()
		child.hidden[h] = clampf(avg * 0.6 + _sim.rng.randn(50, 16) * 0.4, 1, 99)
	child.attrs.looks = clampf((float(parents[0].attrs.looks) + _sim.rng.randn(50, 18)) / 2.0, 5, 99)
	Persona.inherit(child, parents, _sim)


func _random_first(country: String, sex: String) -> String:
	var culture: String = _sim.data.get_def("countries", country).get("culture", "pt")
	var pool: Array = _sim.data.names.get(culture, {}).get(sex, ["Alex"])
	return _sim.rng.pick(pool)


func _random_last(country: String) -> String:
	var culture: String = _sim.data.get_def("countries", country).get("culture", "pt")
	var pool: Array = _sim.data.names.get(culture, {}).get("last", ["Silva"])
	return _sim.rng.pick(pool)


func _preferred_sex(p: Dictionary) -> String:
	var other := "f" if p.sex == "m" else "m"
	match p.get("sexuality", "straight"):
		"gay": return p.sex
		"bi": return _sim.rng.pick([p.sex, other])
	return other
