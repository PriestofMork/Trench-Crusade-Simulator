class_name DiceTray
extends PanelContainer
## The dice tray: shows one roll from core's events, in order: what is being
## rolled and by whom, the modifier breakdown (cancelled plus and minus dice
## struck through), the pre-roll prompts, then the dice, which tumble briefly
## and land on the values core already rolled, the kept ones highlighted,
## then the total and the outcome. It never rolls or decides anything.
## A click or a key while the dice tumble skips to the result.

## One count per option of the choice.
signal choice_answered(amounts: Array[int])

const TUMBLE_SECONDS: float = 0.9
const TUMBLE_STEP_SECONDS: float = 0.07
const LAND_SECONDS: float = 0.3
const OUTCOME_SECONDS: float = 0.35

var _title: RichTextLabel
var _breakdown: RichTextLabel
var _prompt_box: VBoxContainer
var _prompt_label: RichTextLabel
var _prompt_buttons: HBoxContainer
var _dice_row: HFlowContainer
var _total: RichTextLabel
var _outcome: RichTextLabel
var _hint: Label

var _roll: ActiveRoll = null
var _choice_lines: PackedStringArray = PackedStringArray()
var _result: RollResult = null
var _faces: Array[DieFace] = []
var _elapsed: float = 0.0
var _animating: bool = false
var _on_done: Callable = Callable()
var _ended_activation: bool = false
## The counts picked so far in a prompt with several options.
var _picked: Array[int] = []
## What an injury roll did, in words (shown under the outcome).
var _effect: String = ""


func _init() -> void:
	name = "DiceTray"
	add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GOLD_COLOUR.darkened(0.4)))
	custom_minimum_size = Vector2(400, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = UiStyle.rich(19)
	box.add_child(_title)
	_breakdown = UiStyle.rich(15)
	box.add_child(_breakdown)
	_prompt_box = VBoxContainer.new()
	_prompt_box.name = "Prompt"
	_prompt_label = UiStyle.rich(16)
	_prompt_box.add_child(_prompt_label)
	_prompt_buttons = HBoxContainer.new()
	_prompt_buttons.name = "PromptButtons"
	_prompt_box.add_child(_prompt_buttons)
	box.add_child(_prompt_box)
	_dice_row = HFlowContainer.new()
	_dice_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_dice_row.add_theme_constant_override("h_separation", 10)
	_dice_row.add_theme_constant_override("v_separation", 8)
	box.add_child(_dice_row)
	_total = UiStyle.rich(18)
	box.add_child(_total)
	_outcome = UiStyle.rich(24)
	box.add_child(_outcome)
	_hint = UiStyle.label("Click or press a key to skip", 13, UiStyle.DIM_COLOUR)
	_hint.visible = false
	box.add_child(_hint)
	visible = false


## ROLL_REQUESTED: a new roll replaces whatever the tray showed.
func begin(roll: ActiveRoll) -> void:
	_finish_animation(false)
	_roll = roll
	_result = null
	_choice_lines.clear()
	_ended_activation = false
	_effect = ""
	var request: RollRequest = roll.request
	var who: String = "both players" if request.roller < 0 else UiStyle.player_bb(request.roller)
	var model_text: String = "" if request.actor_id < 0 else ", model %d" % request.actor_id
	_title.text = "[b]%s[/b]  —  %s%s" % [request.label, who, model_text]
	_clear_prompt()
	_clear_dice()
	_total.text = ""
	_outcome.text = ""
	_hint.visible = false
	_show_breakdown(roll.modifiers)
	visible = true


## ROLL_CHOICE_MADE: the answer goes into the breakdown.
func add_choice(event: GameEvent) -> void:
	_clear_prompt()
	var amount: int = event.data.get("amount", 0)
	if amount == 0:
		_choice_lines.append("[color=#%s]%s spends none[/color]" % [UiStyle.DIM_COLOUR.to_html(false), UiStyle.player_name(event.player)])
	if _roll != null:
		_show_breakdown(_roll.modifiers)


## DECISION_NEEDED for a pre-roll choice: buttons 0..maximum. With several
## options (blood and infection markers), one row of counts per option and a
## button to spend them.
func ask_choice(decision: PendingDecision) -> void:
	_clear_prompt()
	var choice: RollChoice = decision.choice
	_prompt_label.text = "%s: %s?" % [UiStyle.player_bb(decision.player), choice.label]
	if choice.options.size() <= 1:
		for amount: int in range(0, choice.maximum + 1):
			var text: String = "None" if amount == 0 else str(amount)
			var button: Button = UiStyle.button(text, "Spend%d" % amount)
			button.custom_minimum_size = Vector2(52, 34)
			button.pressed.connect(func() -> void: choice_answered.emit([amount] as Array[int]))
			_prompt_buttons.add_child(button)
	else:
		_picked.clear()
		_picked.resize(choice.options.size())
		var rows: VBoxContainer = VBoxContainer.new()
		rows.name = "Rows"
		_prompt_buttons.add_child(rows)
		for i: int in choice.options.size():
			var option: RollChoice.Option = choice.options[i]
			var row: HBoxContainer = HBoxContainer.new()
			row.add_child(UiStyle.label("%s:" % option.label, 15))
			var group: ButtonGroup = ButtonGroup.new()
			for amount: int in range(0, option.maximum + 1):
				var button: Button = UiStyle.button(str(amount), "Pick%d_%d" % [i, amount])
				button.custom_minimum_size = Vector2(40, 32)
				button.toggle_mode = true
				button.button_group = group
				button.button_pressed = amount == 0
				var index: int = i
				button.pressed.connect(func() -> void: _picked[index] = amount)
				row.add_child(button)
			rows.add_child(row)
		var spend: Button = UiStyle.button("Spend these", "SpendPicked")
		spend.pressed.connect(func() -> void: choice_answered.emit(_picked.duplicate()))
		rows.add_child(spend)
	_prompt_box.visible = true
	visible = true


func is_asking() -> bool:
	return _prompt_box.visible


## Presses the prompt's button for `amount` (as a click would).
func press_choice(amount: int) -> bool:
	var button: Button = _prompt_buttons.get_node_or_null("Spend%d" % amount)
	if button == null:
		return false
	button.pressed.emit()
	return true


## In a prompt with several options: picks `amounts` and presses Spend.
func press_choices(amounts: Array[int]) -> bool:
	var rows: Node = _prompt_buttons.get_node_or_null("Rows")
	if rows == null:
		return false
	for i: int in amounts.size():
		var button: Button = rows.find_child("Pick%d_%d" % [i, amounts[i]], true, false)
		if button == null:
			return false
		button.button_pressed = true
		button.pressed.emit()
	(rows.get_node("SpendPicked") as Button).pressed.emit()
	return true


## INJURY_APPLIED: what the injury roll did, in words.
func show_effect(text: String) -> void:
	_effect = text
	if not _animating and _result != null:
		_show_outcome()


## ROLL_RESOLVED: tumbles, lands on the rolled values, then shows the outcome
## and calls `on_done`.
func show_result(result: RollResult, on_done: Callable) -> void:
	_clear_prompt()
	_result = result
	_on_done = on_done
	_show_breakdown(result.modifiers)
	_clear_dice()
	var roll_off: bool = result.request.kind == RollRequest.Kind.ROLL_OFF
	for i: int in result.dice.size():
		var holder: VBoxContainer = VBoxContainer.new()
		var face: DieFace = DieFace.new()
		holder.add_child(face)
		if roll_off:
			var caption: Label = UiStyle.label(UiStyle.player_name(i).split(" (")[0], 13, UiStyle.player_colour(i))
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			holder.add_child(caption)
		_dice_row.add_child(holder)
		_faces.append(face)
	_total.text = ""
	_outcome.text = ""
	_hint.visible = true
	_elapsed = 0.0
	_animating = true
	visible = true
	_update_faces()


## ACTIVATION_ENDED right after this roll, because it was a failed risky roll.
func note_activation_ended() -> void:
	_ended_activation = true
	if not _animating and _result != null:
		_show_outcome()


func is_animating() -> bool:
	return _animating


func skip() -> void:
	if _animating:
		_finish_animation(true)


func close() -> void:
	_finish_animation(true)
	visible = false


func _process(delta: float) -> void:
	if not _animating:
		return
	_elapsed += delta
	_update_faces()
	if _elapsed >= TUMBLE_SECONDS + LAND_SECONDS + OUTCOME_SECONDS:
		_finish_animation(true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _animating:
		skip()
		accept_event()


func _update_faces() -> void:
	if _result == null:
		return
	var step: int = int(_elapsed / TUMBLE_STEP_SECONDS)
	for i: int in _faces.size():
		var final_value: int = _result.dice[i]
		if _elapsed < TUMBLE_SECONDS:
			# A display-only cycle through the faces; the result is already fixed.
			var shown: int = (final_value + step * (i + 2) + i) % 6 + 1
			_faces[i].show_value(shown, DieFace.Look.TUMBLING, sin(step * 1.7 + i) * 0.35)
		elif _elapsed < TUMBLE_SECONDS + LAND_SECONDS:
			_faces[i].show_value(final_value, DieFace.Look.PLAIN)
		else:
			var look: DieFace.Look = DieFace.Look.KEPT if _result.kept[i] else DieFace.Look.DROPPED
			if _result.request.kind == RollRequest.Kind.ROLL_OFF:
				look = DieFace.Look.KEPT if _result.winner == i else DieFace.Look.DROPPED
			_faces[i].show_value(final_value, look)
	if _elapsed >= TUMBLE_SECONDS + LAND_SECONDS:
		_show_outcome()


func _finish_animation(call_done: bool) -> void:
	if not _animating:
		return
	_animating = false
	_elapsed = TUMBLE_SECONDS + LAND_SECONDS + OUTCOME_SECONDS
	_update_faces()
	_show_outcome()
	_hint.visible = false
	var done: Callable = _on_done
	_on_done = Callable()
	if call_done and done.is_valid():
		done.call()


func _show_outcome() -> void:
	if _result == null:
		return
	var request: RollRequest = _result.request
	if request.kind == RollRequest.Kind.ROLL_OFF:
		_total.text = "%d against %d" % [_result.dice[0], _result.dice[1]]
		if _result.winner == -1:
			_outcome.text = "[color=#%s]Draw: roll again[/color]" % UiStyle.GOLD_COLOUR.to_html(false)
		else:
			_outcome.text = "%s wins" % UiStyle.player_bb(_result.winner)
		return
	var kept: PackedStringArray = PackedStringArray()
	for value: int in _result.kept_dice():
		kept.append(str(value))
	_total.text = "Total %d  [color=#%s](%s)[/color]" % [_result.total, UiStyle.DIM_COLOUR.to_html(false), " + ".join(kept)]
	var text: String = ""
	match _result.outcome:
		RollResult.Outcome.CRITICAL:
			text = "[color=#%s]Critical![/color]" % UiStyle.GOLD_COLOUR.to_html(false)
		RollResult.Outcome.SUCCESS:
			text = "[color=#%s]Success[/color]" % UiStyle.GOOD_COLOUR.to_html(false)
		RollResult.Outcome.FAILURE:
			text = "[color=#%s]Failure[/color]" % UiStyle.BAD_COLOUR.to_html(false)
	if request.kind == RollRequest.Kind.INJURY and _effect != "":
		text = "[color=#%s]%s[/color]" % [UiStyle.GOLD_COLOUR.to_html(false), _effect]
	if _ended_activation:
		text += "  [color=#%s]— activation ends[/color]" % UiStyle.BAD_COLOUR.to_html(false)
	_outcome.text = text


## The base roll and every modifier line, with cancelled plus and minus dice
## (the first ones of each sign, in list order) struck through.
func _show_breakdown(modifiers: Array[RollModifier]) -> void:
	if _roll == null:
		return
	var request: RollRequest = _roll.request
	var lines: PackedStringArray = PackedStringArray()
	match request.kind:
		RollRequest.Kind.ROLL_OFF:
			lines.append("One d6 each, the higher wins")
		RollRequest.Kind.SUCCESS:
			lines.append("%dd6, %d+ succeeds" % [request.dice_kept, RollRequest.SUCCESS_TARGET])
		_:
			lines.append("%dd6" % request.dice_kept)
	if request.risky:
		lines.append("[color=#%s]Risky[/color]: a failure ends the activation" % UiStyle.BAD_COLOUR.to_html(false))
	var plus: int = 0
	var minus: int = 0
	for modifier: RollModifier in modifiers:
		if modifier.dice > 0:
			plus += modifier.dice
		else:
			minus -= modifier.dice
	var cancel_plus: int = mini(plus, minus)
	var cancel_minus: int = cancel_plus
	for modifier: RollModifier in modifiers:
		var tokens: PackedStringArray = PackedStringArray()
		for k: int in absi(modifier.dice):
			if modifier.dice > 0:
				tokens.append(_token("+1", cancel_plus > 0, UiStyle.GOOD_COLOUR))
				cancel_plus -= 1
			else:
				tokens.append(_token("−1", cancel_minus > 0, UiStyle.BAD_COLOUR))
				cancel_minus -= 1
		if modifier.makes_risky:
			tokens.append("[color=#%s]risky[/color]" % UiStyle.BAD_COLOUR.to_html(false))
		lines.append("• %s   %s" % [modifier.label, " ".join(tokens)])
	lines.append_array(_choice_lines)
	var net: int = plus - minus
	if plus > 0 and minus > 0:
		lines.append("[color=#%s]%d plus and %d minus cancel: %s[/color]" % [
			UiStyle.DIM_COLOUR.to_html(false), mini(plus, minus), mini(plus, minus), _net_text(net, request)
		])
	elif net != 0:
		lines.append("[color=#%s]%s[/color]" % [UiStyle.DIM_COLOUR.to_html(false), _net_text(net, request)])
	_breakdown.text = "\n".join(lines)


func _net_text(net: int, request: RollRequest) -> String:
	if net == 0:
		return "no extra dice"
	return "roll %d, keep the %s %d" % [request.dice_kept + absi(net), "highest" if net > 0 else "lowest", request.dice_kept]


func _token(text: String, cancelled: bool, colour: Color) -> String:
	if cancelled:
		return "[s][color=#%s]%s[/color][/s]" % [UiStyle.DIM_COLOUR.to_html(false), text]
	return "[b][color=#%s]%s[/color][/b]" % [colour.to_html(false), text]


func _clear_prompt() -> void:
	_prompt_label.text = ""
	for child: Node in _prompt_buttons.get_children():
		child.queue_free()
		_prompt_buttons.remove_child(child)
	_prompt_box.visible = false


func _clear_dice() -> void:
	for child: Node in _dice_row.get_children():
		_dice_row.remove_child(child)
		child.queue_free()
	_faces.clear()
