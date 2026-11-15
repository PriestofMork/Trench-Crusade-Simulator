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
	_stay_button = UiStyle.button("Stay (skip move)", "StayButton")
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


## Redraws everything from the state. `selected_id` is the previewed model or -1.
func refresh(state: GameState, selected_id: int) -> void:
	_refresh_status(state)
	_refresh_prompt(state)
	_refresh_model(state, selected_id)


func show_message(text: String) -> void:
	_message.text = "[center]%s[/center]" % text


## Presses a HUD button by node name (as a click would). For scripted runs.
func press(button_name: String) -> bool:
	var button: Button = find_child(button_name, true, false) as Button
	if button == null or button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


func _refresh_status(state: GameState) -> void:
	var t: TurnState = state.turn
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


func _refresh_prompt(state: GameState) -> void:
	var pending: PendingDecision = state.pending
	var turn_prompt: bool = pending != null and (
		pending.kind == PendingDecision.Kind.CHOOSE_FIRST_PLAYER or pending.kind == PendingDecision.Kind.ROLL_OFF
	)
	_prompt_panel.visible = turn_prompt
	if not turn_prompt:
		return
	for child: Node in _prompt_buttons.get_children():
		_prompt_buttons.remove_child(child)
		child.queue_free()
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


func _refresh_model(state: GameState, selected_id: int) -> void:
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
	if model.down:
		lines.append("[color=#%s]Down[/color] (stands up when it activates, then moves half)" % UiStyle.BAD_COLOUR.to_html(false))
	elif t.active_model_id == model.id and t.stood_up:
		lines.append("Stood up this activation: half movement")
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

	var pending: PendingDecision = state.pending
	var moving: bool = pending != null and pending.kind == PendingDecision.Kind.MOVE and pending.model_id == model.id
	_stay_button.visible = moving
	var end_error: String = EndActivationCommand.new(model.player, model.id).validate(state)
	_end_button.disabled = end_error != ""
	_end_button.tooltip_text = end_error if end_error != "" else "End this model's activation"


static func _inches(value: float) -> String:
	return str(snappedf(value, 0.1))
