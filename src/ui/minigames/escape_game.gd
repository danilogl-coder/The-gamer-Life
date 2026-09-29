extends VBoxContainer
## Prison escape mini-game: reach the exit on a walled grid. For every step
## you take, the guard takes two, always trying to close the horizontal gap
## first. Outsmart him with the walls.

signal finished(success: bool)

const W_CELLS := 9
const H_CELLS := 9
const CELL := 64

var _walls := {}
var _player := Vector2i.ZERO
var _guard := Vector2i.ZERO
var _exit := Vector2i.ZERO
var _board: Control
var _status: Label
var _done := false
var _rng := RandomNumberGenerator.new()


func setup(seed: int) -> void:
	_rng.seed = seed
	add_theme_constant_override("separation", 10)
	_status = W.label(App.t("mg.escape.hint"), UiTheme.FONT_S, UiTheme.TEXT, true)
	add_child(_status)
	_board = Control.new()
	_board.custom_minimum_size = Vector2(W_CELLS * CELL, H_CELLS * CELL)
	_board.draw.connect(_draw_board)
	var center := CenterContainer.new()
	center.add_child(_board)
	add_child(center)
	var pad := W.grid(3, 6)
	for d in [["", Vector2i.ZERO], ["▲", Vector2i.UP], ["", Vector2i.ZERO], ["◀", Vector2i.LEFT], ["⏸", Vector2i.ZERO], ["▶", Vector2i.RIGHT], ["", Vector2i.ZERO], ["▼", Vector2i.DOWN], ["", Vector2i.ZERO]]:
		if d[0] == "":
			pad.add_child(Control.new())
		else:
			pad.add_child(W.button(d[0], _move.bind(d[1]), 88, UiTheme.FONT_L))
	add_child(pad)
	_generate()


func _generate() -> void:
	for attempt in 50:
		_walls.clear()
		for i in 14:
			_walls[Vector2i(_rng.randi_range(1, W_CELLS - 2), _rng.randi_range(1, H_CELLS - 2))] = true
		_player = Vector2i(_rng.randi_range(2, W_CELLS - 3), H_CELLS - 2)
		_guard = Vector2i(_rng.randi_range(1, W_CELLS - 2), 1)
		_exit = Vector2i(_rng.randi_range(1, W_CELLS - 2), 0)
		_walls.erase(_player)
		_walls.erase(_guard)
		if _reachable(_player, _exit) and _player.distance_to(_guard) > 4:
			break
	_board.queue_redraw()


func _blocked(c: Vector2i) -> bool:
	if c == _exit:
		return false
	return c.x <= 0 or c.y <= 0 or c.x >= W_CELLS - 1 or c.y >= H_CELLS - 1 or _walls.has(c)


func _reachable(a: Vector2i, b: Vector2i) -> bool:
	var seen := {a: true}
	var queue := [a]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == b:
			return true
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if not seen.has(n) and not _blocked(n):
				seen[n] = true
				queue.append(n)
	return false


func _move(dir: Vector2i) -> void:
	if _done:
		return
	var n := _player + dir
	if dir != Vector2i.ZERO and _blocked(n):
		return
	_player = n
	if _player == _exit:
		_finish(true)
		return
	for i in 2:
		_guard_step()
		if _guard == _player:
			_finish(false)
			return
	_board.queue_redraw()


func _guard_step() -> void:
	var dx := signi(_player.x - _guard.x)
	var dy := signi(_player.y - _guard.y)
	if dx != 0 and not _blocked(_guard + Vector2i(dx, 0)):
		_guard += Vector2i(dx, 0)
	elif dy != 0 and not _blocked(_guard + Vector2i(0, dy)):
		_guard += Vector2i(0, dy)


func _finish(success: bool) -> void:
	_done = true
	_status.text = App.t("mg.escape.win" if success else "mg.escape.lose")
	_status.add_theme_color_override("font_color", UiTheme.GOOD if success else UiTheme.BAD)
	_board.queue_redraw()
	await get_tree().create_timer(0.8).timeout
	finished.emit(success)


func _draw_board() -> void:
	var floor_ramp := PixelPalette.ramp(Color("7a7a96"), 3, 0.12)
	for y in H_CELLS:
		for x in W_CELLS:
			var c := Vector2i(x, y)
			var r := Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL))
			if c == _exit:
				_board.draw_rect(r, Color("3fbf5a"))
			elif _blocked(c):
				_board.draw_rect(r, Color("14141c"))
				_board.draw_rect(Rect2(r.position, Vector2(CELL, 8)), Color("5a5a6e"))
				_board.draw_rect(Rect2(r.position + Vector2(0, CELL - 4), Vector2(CELL, 4)), Color("07070b"))
			else:
				_board.draw_rect(r, floor_ramp[1 + (x + y) % 2])
	_board.draw_texture_rect(Portrait.texture_for(App.sim.player()), Rect2(Vector2(_player) * CELL, Vector2(CELL, CELL)), false)
	var guard_c := Vector2(_guard) * CELL + Vector2(CELL, CELL) / 2.0
	_board.draw_circle(guard_c, CELL * 0.38, Color("2a4a9a"))
	_board.draw_circle(guard_c + Vector2(0, -8), CELL * 0.18, Color("e9b48a"))
	_board.draw_rect(Rect2(guard_c + Vector2(-14, -26), Vector2(28, 8)), Color("10183a"))
