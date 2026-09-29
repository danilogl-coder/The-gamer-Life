class_name EducationSystem
extends RefCounted
## School → university → postgrad. Grades come from INT (the Gamer stat),
## discipline, study effort this year, stress, absences and modifiers
## (e.g. the "Speed Reading" skill). Stages, prerequisites and costs are data.

var _sim


func _init(sim) -> void:
	_sim = sim


func stage_def(p: Dictionary) -> Dictionary:
	return _sim.data.get_def("education", p.education.stage)


func in_school(p: Dictionary) -> bool:
	return p.education.stage != ""


func has_completed(p: Dictionary, id: String) -> bool:
	if id == "any_university":
		for c in p.education.completed:
			if _sim.data.get_def("education", c).get("type", "") == "university":
				return true
		return false
	return p.education.completed.has(id)


## Can the player enroll in `id` right now? Returns "" or a reason key.
func enroll_block_reason(p: Dictionary, id: String) -> String:
	var def: Dictionary = _sim.data.get_def("education", id)
	if def.is_empty() or def.get("auto", false):
		return "ui.invalid"
	if in_school(p):
		return "edu.block.already"
	if has_completed(p, id):
		return "edu.block.done"
	if int(p.age) < int(def.get("min_age", 17)):
		return "edu.block.age"
	for req in def.get("requires", []):
		if not has_completed(p, req):
			return "edu.block.requires"
	if float(p.education.grades) < float(def.get("min_grades", 0)):
		return "edu.block.grades"
	for stat in def.get("stat_req", {}):
		if _sim.gamer.effective_stat(p, stat) < float(def.stat_req[stat]):
			return "edu.block.stat"
	if not _sim.cond.check_all(def.get("conditions", []), {}):
		return "edu.block.locked"
	return ""


func enroll(p: Dictionary, id: String) -> Dictionary:
	var reason := enroll_block_reason(p, id)
	if reason != "":
		return {"ok": false, "reason": reason}
	var def: Dictionary = _sim.data.get_def("education", id)
	# Entrance exam: INT + grades + luck.
	var spec := {"base": float(def.get("admission", 0.8)), "mods": [
		{"path": "stat.int", "per": 0.004, "offset": 15.0, "max": 0.3},
		{"path": "player.education.grades", "per": 0.004, "offset": 60.0}]}
	if not _sim.prob.roll_spec(spec):
		_sim.add_log("log.edu_rejected", {"school": "@edu." + id}, "warning")
		return {"ok": false, "reason": "edu.rejected"}
	_start_stage(p, id)
	if float(p.education.grades) >= float(_sim.data.bal("education.scholarship_grades", 88)):
		p.education.scholarship = true
		_sim.add_log("log.scholarship", {"school": "@edu." + id}, "major")
	return {"ok": true, "key": "edu.enrolled", "params": {"school": "@edu." + id}}


func drop_out(p: Dictionary) -> void:
	if not in_school(p):
		return
	var def := stage_def(p)
	if def.get("auto", false) and int(p.age) < int(def.get("drop_age", 16)):
		return
	_sim.add_log("log.dropout", {"school": "@edu." + p.education.stage}, "major")
	_sim.state.set_flag("dropout_" + p.education.stage)
	_sim.relations.change_parents(-12)
	p.education.stage = ""
	p.education.years = 0


func _start_stage(p: Dictionary, id: String) -> void:
	p.education.stage = id
	p.education.years = 0
	p.education.absences = 0
	p.education.scholarship = false
	_sim.add_log("log.edu_start", {"school": "@edu." + id}, "info")
	_sim.npcs.spawn_classmates(p)


# ---------------------------------------------------------------------------
# Year tick
# ---------------------------------------------------------------------------

func process_year(p: Dictionary) -> void:
	if _sim.crime.in_prison(p):
		return
	if not in_school(p):
		return
	var def := stage_def(p)
	_update_grades(p)
	_charge_tuition(p, def)
	p.education.years = int(p.education.years) + 1
	if int(p.education.years) >= int(def.get("years", 1)):
		_finish_stage(p, def)
	p.education.absences = 0


func _update_grades(p: Dictionary) -> void:
	var int_v: float = _sim.gamer.effective_stat(p, "int")
	var yc: Dictionary = p.year_counters
	var target := 34.0 + minf(int_v * 1.6, 60.0) + float(p.attrs.discipline) * 0.15
	target += float(yc.get("study", 0)) * float(_sim.data.bal("education.study_bonus", 6))
	target += _sim.gamer.mod("study_gain") * 30.0
	target += (float(p.hidden.academic) - 50.0) * 0.15
	target -= maxf(0.0, float(p.attrs.stress) - 50.0) * 0.3
	target -= float(p.education.absences) * float(_sim.data.bal("education.absence_penalty", 5))
	target -= 10.0 if float(p.attrs.health) < 30.0 else 0.0
	var g := float(p.education.grades)
	g = lerpf(g, clampf(target, 0.0, 100.0), 0.45) + _sim.rng.randn(0, 3)
	p.education.grades = clampf(g, 0.0, 100.0)


func _charge_tuition(p: Dictionary, def: Dictionary) -> void:
	var tuition := float(def.get("tuition", 0)) * float(_sim.finance.country(p).get("cost_of_living", 1.0))
	if tuition <= 0.0 or p.education.get("scholarship", false):
		return
	# Parents may pay if they can and like you.
	var parent_id: String = _sim.relations.first_with_role(p, "mother")
	if parent_id == "":
		parent_id = _sim.relations.first_with_role(p, "father")
	if parent_id != "":
		var parent: Dictionary = _sim.state.npc(parent_id)
		if float(parent.finance.cash) >= tuition and _sim.relations.score(parent_id) >= 55.0:
			parent.finance.cash = float(parent.finance.cash) - tuition
			return
	if float(p.finance.cash) >= tuition:
		_sim.finance.add_cash(p, -tuition)
	else:
		_sim.finance.take_loan(p, tuition, "student", 10)


func _finish_stage(p: Dictionary, def: Dictionary) -> void:
	var pass_grade := float(_sim.data.bal("education.pass_grade", 45))
	if float(p.education.grades) < pass_grade and def.get("can_fail", true):
		p.education.years = int(p.education.years) - 1
		_sim.add_log("log.edu_failed_year", {"school": "@edu." + def.id}, "warning")
		_sim.relations.change_parents(-6)
		_sim.activities.bump_counter("edu.failed_year")
		return
	p.education.completed.append(def.id)
	_sim.add_log("log.edu_graduated", {"school": "@edu." + def.id}, "major")
	_sim.activities.bump_counter("edu.graduated")
	_sim.gamer.add_exp(p, float(def.get("exp", 60)))
	_sim.effects.run_all(def.get("on_complete", []), {})
	p.education.stage = ""
	p.education.years = 0
	p.education.major = def.id if def.get("type", "") == "university" else p.education.major
	if def.has("next"):
		_start_stage(p, def.next)


func auto_enroll(p: Dictionary) -> void:
	if in_school(p):
		return
	for id in _sim.data.table("education"):
		var def: Dictionary = _sim.data.table("education")[id]
		if def.get("auto", false) and int(def.get("start_age", -1)) == int(p.age) and not has_completed(p, id):
			_start_stage(p, id)
			return


## Coherent education for generated NPCs, based on age and wealth.
func assign_npc_education(npc: Dictionary) -> void:
	var age := int(npc.age)
	var done: Array = []
	for pair in [["preschool", 6], ["primary", 11], ["middle", 15], ["high", 18]]:
		if age >= pair[1]:
			done.append(pair[0])
	var uni_chance := {"poor": 0.12, "working": 0.25, "middle": 0.45, "upper": 0.7, "elite": 0.85}
	if age >= 22 and _sim.prob.roll_neutral(float(uni_chance.get(npc.wealth, 0.4))):
		var majors: Array = []
		for id in _sim.data.table("education"):
			if _sim.data.table("education")[id].get("type", "") == "university":
				majors.append(id)
		majors.sort()
		var major: String = _sim.rng.pick(majors)
		done.append(major)
		npc.education.major = major
	npc.education.completed = done
	if age >= 3 and age < 18:
		for pair in [["preschool", 3, 6], ["primary", 6, 11], ["middle", 11, 15], ["high", 15, 18]]:
			if age >= pair[1] and age < pair[2]:
				npc.education.stage = pair[0]
				npc.education.years = age - pair[1]
