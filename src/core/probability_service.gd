class_name ProbabilityService
extends RefCounted
## Every meaningful roll goes through here instead of scattered randf() calls.
## A chance spec is data:
##   {"base": 0.4, "mods": [{"path": "stat.dex", "per": 0.004, "max": 0.3}],
##    "min": 0.02, "max": 0.97, "luck": true}
## Luck (LUK stat) pulls favourable rolls towards success — the Gamer's
## luck is never absolute, it only bends the curve.

var _sim


func _init(sim) -> void:
	_sim = sim


func compute(spec: Dictionary, ctx: Dictionary = {}) -> float:
	var p: float = float(spec.get("base", 0.5))
	for m in spec.get("mods", []):
		var value = _sim.resolve(m.path, ctx)
		if value == null:
			continue
		var v := float(value)
		if m.has("offset"):
			v -= float(m.offset)
		var contrib := v * float(m.get("per", 0.01))
		if m.has("max"):
			contrib = minf(contrib, float(m.max))
		if m.has("min"):
			contrib = maxf(contrib, float(m.min))
		p += contrib
	if spec.get("luck", true):
		p = apply_luck(p)
	return clampf(p, float(spec.get("min", 0.01)), float(spec.get("max", 0.99)))


## Luck bonus fraction of the remaining failure space.
func luck_bonus() -> float:
	var luk: float = _sim.gamer.effective_stat(_sim.player(), "luk")
	var per: float = _sim.data.bal("probability.luck_per_point", 0.002)
	var cap: float = _sim.data.bal("probability.luck_cap", 0.35)
	# Karma quietly bends fate too: good deeds come back around.
	var karma: float = (float(_sim.player().get("hidden", {}).get("karma", 50.0)) - 50.0) * float(_sim.data.bal("probability.karma_per_point", 0.0015))
	return clampf((luk - 10.0) * per + karma, -0.15, cap)


func apply_luck(p: float) -> float:
	var b := luck_bonus()
	if b >= 0.0:
		return p + (1.0 - p) * b
	return p * (1.0 + b)


func roll(p: float) -> bool:
	return _sim.rng.randf() < p


func roll_spec(spec: Dictionary, ctx: Dictionary = {}) -> bool:
	return roll(compute(spec, ctx))


## Raw roll without luck, for things that must stay neutral (world, NPCs).
func roll_neutral(p: float) -> bool:
	return _sim.rng.randf() < clampf(p, 0.0, 1.0)
