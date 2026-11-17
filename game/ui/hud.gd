class_name Hud
extends Control
## Turn and decision status, the selected model's panel with its action
## buttons, and the start-of-turn prompt. Reads core state to display it and
## reports button presses as signals; it never changes the state.

signal action_pressed(action_id: StringName)
signal end_activation_pressed
signal stay_pressed
signal first_player_chosen(first: int)
signal roll_off_pressed
signal undo_pressed
signal redo_pressed
signal descent_pressed
## Charge mode: "allow climbs and jumps" switched (brief 008b).
signal charge_rolls_pressed
## FREE_ATTACK_ORDER: the enemy player picked the next attacker.
signal attacker_picked(attacker_id: int)
signal sight_overview_pressed
signal sight_debug_pressed

var _turn_label: RichTextLabel
var _decision_label: RichTextLabel
var _model_panel: PanelContainer
var _model_title: RichTextLabel
var _model_details: RichTextLabel
var _actions_box: HBoxContainer
var _end_button: Button
var _stay_button: Button
var _prompt_panel: PanelContainer
var _prompt_label: RichTextLabel
var _prompt_buttons: HBoxContainer
var _message: RichTextLabel
var _help: Label
var _action_buttons: Dictionary[StringName, Button] = {}
var _undo_button: Button
var _descent_button: Button
var _charge_rolls_button: Button
var _redo_button: Button
var _sight_overview_button: Button
var _sight_debug_button: Button


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status_panel: PanelContainer = PanelContainer.new()
	status_panel.name = "Status"
	status_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	status_panel.position = Vector2(16, 16)
	status_panel.custom_minimum_size = Vector2(380, 0)
	add_child(status_panel)
	var status_box: VBoxContainer = VBoxContainer.new()
	status_panel.add_child(status_box)
	_turn_label = UiStyle.rich(20)
	status_box.add_child(_turn_label)
	_decision_label = UiStyle.rich(16)
	status_box.add_child(_decision_label)
	var history_row: HBoxContainer = HBoxContainer.new()
	history_row.add_theme_constant_override("separation", 6)
	status_box.add_child(history_row)
	_undo_button = UiStyle.button("Undo (Ctrl+Z)", "UndoButton")
	_undo_button.pressed.connect(func() -> void: undo_pressed.emit())
	history_row.add_child(_undo_button)
	_redo_button = UiStyle.button("Redo (Ctrl+Y)", "RedoButton")
	_redo_button.pressed.connect(func() -> void: redo_pressed.emit())
	history_row.add_child(_redo_button)
	var sight_row: HBoxContainer = HBoxContainer.new()
	sight_row.add_theme_constant_override("separation", 6)
	status_box.add_child(sight_row)
	_sight_overview_button = UiStyle.button("Sight overview (V)", "SightOverviewButton")
	_sight_overview_button.toggle_mode = true
	_sight_overview_button.tooltip_text = "Mark the enemies the selected model can see; dim the ones it cannot"
	_sight_overview_button.pressed.connect(func() -> void: sight_overview_pressed.emit())
	sight_row.add_child(_sight_overview_button)
	_sight_debug_button = UiStyle.button("Sight cylinders (L)", "SightDebugButton")
	_sight_debug_button.toggle_mode = true
	_sight_debug_button.tooltip_text = "Debug: draw every model's sight cylinder, tilted as the rules use it"
	_sight_debug_button.pressed.connect(func() -> void: sight_debug_pressed.emit())
	sight_row.add_child(_sight_debug_button)

	_model_panel = PanelContainer.new()
	_model_panel.name = "ModelPanel"
	_model_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_model_panel.custom_minimum_size = Vector2(380, 0)
	add_child(_model_panel)
	var model_box: VBoxContainer = VBoxContainer.new()
	model_box.add_theme_constant_override("separation", 6)
	_model_panel.add_child(model_box)
	_model_title = UiStyle.rich(18)
	model_box.add_child(_model_title)
	_model_details = UiStyle.rich(15)
	model_box.add_child(_model_details)
	_actions_box = HBoxContainer.new()
	_actions_box.name = "Actions"
	_actions_box.add_theme_constant_override("separation", 6)
	model_box.add_child(_actions_box)
	_descent_button = UiStyle.button("Descent: Drop (C)", "DescentButton")
	_descent_button.tooltip_text = "How drops of 3\" or more are taken: Drop (free, injury roll) or Climb down (pays the height, risky roll). C switches."
	_descent_button.pressed.connect(func() -> void: descent_pressed.emit())
	model_box.add_child(_descent_button)
	_charge_rolls_button = UiStyle.button("Climbs and jumps: off (J)", "ChargeRollsButton")
	_charge_rolls_button.toggle_mode = true
	_charge_rolls_button.tooltip_text = "Charge route: off takes the shortest route with no roll; on the shortest route of any kind (sheer climbs, jumps, drops of 3\" or more). J switches."
	_charge_rolls_button.pressed.connect(func() -> void: charge_rolls_pressed.emit())
	_charge_rolls_button.visible = false
	model_box.add_child(_charge_rolls_button)
	_stay_button = UiStyle.button("Finish move", "StayButton")
	_stay_button.tooltip_text = "End the move here; movement left over is lost"
	_stay_button.pressed.connect(func() -> void: stay_pressed.emit())
	model_box.add_child(_stay_button)
	_end_button = UiStyle.button("End activation", "EndActivationButton")
	_end_button.pressed.connect(func() -> void: end_activation_pressed.emit())
	model_box.add_child(_end_button)
	_model_panel.visible = false

	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "TurnPrompt"
	_prompt_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GOLD_COLOUR.darkened(0.3)))
	_prompt_panel.custom_minimum_size = Vector2(520, 0)
	add_child(_prompt_panel)
	var prompt_box: VBoxContainer = VBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", 10)
	_prompt_panel.add_child(prompt_box)
	_prompt_label = UiStyle.rich(18)
	prompt_box.add_child(_prompt_label)
	_prompt_buttons = HBoxContainer.new()
	_prompt_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_buttons.add_theme_constant_override("separation", 12)
	prompt_box.add_child(_prompt_buttons)
	_prompt_panel.visible = false

	_message = UiStyle.rich(15)
	_message.custom_minimum_size = Vector2(700, 0)
	add_child(_message)

	_help = UiStyle.label(
		"Left click: select / move.  Right drag: orbit.  Middle drag / WASD: pan.  Wheel: zoom.  O: overrides.  Esc: deselect.",
		13, UiStyle.DIM_COLOUR
	)
	_help.custom_minimum_size = Vector2(744, 0)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_help)


func _process(_delta: float) -> void:
	var view: Vector2 = size
	_model_panel.size.y = 0.0
	_model_panel.position = Vector2(16, view.y - _model_panel.get_combined_minimum_size().y - 16)
	_prompt_panel.position = Vector2((view.x - _prompt_panel.size.x) / 2.0, 90)
	_message.position = Vector2((view.x - _message.size.x) / 2.0, view.y - 60)
	_help.position = Vector2(view.x - _help.size.x - 16, view.y - 28)


## Redraws everything from the state. `selected_id` is the previewed model
## or -1; `attack_order` the attackers picked so far for a FREE_ATTACK_ORDER
## decision; `charge_mode` whether the selected model is picking a charge
## target, and `charge_rolls` whether its routes may climb and jump.
func refresh(
	state: GameState, selected_id: int, descent: Transitions.DescentMode = Transitions.DescentMode.DROP,
	attack_order: Array[int] = [], charge_mode: bool = false, charge_rolls: bool = false
) -> void:
	_descent_button.text = "Descent: %s (C)" % ("Climb down" if descent == Transitions.DescentMode.CLIMB_DOWN else "Drop")
	_charge_rolls_button.visible = charge_mode
	_charge_rolls_button.set_pressed_no_signal(charge_rolls)
	_charge_rolls_button.text = "Climbs and jumps: %s (J)" % ("on" if charge_rolls else "off")
	refresh_status(state)
	_refresh_prompt(state, attack_order)
	_refresh_model(state, selected_id, charge_mode)


## Shows whether the sight overview and the debug cylinders are on.
func show_sight_toggles(overview: bool, debug: bool) -> void:
	_sight_overview_button.set_pressed_no_signal(overview)
	_sight_debug_button.set_pressed_no_signal(debug)


func show_message(text: String) -> void:
	_message.text = "[center]%s[/center]" % text


## Presses a HUD button by node name (as a click would). For scripted runs.
func press(button_name: String) -> bool:
	var button: Button = find_child(button_name, true, false) as Button
	if button == null or button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


## The turn line, what core waits for now, and undo and redo.
func refresh_status(state: GameState) -> void:
	var t: TurnState = state.turn
	_undo_button.disabled = not state.can_undo()
	_redo_button.disabled = not state.can_redo()
	_undo_button.tooltip_text = "Take back the last step (back to the start of turn 1)"
	_redo_button.tooltip_text = "Do the last undone step again (same dice)"
	_turn_label.text = "[b]Turn %d[/b]" % t.turn if t.turn > 0 else "[b]Set-up[/b]"
	var pending: PendingDecision = state.pending
	if pending != null:
		_decision_label.text = "Decision: %s\n%s" % [UiStyle.player_bb(pending.player), pending.prompt]
	elif state.active_roll != null:
		_decision_label.text = "Rolling…"
	elif t.player_to_act >= 0:
		var text: String = "To act: %s" % UiStyle.player_bb(t.player_to_act)
		if t.active_model_id != -1:
			text += "\nModel %d is activating." % t.active_model_id
		else:
			text += "\nSelect a model that has not activated."
		_decision_label.text = text
	else:
		_decision_label.text = ""


func _refresh_prompt(state: GameState, attack_order: Array[int] = []) -> void:
	var pending: PendingDecision = state.pending
	var order_prompt: bool = pending != null and pending.kind == PendingDecision.Kind.FREE_ATTACK_ORDER
	var turn_prompt: bool = pending != null and (
		pending.kind == PendingDecision.Kind.CHOOSE_FIRST_PLAYER or pending.kind == PendingDecision.Kind.ROLL_OFF
	)
	_prompt_panel.visible = turn_prompt or order_prompt
	if not _prompt_panel.visible:
		return
	for child: Node in _prompt_buttons.get_children():
		_prompt_buttons.remove_child(child)
		child.queue_free()
	if order_prompt:
		var picked: PackedStringArray = PackedStringArray()
		for id: int in attack_order:
			picked.append("model %d" % id)
		_prompt_label.text = "[center][b]Free attacks[/b]
%s: %s
%s[/center]" % [
			UiStyle.player_bb(pending.player), pending.prompt,
			"Order so far: %s. Who attacks next?" % ", ".join(picked) if not picked.is_empty() else "Who attacks first?"
		]
		for id: int in pending.model_ids:
			if attack_order.has(id):
				continue
			var pick: Button = UiStyle.button("Model %d" % id, "Attacker%d" % id)
			pick.add_theme_color_override("font_color", UiStyle.player_colour(pending.player))
			pick.custom_minimum_size = Vector2(150, 38)
			pick.pressed.connect(func() -> void: attacker_picked.emit(id))
			_prompt_buttons.add_child(pick)
		return
	_prompt_label.text = "[center][b]Turn %d[/b]\n%s: %s[/center]" % [
		state.turn.turn, UiStyle.player_bb(pending.player) if pending.player >= 0 else "Both players", pending.prompt
	]
	if pending.kind == PendingDecision.Kind.ROLL_OFF:
		var roll: Button = UiStyle.button("Roll off", "RollOffButton")
		roll.custom_minimum_size = Vector2(160, 38)
		roll.pressed.connect(func() -> void: roll_off_pressed.emit())
		_prompt_buttons.add_child(roll)
	else:
		for player: int in 2:
			var choose: Button = UiStyle.button("%s first" % UiStyle.player_name(player), "First%d" % player)
			choose.add_theme_color_override("font_color", UiStyle.player_colour(player))
			choose.custom_minimum_size = Vector2(200, 38)
			choose.pressed.connect(func() -> void: first_player_chosen.emit(player))
			_prompt_buttons.add_child(choose)


func _refresh_model(state: GameState, selected_id: int, charge_mode: bool = false) -> void:
	var model: ModelState = state.get_model(selected_id)
	_model_panel.visible = model != null
	if model == null:
		return
	var t: TurnState = state.turn
	var status: String = "not activated"
	if t.active_model_id == model.id:
		status = "[color=#%s]activating[/color]" % UiStyle.GOLD_COLOUR.to_html(false)
	elif t.has_activated(model.id):
		status = "[color=#%s]activated[/color]" % UiStyle.DIM_COLOUR.to_html(false)
	_model_title.text = "[b]Model %d[/b]  %s  —  %s" % [model.id, UiStyle.player_bb(model.player), status]
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Movement %s\"   %d mm base" % [_inches(model.movement), model.base_mm])
	var markers: PackedStringArray = PackedStringArray()
	for kind: StringName in Markers.KINDS:
		markers.append("%s %d" % [Markers.label(kind), model.marker_count(kind)])
	lines.append("  ·  ".join(markers))
	if not model.on_table():
		lines.append("[color=#%s]Out of Action[/color] (removed from the table)" % UiStyle.BAD_COLOUR.to_html(false))
	elif model.down:
		lines.append("[color=#%s]Down[/color] (stands up when it activates, then moves half)" % UiStyle.BAD_COLOUR.to_html(false))
	elif t.active_model_id == model.id and t.stood_up:
		lines.append("Stood up this activation: half movement")
	var melee: Array[int] = MeleeZone.enemy_ids_within(state, model)
	var retreating: bool = (
		state.pending != null and state.pending.kind == PendingDecision.Kind.MOVE
		and state.pending.model_id == model.id and state.pending.zones != null
	)
	if retreating:
		lines.append("[color=#%s]Retreating[/color]: the move must end more than 1\" from every enemy." % UiStyle.GOLD_COLOUR.to_html(false))
	elif not melee.is_empty():
		lines.append("[color=#%s]In melee[/color] with %s: it cannot Move, Dash or Charge; it can only leave by Retreating." % [
			UiStyle.GOLD_COLOUR.to_html(false), ", ".join(melee.map(func(id: int) -> String: return "model %d" % id))
		])
	if charge_mode:
		lines.append("[color=#%s]Charge mode[/color]: click an enemy to charge it (G or Esc to leave; J: climbs and jumps)." % UiStyle.GOLD_COLOUR.to_html(false))
	if not t.actions_used.is_empty() and t.active_model_id == model.id:
		lines.append("Used: %s" % ", ".join(t.actions_used.map(func(id: StringName) -> String: return state.rules.action(id).label)))
	_model_details.text = "\n".join(lines)

	for action: ActionDef in state.rules.actions:
		var button: Button = _action_buttons.get(action.id)
		if button == null:
			button = UiStyle.button(action.label, "Action_%s" % action.id)
			button.custom_minimum_size = Vector2(110, 34)
			var id: StringName = action.id
			button.pressed.connect(func() -> void: action_pressed.emit(id))
			_actions_box.add_child(button)
			_action_buttons[action.id] = button
		var reason: String = TurnFlow.activation_error(state, model.player, model)
		if reason == "":
			reason = BeginActionCommand.unavailable_reason(state, model, action.id)
		button.disabled = reason != ""
		button.tooltip_text = reason if reason != "" else "%s%s" % [action.label, " (risky)" if action.risky else ""]
		var hotkey: String = {&"charge": " (G)", &"retreat": " (R)"}.get(action.id, "")
		button.text = action.label + hotkey
		if action.id == &"charge":
			button.toggle_mode = true
			button.set_pressed_no_signal(charge_mode)

	var pending: PendingDecision = state.pending
	var moving: bool = pending != null and pending.kind == PendingDecision.Kind.MOVE and pending.model_id == model.id
	_stay_button.visible = moving
	var end_error: String = EndActivationCommand.new(model.player, model.id).validate(state)
	_end_button.disabled = end_error != ""
	_end_button.tooltip_text = end_error if end_error != "" else "End this model's activation"


static func _inches(value: float) -> String:
	return str(snappedf(value, 0.1))
