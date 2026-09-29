extends VBoxContainer
## Minimal blackjack against the house: hit or stand, dealer draws to 17.

signal finished(won: bool, bet: float)

var _deck: Array = []
var _player: Array = []
var _dealer: Array = []
var _bet := 500.0
var _info: Label
var _hands: Label
var _buttons: HBoxContainer
var _rng := RandomNumberGenerator.new()


func setup(seed: int, bet: float) -> void:
	_rng.seed = seed
	_bet = bet
	add_theme_constant_override("separation", 12)
	_info = W.label(App.t("mg.bj.bet", {"v": Fmt.money(_bet)}), UiTheme.FONT_S, UiTheme.GOLD)
	add_child(_info)
	_hands = W.label("", UiTheme.FONT_L, UiTheme.TEXT, true)
	add_child(_hands)
	_buttons = W.hbox(10)
	_buttons.add_child(W.tinted_button(App.t("mg.bj.hit"), _hit, UiTheme.PANEL_HI))
	_buttons.add_child(W.tinted_button(App.t("mg.bj.stand"), _stand, UiTheme.SYSTEM))
	add_child(_buttons)
	for s in 4:
		for v in range(1, 14):
			_deck.append(v)
	for i in range(_deck.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = _deck[i]
		_deck[i] = _deck[j]
		_deck[j] = t
	_player = [_deck.pop_back(), _deck.pop_back()]
	_dealer = [_deck.pop_back(), _deck.pop_back()]
	_render(false)


func _value(hand: Array) -> int:
	var total := 0
	var aces := 0
	for c in hand:
		var v: int = mini(int(c), 10)
		if v == 1:
			aces += 1
			v = 11
		total += v
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


func _card(c: int) -> String:
	return {1: "A", 11: "J", 12: "Q", 13: "K"}.get(c, str(c))


func _render(reveal: bool) -> void:
	var dealer_txt := " ".join(_dealer.map(func(c): return "[%s]" % _card(c))) if reveal else "[%s] [?]" % _card(_dealer[0])
	_hands.text = "%s: %s\n%s: %s  (%d)" % [App.t("mg.bj.dealer"), dealer_txt, App.t("mg.bj.you"), " ".join(_player.map(func(c): return "[%s]" % _card(c))), _value(_player)]


func _hit() -> void:
	_player.append(_deck.pop_back())
	_render(false)
	if _value(_player) > 21:
		_end(false)


func _stand() -> void:
	while _value(_dealer) < 17:
		_dealer.append(_deck.pop_back())
	var pv := _value(_player)
	var dv := _value(_dealer)
	_end(dv > 21 or pv > dv)


func _end(won: bool) -> void:
	_render(true)
	for b in _buttons.get_children():
		b.disabled = true
	_info.text = App.t("mg.bj.win" if won else "mg.bj.lose")
	_info.add_theme_color_override("font_color", UiTheme.GOOD if won else UiTheme.BAD)
	await get_tree().create_timer(1.0).timeout
	finished.emit(won, _bet)
