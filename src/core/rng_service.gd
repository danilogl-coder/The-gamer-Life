class_name RngService
extends RefCounted
## Deterministic RNG for a single life. Seed + state are persisted in the save,
## so a loaded game continues exactly the same random sequence.

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0


func _init(p_seed: int = 0) -> void:
	reseed(p_seed)


func reseed(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed


func get_state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value


func randf() -> float:
	return _rng.randf()


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randn(mean: float = 0.0, deviation: float = 1.0) -> float:
	return _rng.randfn(mean, deviation)


func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


## Picks an element using a parallel array of weights (all >= 0).
func pick_weighted(items: Array, weights: Array):
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return null
	var roll := _rng.randf() * total
	for i in items.size():
		roll -= maxf(0.0, float(weights[i]))
		if roll <= 0.0:
			return items[i]
	return items[items.size() - 1]


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
