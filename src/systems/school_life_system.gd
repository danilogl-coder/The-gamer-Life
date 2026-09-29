class_name SchoolLifeSystem
extends RefCounted
## Social life at school: popularity, cliques (with entry requirements) and
## extracurricular clubs with ranks (member → starter → captain). Clubs raise
## stats, popularity and scholarship odds; cliques give modifiers.

const RANKS := 3   # 0 member, 1 starter, 2 captain

var _sim


func _init(sim) -> void:
	_sim = sim


func school(p: Dictionary) -> Dictionary:
	if not p.has("school"):
		p.school = {"popularity": 30.0, "clique": "", "clubs": {}}
	return p.school


func popularity(p: Dictionary) -> float:
	return float(school(p).popularity)


func change_popularity(p: Dictionary, amount: float) -> void:
	school(p).popularity = clampf(popularity(p) + amount, 0.0, 100.0)


# ---------------------------------------------------------------- cliques

func clique_block_reason(p: Dictionary, id: String) -> String:
	var def: Dictionary = _sim.data.get_def("cliques", id)
	if def.is_empty():
		return "ui.invalid"
	if not _sim.education.in_school(p):
		return "school.block.not_student"
	if int(p.age) < int(def.min_age) or int(p.age) > int(def.max_age):
		return "job.block.age"
	if school(p).clique == id:
		return "sc.block.active"
	if popularity(p) < float(def.min_popularity):
		return "school.block.popularity"
	if def.has("req") and not _sim.cond.check(def.req, {}):
		return "school.block.req"
	return ""


func join_clique(p: Dictionary, id: String) -> Dictionary:
	var reason := clique_block_reason(p, id)
	if reason != "":
		return {"ok": false, "reason": reason}
	var accept := {"base": 0.55, "mods": [{"path": "stat.cha", "per": 0.01, "offset": 10.0, "max": 0.3},
		{"path": "player.attrs.looks", "per": 0.004, "offset": 50.0}]}
	if not _sim.prob.roll_spec(accept):
		change_popularity(p, -3.0)
		return {"ok": false, "reason": "school.clique_rejected"}
	school(p).clique = id
	_sim.gamer.invalidate()
	_sim.add_log("log.clique", {"clique": "@clique." + id}, "info")
	_sim.activities.bump_counter("school.clique." + id)
	return {"ok": true, "key": "school.clique_joined", "params": {"clique": "@clique." + id}}


func leave_clique(p: Dictionary) -> void:
	school(p).clique = ""
	_sim.gamer.invalidate()


# ---------------------------------------------------------------- clubs

func join_club(p: Dictionary, id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("clubs", id)
	if def.is_empty() or not _sim.education.in_school(p) or int(p.age) < int(def.min_age):
		return {"ok": false, "reason": "school.block.not_student"}
	if school(p).clubs.has(id):
		return {"ok": false, "reason": "sc.block.active"}
	if school(p).clubs.size() >= 2:
		return {"ok": false, "reason": "school.block.max_clubs"}
	school(p).clubs[id] = {"rank": 0, "xp": 0.0}
	_sim.add_log("log.club_join", {"club": "@club." + id}, "info")
	return {"ok": true, "key": "school.club_joined", "params": {"club": "@club." + id}}


func practice(p: Dictionary, id: String) -> Dictionary:
	var def: Dictionary = _sim.data.get_def("clubs", id)
	var entry: Dictionary = school(p).clubs.get(id, {})
	if entry.is_empty():
		return {"ok": false, "reason": "ui.invalid"}
	if not _sim.activities.spend_time(1):
		return {"ok": false, "reason": "ui.no_time"}
	var gain: float = 10.0 + _sim.gamer.effective_stat(p, def.stat) * 0.8 + _sim.gamer.effective_stat(p, def.second) * 0.3
	gain += (float(p.hidden.get("athleticism", 50)) - 50.0) * 0.2 if def.stat in ["str", "vit", "dex"] else 0.0
	entry.xp = float(entry.xp) + gain
	_sim.gamer.add_stat_xp(p, def.stat, 14.0)
	_sim.gamer.add_stat_xp(p, def.second, 7.0)
	_sim.gamer.add_exp(p, 12.0)
	_sim.activities.bump_counter(def.get("counter", "act.club"))
	_sim.activities.bump_counter("school.practice")
	change_popularity(p, float(def.popularity) * 0.4)
	return {"ok": true, "key": "school.practiced", "params": {"club": "@club." + id}}


func quit_club(p: Dictionary, id: String) -> void:
	school(p).clubs.erase(id)


func has_captaincy(p: Dictionary) -> bool:
	for id in school(p).get("clubs", {}):
		if int(school(p).clubs[id].rank) >= RANKS - 1:
			return true
	return false


# ---------------------------------------------------------------- year tick

func process_year(p: Dictionary) -> void:
	var sch := school(p)
	if not _sim.education.in_school(p):
		sch.clubs = {}
		if sch.clique != "" and int(p.age) > 17 and sch.clique != "fraternity":
			sch.clique = ""
		return
	for id in sch.clubs.keys():
		var entry: Dictionary = sch.clubs[id]
		var def: Dictionary = _sim.data.get_def("clubs", id)
		var need := 60.0 * (int(entry.rank) + 1)
		if int(entry.rank) < RANKS - 1 and float(entry.xp) >= need:
			entry.xp = float(entry.xp) - need
			entry.rank = int(entry.rank) + 1
			change_popularity(p, 6.0 + float(def.popularity))
			_sim.add_log("log.club_rank", {"club": "@club." + id, "rank": "@club_rank.%d" % int(entry.rank)}, "major" if int(entry.rank) == RANKS - 1 else "info")
			_sim.activities.bump_counter("school.promoted")
			if int(entry.rank) == RANKS - 1:
				_sim.activities.bump_counter("school.captain")
		entry.xp = float(entry.xp) * 0.7
	var clique_def: Dictionary = _sim.data.get_def("cliques", sch.clique)
	var drift: float = (float(p.attrs.looks) - 50.0) * 0.06 + (_sim.gamer.effective_stat(p, "cha") - 10.0) * 0.1
	drift += float(clique_def.get("popularity", 0)) + (40.0 - popularity(p)) * 0.05
	change_popularity(p, drift)
	if popularity(p) < 12.0 and _sim.prob.roll_neutral(0.3):
		_sim.events.queue_event("school_bully")


## Modifiers from the current clique (read by GamerSystem).
func mods(p: Dictionary) -> Dictionary:
	return _sim.data.get_def("cliques", school(p).get("clique", "")).get("mods", {})
