class_name SocietySystem
extends RefCounted
## The living world around the player. It runs every year whether or not the
## player takes part, and it listens to what the player does.
##
##  NATIONS     each country has cities, a home city with places (bakery, bar,
##              gym, guild hall...) that open and close with the economy, a
##              crime rate, prosperity and pollution, a sports league, and a
##              GOVERNMENT: party in power, leader, approval, policies (tax,
##              welfare, police, rift law) and elections every 4 years.
##  TECH        a technology level that unlocks eras (smartphones, AI,
##              automation, mana tech, longevity...) with real effects on jobs,
##              health and what people talk about.
##  CELEBRITIES famous people who debut, win awards, marry, cause scandals,
##              get arrested, retire and die. Politicians among them lead
##              parties; hunters fight dungeon breaks.
##  NEWS        a yearly newspaper built from all of the above plus the
##              world events and — when visible enough — the player's deeds.
##  MARKS       notable things the player did (from the timeline). People
##              around the player learn about them through gossip, and their
##              opinion changes according to their own values: a devout aunt
##              and a cruel friend react differently to the same arrest.
##
## All of it feeds the dialogue facts, the NPC life simulation and the mod
## pool, so nothing here is decoration.

const TEAM_FMTS := 4
const MAX_NEWS := 60
const MAX_MARKS := 40

var _sim


func _init(sim) -> void:
	_sim = sim
	_sim.bus.log_added.connect(_on_log)


func soc() -> Dictionary:
	var w: Dictionary = _sim.state.data.world
	if not w.has("society"):
		w.society = {"nations": {}, "tech": {"level": 0.0, "eras": []}, "celebs": {}, "news": [], "marks": [], "next_mark": 1}
	return w.society


func init_society() -> void:
	soc()
	for c in _sim.data.table("countries").keys():
		nation(c)
	for i in 12:
		_spawn_celeb(_sim.rng.randi_range(20, 60), "")


func nation(country: String = "") -> Dictionary:
	if country == "":
		country = _sim.player().get("country", "brava") if not _sim.player().is_empty() else "brava"
	var n: Dictionary = soc().nations
	if not n.has(country):
		n[country] = _new_nation(country)
	return n[country]


func city() -> Dictionary:
	return nation().city


func gov() -> Dictionary:
	return nation().gov


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

func _culture(country: String) -> String:
	return _sim.data.get_def("countries", country).get("culture", "pt")


func _city_name(culture: String) -> String:
	var parts: Dictionary = _sim.data.bal("society.city_parts." + culture, _sim.data.bal("society.city_parts.en", {}))
	var pre: String = _sim.rng.pick(parts.get("pre", [""]))
	var core: String = _sim.rng.pick(parts.get("core", ["Ash"]))
	var suf: String = _sim.rng.pick(parts.get("suf", [""]))
	return (pre + core + suf).strip_edges()


func _new_nation(country: String) -> Dictionary:
	var culture := _culture(country)
	var cities: Array = []
	var guard := 0
	while cities.size() < 7 and guard < 40:
		guard += 1
		var nm := _city_name(culture)
		if not cities.has(nm):
			cities.append(nm)
	var teams: Array = []
	for i in 6:
		teams.append({"c": cities[i % cities.size()], "f": _sim.rng.randi_range(0, TEAM_FMTS - 1), "pts": 0, "titles": 0})
	var parties: Array = _sim.data.table("parties").keys()
	parties.sort()
	var ruling: String = _sim.rng.pick(parties)
	var n := {
		"cities": cities,
		"city": _new_city(cities[0], culture),
		"teams": teams,
		"champion": -1,
		"gov": {"party": ruling, "leader": "", "approval": 55.0, "since": int(_sim.state.data.world_year),
			"next_election": int(_sim.state.data.world_year) + _sim.rng.randi_range(1, 4),
			"policies": _party_policies(ruling), "history": []},
	}
	return n


func _new_city(name: String, culture: String) -> Dictionary:
	var c = {"name": name, "prosperity": _sim.rng.randf_range(35, 65), "crime": _sim.rng.randf_range(20, 50),
		"pollution": _sim.rng.randf_range(15, 45), "places": [], "next_place": 1, "culture": culture}
	for t in _sim.data.table("place_types"):
		var def: Dictionary = _sim.data.table("place_types")[t]
		for i in int(def.get("start", 1)):
			_open_place(c, t, "", false)
	return c


func _brand(culture: String) -> String:
	var pool: Array = _sim.data.names.get(culture, {}).get("last", ["Silva"])
	if _sim.rng.randf() < 0.4:
		pool = _sim.data.names.get(culture, {}).get(_sim.rng.pick(["m", "f"]), pool)
	return _sim.rng.pick(pool)


func _open_place(c: Dictionary, type: String, owner: String, announce: bool = true) -> Dictionary:
	var pl := {"id": "pl%d" % int(c.next_place), "type": type, "brand": _brand(c.get("culture", "pt")),
		"q": _sim.rng.randi_range(1, 5), "open": true, "since": int(_sim.state.data.world_year), "owner": owner}
	if owner != "" and _sim.state.has_npc(owner):
		pl.brand = _sim.state.npc(owner).first_name
	c.next_place = int(c.next_place) + 1
	c.places.append(pl)
	if announce:
		news("news.place_open", {"place": place_name(pl), "city": c.name}, "city", "good", ["place_open"])
	return pl


func place_name(pl: Dictionary) -> String:
	return "@place.%s|%s" % [pl.type, pl.brand]


func _party_policies(party: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("parties", party)
	return {"tax": float(def.get("tax", 0.0)), "welfare": float(def.get("welfare", 0.4)),
		"police": float(def.get("police", 0.2)), "rift": def.get("rift", "free")}


func _spawn_celeb(age: int, field: String) -> Dictionary:
	var countries: Array = _sim.data.table("countries").keys()
	countries.sort()
	var country: String = _sim.rng.pick(countries)
	var culture := _culture(country)
	var sex: String = _sim.rng.pick(["m", "f"])
	var fields: Array = _sim.data.bal("society.celeb_fields", ["music", "sport", "film", "influencer", "politics", "hunter", "business"])
	if field == "":
		field = _sim.rng.pick(fields)
	var id := "cel%d" % (soc().celebs.size() + 1)
	while soc().celebs.has(id):
		id += "x"
	var cel = {"id": id, "first": _sim.rng.pick(_sim.data.names.get(culture, {}).get(sex, ["Alex"])),
		"last": _sim.rng.pick(_sim.data.names.get(culture, {}).get("last", ["Silva"])), "sex": sex,
		"field": field, "age": age, "fame": _sim.rng.randf_range(35, 80), "alive": true, "country": country,
		"status": "active", "spouse": "", "scandals": 0, "awards": 0}
	if field == "politics":
		var parties: Array = _sim.data.table("parties").keys()
		parties.sort()
		cel.party = _sim.rng.pick(parties)
	soc().celebs[id] = cel
	return cel


func celeb_name(cel: Dictionary) -> String:
	return "%s %s" % [cel.first, cel.last]


# ---------------------------------------------------------------------------
# Year tick
# ---------------------------------------------------------------------------

func process_year() -> void:
	soc()
	var year = int(_sim.state.data.world_year)
	_world_event_news()
	_tech_year()
	_celebs_year()
	for c in soc().nations:
		_nation_year(c, soc().nations[c], year)
	_sim.gamer.invalidate()


func _world_event_news() -> void:
	var year = int(_sim.state.data.world_year)
	for h in _sim.state.data.world.get("history", []):
		if int(h.year) == year:
			news("news.wevent." + str(h.id), {}, "world", "neutral", ["wevent", "wevent." + str(h.id)])
	var econ = float(_sim.state.data.world.economy)
	if econ < -0.55:
		news("news.economy_bad", {"u": "%d%%" % int(float(_sim.state.data.world.unemployment) * 100)}, "world", "bad", ["economy_bad"])
	elif econ > 0.6:
		news("news.economy_good", {}, "world", "good", ["economy_good"])


func _tech_year() -> void:
	var t: Dictionary = soc().tech
	var gain: float = _sim.rng.randf_range(0.6, 1.4)
	if _sim.state.data.world.get("events", {}).has("tech_revolution"):
		gain += 2.0
	t.level = float(t.level) + gain
	for id in _sorted_eras():
		var def: Dictionary = _sim.data.get_def("tech_eras", id)
		if not t.eras.has(id) and float(t.level) >= float(def.get("at", 999)):
			t.eras.append(id)
			news("news.tech." + id, {}, "world", "neutral", ["tech", "tech." + id])
			_sim.add_log("log.tech_era", {"era": "@tech." + id}, "world")


func _sorted_eras() -> Array:
	var ids: Array = _sim.data.table("tech_eras").keys()
	ids.sort_custom(func(a, b): return float(_sim.data.get_def("tech_eras", a).get("at", 0)) < float(_sim.data.get_def("tech_eras", b).get("at", 0)))
	return ids


func has_era(id: String) -> bool:
	return soc().tech.eras.has(id)


func _celebs_year() -> void:
	var ids: Array = soc().celebs.keys()
	ids.sort()
	var alive := 0
	for id in ids:
		var c: Dictionary = soc().celebs[id]
		if not c.alive:
			continue
		c.age = int(c.age) + 1
		var nm := celeb_name(c)
		var prm := {"celeb": nm, "field": "@celebfield." + str(c.field)}
		if _sim.prob.roll_neutral(_celeb_mortality(int(c.age))):
			c.alive = false
			var dprm := prm.duplicate()
			dprm.age = c.age
			news("news.celeb_died", dprm, "world", "bad", ["celeb_died", "celeb." + str(c.field)])
			continue
		alive += 1
		if c.status == "jailed":
			if _sim.rng.randf() < 0.4:
				c.status = "active"
				news("news.celeb_released", prm, "world", "neutral", ["celeb_released"])
			continue
		if c.status == "retired":
			continue
		c.fame = clampf(float(c.fame) + _sim.rng.randn(0, 6), 0, 100)
		var r: float = _sim.rng.randf()
		if r < 0.05:
			c.scandals = int(c.scandals) + 1
			c.fame = maxf(0, float(c.fame) - 14)
			news("news.celeb_scandal", prm, "world", "bad", ["celeb_scandal", "celeb." + str(c.field)])
		elif r < 0.12 and c.field in ["music", "film", "sport", "business"]:
			c.awards = int(c.awards) + 1
			c.fame = minf(100, float(c.fame) + 10)
			news("news.celeb_award." + str(c.field), prm, "world", "good", ["celeb_award", "celeb." + str(c.field)])
		elif r < 0.14:
			c.status = "jailed"
			c.fame = maxf(0, float(c.fame) - 20)
			news("news.celeb_arrested", prm, "world", "bad", ["celeb_arrested"])
		elif r < 0.17 and c.spouse == "":
			var other := _find_single_celeb(c)
			if not other.is_empty():
				c.spouse = other.id
				other.spouse = c.id
				news("news.celeb_wedding", {"celeb": nm, "celeb2": celeb_name(other)}, "world", "good", ["celeb_wedding"])
		elif r < 0.19 and c.spouse != "":
			var sp: Dictionary = soc().celebs.get(c.spouse, {})
			if not sp.is_empty():
				sp.spouse = ""
				news("news.celeb_divorce", {"celeb": nm, "celeb2": celeb_name(sp)}, "world", "bad", ["celeb_divorce"])
			c.spouse = ""
		elif r < 0.25 and c.field == "hunter" and (float(_sim.state.data.world.rift) > 0.5 or _sim.state.data.world.events.has("dungeon_break")):
			c.fame = minf(100, float(c.fame) + 8)
			news("news.hunter_hero", prm, "world", "good", ["hunter_hero"])
		elif r < 0.33:
			news("news.celeb_work." + str(c.field), prm, "world", "neutral", ["celeb_work", "celeb." + str(c.field)])
		if (int(c.age) > 62 and _sim.rng.randf() < 0.12) or float(c.fame) < 6:
			c.status = "retired"
			news("news.celeb_retired", prm, "world", "neutral", ["celeb_retired"])
	if alive < 12:
		for i in 12 - alive:
			var c = _spawn_celeb(_sim.rng.randi_range(17, 30), "")
			news("news.celeb_debut." + str(c.field), {"celeb": celeb_name(c), "field": "@celebfield." + str(c.field)}, "world", "good", ["celeb_debut"])
	_trim_celebs()


func _celeb_mortality(age: int) -> float:
	return clampf(0.002 + pow(maxf(0, age - 40) / 50.0, 3.0) * 0.25, 0.0, 0.6)


func _find_single_celeb(c: Dictionary) -> Dictionary:
	var ids: Array = soc().celebs.keys()
	ids.sort()
	for id in ids:
		var o: Dictionary = soc().celebs[id]
		if o.id != c.id and o.alive and o.spouse == "" and o.sex != c.sex and absi(int(o.age) - int(c.age)) < 12:
			return o
	return {}


func _trim_celebs() -> void:
	var dead: Array = []
	for id in soc().celebs:
		if not soc().celebs[id].alive:
			dead.append(id)
	dead.sort()
	while dead.size() > 20:
		soc().celebs.erase(dead.pop_front())


func _nation_year(country: String, n: Dictionary, year: int) -> void:
	var home = country == _sim.player().get("country", "")
	_city_year(n.city, home)
	_league_year(country, n, home)
	_gov_year(country, n, year, home)


func _city_year(c: Dictionary, home: bool) -> void:
	var w: Dictionary = _sim.state.data.world
	var econ := float(w.economy)
	var pol: Dictionary = gov().policies if home else {}
	var p: Dictionary = _sim.player()
	var player_biz := 0
	for pl in c.places:
		if pl.open and pl.owner == p.id:
			player_biz += 1
	var donations := float(p.get("year_counters", {}).get("act.donate", 0)) if home else 0.0
	c.prosperity = clampf(float(c.prosperity) + econ * 4.0 + player_biz * 1.5 + donations * 0.8 + _sim.rng.randn(0, 2.5)
		+ float(pol.get("welfare", 0.4)) * 1.0 - 0.4, 3, 97)
	var player_crimes := 0.0
	if home:
		for k in p.get("year_counters", {}):
			if str(k).begins_with("crime."):
				player_crimes += float(p.year_counters[k])
	c.crime = clampf(float(c.crime) + (float(w.unemployment) - 0.08) * 40.0 + (50.0 - float(c.prosperity)) * 0.04
		- float(pol.get("police", 0.2)) * 3.0 + player_crimes * 1.5 + _sim.rng.randn(0, 2.5) + 0.5, 3, 97)
	c.pollution = clampf(float(c.pollution) + float(soc().tech.level) * 0.01 + _sim.rng.randn(0, 1.5) - (2.0 if has_era("green_energy") else 0.0), 2, 95)
	var year = int(_sim.state.data.world_year)
	# Businesses close and open with the economy.
	var open_n := 0
	for pl in c.places:
		if not pl.open:
			continue
		open_n += 1
		if pl.owner == p.id:
			continue
		var def: Dictionary = _sim.data.get_def("place_types", pl.type)
		if def.get("essential", false):
			continue
		var close := 0.035 + maxf(0, -econ) * 0.07 + (3 - int(pl.q)) * 0.01 - float(c.prosperity) * 0.0003
		if _sim.prob.roll_neutral(close):
			pl.open = false
			pl.closed = year
			if home:
				news("news.place_closed", {"place": place_name(pl), "city": c.name, "years": year - int(pl.since)}, "city", "bad", ["place_closed"])
				_owner_life_event(pl, "business_closed")
	var cap = int(_sim.data.bal("society.max_places", 18))
	if open_n < cap and _sim.prob.roll_neutral(0.25 + float(c.prosperity) * 0.006 + econ * 0.1):
		var types: Array = []
		var ws: Array = []
		for t in _sim.data.table("place_types"):
			var def: Dictionary = _sim.data.table("place_types")[t]
			if def.has("era") and not has_era(def.era):
				continue
			types.append(t)
			ws.append(float(def.get("w", 1)))
		var t = _sim.rng.pick_weighted(types, ws)
		if t != null:
			if home:
				_open_place(c, t, "", true)
			else:
				_open_place(c, t, "", false)
	var closed: Array = c.places.filter(func(x): return not x.open and year - int(x.get("closed", year)) > 6)
	for x in closed:
		c.places.erase(x)
	if home:
		if float(c.crime) > 70 and _sim.rng.randf() < 0.5:
			news("news.crime_wave", {"city": c.name}, "city", "bad", ["crime_wave"])
		elif float(c.crime) < 18 and _sim.rng.randf() < 0.25:
			news("news.city_safe", {"city": c.name}, "city", "good", ["city_safe"])
		if float(c.prosperity) > 78 and _sim.rng.randf() < 0.3:
			news("news.city_boom", {"city": c.name}, "city", "good", ["city_boom"])
		if float(c.pollution) > 70 and _sim.rng.randf() < 0.3:
			news("news.smog", {"city": c.name}, "city", "bad", ["smog"])


func _owner_life_event(pl: Dictionary, ev: String) -> void:
	var owner: String = pl.get("owner", "")
	if owner != "" and _sim.state.has_npc(owner):
		_sim.npcs.log_life(_sim.state.npc(owner), ev, {"place": place_name(pl)})


func _league_year(country: String, n: Dictionary, home: bool) -> void:
	var ws: Array = []
	for t in n.teams:
		ws.append(1.0 + float(t.titles) * 0.15)
	var idxs: Array = range(n.teams.size())
	var champ: int = _sim.rng.pick_weighted(idxs, ws)
	n.champion = champ
	n.teams[champ].titles = int(n.teams[champ].titles) + 1
	if home:
		news("news.champion", {"team": team_name(n.teams[champ])}, "sport", "good", ["champion"])


func team_name(t: Dictionary) -> String:
	return "@team.%d|%s" % [int(t.f), t.c]


func _gov_year(country: String, n: Dictionary, year: int, home: bool) -> void:
	var g: Dictionary = n.gov
	var w: Dictionary = _sim.state.data.world
	var player_leader := home and _player_is_leader()
	if player_leader:
		g.leader = "player"
	var target := 50.0 + float(w.economy) * 25.0 - maxf(0, float(w.unemployment) - 0.08) * 150.0
	for ev in w.get("events", {}):
		target -= float(_sim.data.get_def("world_events", ev).get("approval", 0))
	if float(n.city.crime) > 65:
		target -= 6
	g.approval = clampf(lerpf(float(g.approval), target, 0.45) + _sim.rng.randn(0, 4), 3, 97)
	# Policies drift toward the ruling party.
	var goal := _party_policies(g.party)
	for k in ["tax", "welfare", "police"]:
		g.policies[k] = lerpf(float(g.policies[k]), float(goal[k]), 0.5)
	if g.policies.rift != goal.rift and _sim.rng.randf() < 0.5:
		g.policies.rift = goal.rift
		if home:
			news("news.rift_law." + str(goal.rift), {}, "politics", "neutral", ["rift_law", "rift_law." + str(goal.rift)])
	if home and float(g.approval) < 22 and _sim.rng.randf() < 0.5:
		news("news.protests", {"leader": leader_name(g)}, "politics", "bad", ["protests"])
	if year >= int(g.next_election):
		_election(country, n, home, player_leader)
		g.next_election = year + 4


func _player_is_leader() -> bool:
	var st: Dictionary = _sim.player().get("special", {}).get("politics", {})
	return int(st.get("office", -1)) >= 3


func _election(country: String, n: Dictionary, home: bool, player_leader: bool) -> void:
	var g: Dictionary = n.gov
	if player_leader:
		g.history.append({"y": _sim.state.data.world_year, "party": g.party, "leader": "player"})
		return
	var parties: Array = _sim.data.table("parties").keys()
	parties.sort()
	var support := {}
	var p: Dictionary = _sim.player()
	var voted: String = p.get("vote", "") if home else ""
	for party in parties:
		var def: Dictionary = _sim.data.get_def("parties", party)
		var s = 25.0 + _sim.rng.randn(0, 9) + float(def.get("base", 0))
		if party == g.party:
			s += (float(g.approval) - 50.0) * 0.6
		# Hard times push voters toward order or toward change.
		var ideol := float(def.get("ideology", 0))
		s += -float(_sim.state.data.world.economy) * ideol * 0.05
		if float(n.city.crime) > 60:
			s += ideol * 0.06
		if def.has("era") and not has_era(def.era):
			s -= 100
		if party == voted:
			s += 1.0 + float(p.get("fame", 0)) * 0.12
		support[party] = s
	var winner: String = parties[0]
	for party in parties:
		if float(support[party]) > float(support[winner]):
			winner = party
	var changed: bool = winner != g.party
	g.party = winner
	g.leader = _pick_leader(winner, country)
	g.approval = 58.0
	g.since = int(_sim.state.data.world_year)
	g.history.append({"y": _sim.state.data.world_year, "party": winner, "leader": g.leader})
	if home:
		var key := "news.election_change" if changed else "news.election_keep"
		news(key, {"party": "@party." + winner, "leader": leader_name(g)}, "politics", "neutral", ["election", "party." + winner])
		p.erase("vote")
		if voted != "":
			var won := voted == winner
			_sim.add_log("log.vote_result_" + ("won" if won else "lost"), {"party": "@party." + winner}, "info")


func _pick_leader(party: String, country: String) -> String:
	var ids: Array = soc().celebs.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = soc().celebs[id]
		if c.alive and c.field == "politics" and c.get("party", "") == party and c.status == "active":
			return id
	var c = _spawn_celeb(_sim.rng.randi_range(40, 65), "politics")
	c.party = party
	c.country = country
	return c.id


func leader_name(g: Dictionary) -> String:
	if g.get("leader", "") == "player":
		return _sim.player().first_name + " " + _sim.player().last_name
	var c: Dictionary = soc().celebs.get(g.get("leader", ""), {})
	return celeb_name(c) if not c.is_empty() else "—"


# ---------------------------------------------------------------------------
# News
# ---------------------------------------------------------------------------

func news(key: String, params: Dictionary, scope: String, tone: String, tags: Array) -> void:
	var list: Array = soc().news
	list.append({"y": int(_sim.state.data.world_year), "key": key, "params": params, "scope": scope, "tone": tone, "tags": tags})
	while list.size() > MAX_NEWS:
		list.pop_front()


func recent_news(years: int = 1) -> Array:
	var year = int(_sim.state.data.world_year)
	return soc().news.filter(func(n): return year - int(n.y) < years)


# ---------------------------------------------------------------------------
# Marks & gossip — the world reacting to the player
# ---------------------------------------------------------------------------

func _on_log(entry: Dictionary) -> void:
	var def: Dictionary = _sim.data.get_def("marks", entry.get("key", ""))
	if def.is_empty() or _sim.player().is_empty():
		return
	var s := soc()
	var mark = {"id": int(s.next_mark), "type": def.type, "y": int(_sim.state.data.world_year), "vis": float(def.get("vis", 0.3)), "params": entry.get("params", {})}
	s.next_mark = int(s.next_mark) + 1
	s.marks.append(mark)
	while s.marks.size() > MAX_MARKS:
		s.marks.pop_front()
	var p: Dictionary = _sim.player()
	if def.get("news", false) and float(p.get("fame", 0)) >= float(def.get("fame_min", 30)):
		var prm: Dictionary = entry.get("params", {}).duplicate()
		prm.player = p.first_name + " " + p.last_name
		news("news.player." + str(def.type), prm, "personal", def.get("tone", "neutral"), ["player", "player." + str(def.type)])
	if not p.has("life_log"):
		p.life_log = []
	p.life_log.append({"e": def.type, "y": int(_sim.state.data.world_year)})
	while p.life_log.size() > 20:
		p.life_log.pop_front()


## Once a year every person close to the player may hear about recent marks.
## What they think depends on who they are.
func spread_gossip(p: Dictionary) -> void:
	var year = int(_sim.state.data.world_year)
	var fame_boost := 1.0 + float(p.get("fame", 0)) / 40.0
	var ids: Array = p.get("rels", {}).keys()
	ids.sort()
	for id in ids:
		var npc: Dictionary = _sim.state.npc(id)
		if npc.is_empty() or not npc.alive or int(npc.age) < 8:
			continue
		Persona.ensure(npc, _sim)
		var known: Array = npc.get("known_marks", [])
		var role = _sim.relations.role_of(id)
		var closeness := 1.6 if RelationshipSystem.FAMILY_ROLES.has(role) or role in ["best_friend", "partner", "fiance"] else 1.0
		var nosy := 0.25 + (0.25 if npc.persona.interests.has("gossip") else 0.0) + Persona.trait_of(npc, "e") / 400.0
		for m in soc().marks:
			if year - int(m.y) > 3 or known.has(m.type + str(m.id)):
				continue
			var chance := clampf(float(m.vis) * nosy * closeness * fame_boost, 0.0, 0.95)
			if not _sim.prob.roll_neutral(chance):
				continue
			known.append(m.type + str(m.id))
			if not known.has(m.type):
				known.append(m.type)
			_judge(npc, m)
		while known.size() > 30:
			known.pop_front()
		npc.known_marks = known


## Opinion shift = base + persona modifiers declared in data/marks.json.
func _judge(npc: Dictionary, m: Dictionary) -> void:
	var def: Dictionary = {}
	for k in _sim.data.table("marks"):
		if _sim.data.table("marks")[k].type == m.type:
			def = _sim.data.table("marks")[k]
			break
	var facts := {}
	_sim.dialogue.character_facts(npc, "", facts)
	var delta := float(def.get("opinion", 0))
	for mod in def.get("judge", []):
		if mod.size() == 2:
			if DialogueSystem.truthy(facts.get(mod[0], false)):
				delta += float(mod[1])
		else:
			delta += (float(facts.get(mod[0], 50)) - float(mod[2])) * float(mod[1])
	if absf(delta) < 0.5:
		return
	_sim.relations.change_score(npc.id, delta)
	if delta <= -4:
		_sim.relations.add_memory(npc.id, "heard_" + str(m.type), absf(delta) * 2.0)


# ---------------------------------------------------------------------------
# Queries used by other systems
# ---------------------------------------------------------------------------

func policy(key: String) -> float:
	if _sim.player().is_empty():
		return 0.0
	var pol: Dictionary = gov().policies
	match key:
		"tax":
			return float(pol.get("tax", 0.0))
		"police":
			return float(pol.get("police", 0.2)) - 0.2
		"welfare":
			return float(pol.get("welfare", 0.4))
		"rift_ban":
			return 1.0 if pol.get("rift", "") == "ban" else 0.0
		"rift_registry":
			return 1.0 if pol.get("rift", "") == "registry" else 0.0
	return 0.0


## Salary multiplier for a job id from tech eras (automation, AI...).
func job_mult(job_id: String) -> float:
	if job_id == "":
		return 1.0
	var cat: String = _sim.data.get_def("jobs", job_id).get("cat", "")
	var m := 1.0
	for era in soc().tech.eras:
		m *= 1.0 + float(_sim.data.get_def("tech_eras", era).get("job_pay", {}).get(cat, 0.0))
	return m


func mods(_p: Dictionary) -> Dictionary:
	var out := {}
	for era in soc().tech.eras:
		var m: Dictionary = _sim.data.get_def("tech_eras", era).get("mods", {})
		for k in m:
			out[k] = float(out.get(k, 0.0)) + float(m[k])
	if _sim.player().is_empty():
		return out
	var c := city()
	if float(c.crime) > 60:
		out.stress_gain = float(out.get("stress_gain", 0)) + 0.05
	if float(c.pollution) > 65:
		out.disease_resist = float(out.get("disease_resist", 0)) - 0.05
	if float(c.prosperity) > 70:
		out.happiness = float(out.get("happiness", 0)) + 1.0
	if policy("rift_registry") > 0:
		out.gold_find = float(out.get("gold_find", 0)) + 0.05
	return out


func places_of(type: String) -> Array:
	return city().places.filter(func(x): return x.open and x.type == type)


## Facts for dialogue / conditions.
func world_facts(f: Dictionary) -> void:
	if _sim.player().is_empty():
		return
	var c := city()
	f["city.crime"] = float(c.crime)
	f["city.prosperity"] = float(c.prosperity)
	if float(c.crime) > 60:
		f["city.dangerous"] = true
	if float(c.prosperity) > 70:
		f["city.booming"] = true
	elif float(c.prosperity) < 30:
		f["city.decaying"] = true
	if float(c.pollution) > 65:
		f["city.polluted"] = true
	var g := gov()
	f["gov.party"] = str(g.party)
	f["gov.party." + str(g.party)] = true
	f["gov.approval"] = float(g.approval)
	f["gov.ideology"] = float(_sim.data.get_def("parties", g.party).get("ideology", 0))
	if g.get("leader", "") == "player":
		f["gov.player"] = true
	f["gov.rift." + str(g.policies.rift)] = true
	if int(g.next_election) == int(_sim.state.data.world_year):
		f["election_year"] = true
	for era in soc().tech.eras:
		f["tech." + str(era)] = true
	for n in recent_news(1):
		for t in n.tags:
			f["news." + str(t)] = true
	var nat := nation()
	if int(nat.champion) >= 0:
		f["champ"] = int(nat.champion)


## Text parameters for dialogue lines: city, places, celebrities, leader...
func text_params(npc: Dictionary, place_type: String) -> Dictionary:
	var out := {}
	if _sim.player().is_empty():
		return out
	var c := city()
	out.city = c.name
	var cities: Array = nation().cities
	out.other_city = cities[1 + (absi(hash(npc.get("id", ""))) % maxi(1, cities.size() - 1))] if cities.size() > 1 else c.name
	var pool: Array = places_of(place_type) if place_type != "" else c.places.filter(func(x): return x.open)
	if not pool.is_empty():
		out.place = place_name(pool[absi(hash(str(npc.get("id", "")) + place_type)) % pool.size()])
	for t in ["bar", "cafe", "bakery", "gym", "market", "church", "guild", "restaurant", "park", "club"]:
		var ps := places_of(t)
		if not ps.is_empty():
			out["place_" + t] = place_name(ps[absi(hash(str(npc.get("id", "")))) % ps.size()])
		else:
			out["place_" + t] = "@placegeneric." + t
	var closed: Array = c.places.filter(func(x): return not x.open)
	if not closed.is_empty():
		out.closed_place = place_name(closed[-1])
	var g := gov()
	out.leader = leader_name(g)
	out.party = "@party." + str(g.party)
	var nat := nation()
	var pz: Dictionary = npc.get("persona", {})
	if pz.get("interests", []).has("sports") and not pz.has("team"):
		pz.team = str(absi(hash(npc.get("id", ""))) % nat.teams.size())
	var ti := int(pz.get("team", "0"))
	out.team = team_name(nat.teams[ti % nat.teams.size()])
	if int(nat.champion) >= 0:
		out.champion = team_name(nat.teams[int(nat.champion)])
		if pz.has("team") and int(pz.team) == int(nat.champion):
			pz.team_won = int(_sim.state.data.world_year)
	for field in ["music", "sport", "film", "influencer", "hunter", "business"]:
		var best := _top_celeb(field)
		out["celeb_" + field] = celeb_name(best) if not best.is_empty() else "—"
	var hot := _hot_celeb()
	out.celeb = celeb_name(hot) if not hot.is_empty() else out.get("celeb_music", "—")
	return out


func _top_celeb(field: String) -> Dictionary:
	var best: Dictionary = {}
	for id in soc().celebs:
		var c: Dictionary = soc().celebs[id]
		if c.alive and c.field == field and c.status != "retired" and (best.is_empty() or float(c.fame) > float(best.fame)):
			best = c
	return best


## The celebrity most recently in the news.
func _hot_celeb() -> Dictionary:
	var list: Array = soc().news
	for i in range(list.size() - 1, -1, -1):
		var nm: String = str(list[i].params.get("celeb", ""))
		if nm == "":
			continue
		for id in soc().celebs:
			if celeb_name(soc().celebs[id]) == nm:
				return soc().celebs[id]
	return {}


## The player opens a business in the city (from the Business career).
func player_business(open: bool) -> void:
	var c := city()
	if open:
		var pl = _open_place(c, "shop", _sim.player().id, true)
		pl.brand = _sim.player().last_name
	else:
		for pl in c.places:
			if pl.owner == _sim.player().id and pl.open:
				pl.open = false
				pl.closed = int(_sim.state.data.world_year)
