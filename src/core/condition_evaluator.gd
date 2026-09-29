class_name ConditionEvaluator
extends RefCounted
## Evaluates data-driven conditions. Grammar:
##   {"path": "player.age", "op": ">=", "value": 18}
##   {"path": "stat.int", "op": ">", "value": {"path": "actor.gamer.level"}}
##   {"all": [...]}, {"any": [...]}, {"not": {...}}
## Paths are resolved by LifeSimulation.resolve(), which understands derived
## prefixes (stat., skill., mod., rel., counter., flag.) as well as raw state.

var _sim  # LifeSimulation (untyped to avoid a cyclic class reference)


func _init(sim) -> void:
	_sim = sim


func check_all(conditions, ctx: Dictionary) -> bool:
	if conditions == null:
		return true
	if typeof(conditions) == TYPE_DICTIONARY:
		return check(conditions, ctx)
	for c in conditions:
		if not check(c, ctx):
			return false
	return true


func check(cond: Dictionary, ctx: Dictionary) -> bool:
	if cond.has("all"):
		return check_all(cond.all, ctx)
	if cond.has("any"):
		for c in cond.any:
			if check(c, ctx):
				return true
		return false
	if cond.has("not"):
		return not check(cond.not, ctx)
	if not cond.has("path"):
		push_warning("Condition without path: %s" % cond)
		return false
	var left = _sim.resolve(cond.path, ctx)
	var right = cond.get("value", true)
	if typeof(right) == TYPE_DICTIONARY and right.has("path"):
		right = _sim.resolve(right.path, ctx)
	return compare(left, cond.get("op", "=="), right)


static func compare(left, op: String, right) -> bool:
	match op:
		"==":
			return _loose_eq(left, right)
		"!=":
			return not _loose_eq(left, right)
		">", ">=", "<", "<=":
			if not _is_num(left) or not _is_num(right):
				return false
			var a := float(left)
			var b := float(right)
			match op:
				">": return a > b
				">=": return a >= b
				"<": return a < b
				_: return a <= b
		"in":
			return typeof(right) == TYPE_ARRAY and right.has(left)
		"not_in":
			return typeof(right) != TYPE_ARRAY or not right.has(left)
		"has":
			return _container_has(left, right)
		"not_has":
			return not _container_has(left, right)
		"exists":
			return (left != null) == bool(right)
	push_warning("Unknown condition op: " + op)
	return false


static func _container_has(container, value) -> bool:
	match typeof(container):
		TYPE_ARRAY:
			return container.has(value)
		TYPE_DICTIONARY:
			return container.has(value)
	return false


static func _is_num(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]


static func _loose_eq(a, b) -> bool:
	if a == null:
		return b == null or (typeof(b) == TYPE_BOOL and b == false)
	if b == null:
		return typeof(a) == TYPE_BOOL and a == false
	if _is_num(a) and _is_num(b):
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	return a == b
