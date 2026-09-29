class_name TestBase
extends RefCounted

var data: DataRegistry
var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func new_sim(seed: int = 42, options: Dictionary = {}) -> LifeSimulation:
	var sim := LifeSimulation.new(data)
	sim.new_life(seed, options)
	return sim


## Resolves pending events with the first visible choice (deterministic bot).
func drain_events(sim: LifeSimulation) -> void:
	var guard := 0
	while sim.has_pending_events() and guard < 50:
		guard += 1
		var choices: Array = sim.events.visible_choices(sim.current_event())
		sim.choose(choices[0].id)


func live_years(sim: LifeSimulation, years: int) -> void:
	for i in years:
		if sim.is_dead():
			return
		drain_events(sim)
		sim.advance_year()
	drain_events(sim)
