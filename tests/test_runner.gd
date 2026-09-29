extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/test_runner.gd
## Exits with code 1 if any test fails.

const SUITES := [
	preload("res://tests/test_core.gd"),
	preload("res://tests/test_life.gd"),
	preload("res://tests/test_features.gd"),
]

var failures := 0
var passed := 0


func _initialize() -> void:
	var data := DataRegistry.new().load_all()
	for suite_script in SUITES:
		var suite = suite_script.new()
		suite.data = data
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			suite.errors = []
			suite.call(name)
			if suite.errors.is_empty():
				passed += 1
			else:
				failures += 1
				for e in suite.errors:
					printerr("FAIL %s: %s" % [name, e])
	print("Tests passed: %d, failed: %d" % [passed, failures])
	quit(1 if failures > 0 else 0)
