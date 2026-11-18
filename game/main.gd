extends Node3D
## Main scene: builds a GameState through commands, builds the views, and
## wires the parts of game/ together: the shared Session (command sender with
## event playback, undo and redo; selection and picking; background jobs;
## state-keyed caches; the confirmation prompt; sight) and one controller
## per interaction mode (game/modes/). Input goes to the active mode; what it
## does not handle goes to Move, the default. Never changes the state
## directly. Two players share the screen and mouse (hotseat); every prompt
## names the player who answers it.
##
## Keys: G (or the Charge button) charge mode; R (or the Retreat button)
## retreat; C (or the HUD button) the selected model's descent mode, Drop or
## Climb down; V the sight overview; L the sight debug view; O the override
## panel; Enter / Esc confirm or cancel the confirmation panel (Esc otherwise
## leaves the mode, or deselects); Ctrl+Z / Ctrl+Y undo / redo (also HUD
## buttons). While the dice tumble, a click or a key skips to the result.
## What hovering and clicking do in each mode is in that mode's script.

## The table set-up loaded at start (terrain and models).
const TABLE_FILE: String = "res://data/tables/height_test_table.json"

var state: GameState
## Every event played, for logs and scripted checks.
var event_log: Array[GameEvent]:
	get:
		return _session.sender.event_log

## The mode controllers and the sight helper (public for scripted checks).
var move: MoveMode
var charge: ChargeMode
var contact: ContactMode
var retreat: RetreatMode
var sight: SightOverlay

var _session: Session = Session.new()
var _mode: InteractionMode
var _overrides: OverridePanel

@onready var _camera: TableCamera = $TableCamera
@onready var _table_root: Node3D = $Table
@onready var _models_root: Node3D = $Models


func _ready() -> void:
	state = GameState.new(1)
	_session.state = state
	_session.camera = _camera
	TableBuilder.build_table(_table_root, state)
	for command: Command in TableSetup.commands(TableSetup.load_file(TABLE_FILE)):
		var error: String = state.execute(command)
		if error != "":
			push_error("Table set-up rejected: %s" % error)
	TableBuilder.build_views(_table_root, _models_root, state, _session.views)
	var layer: CanvasLayer = TableBuilder.build_overlays(self, _session)
	_overrides = OverridePanel.new()
	_overrides.send = func(command: Command) -> void: _session.send(command)
	layer.add_child(_overrides)
	_build_session()
	_camera.set_table_bounds(state.table_width, state.table_depth)
	_session.send(StartGameCommand.new())


func _exit_tree() -> void:
	_session.dispose()


func _unhandled_input(event: InputEvent) -> void:
	var tray_view: DiceTray = _session.tray
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if not button.pressed:
			return
		if tray_view.is_animating():
			tray_view.skip()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and not is_busy():
			if not _mode.click(button.position):
				move.click(button.position)
	elif event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		if tray_view.is_animating():
			tray_view.skip()
			return
		_on_key(key)


func _on_key(key: InputEventKey) -> void:
	var code: Key = key.physical_keycode
	var prompt: ConfirmPrompt = _session.prompt
	if key.ctrl_pressed and code == KEY_Z:
		if key.shift_pressed:
			_session.sender.redo()
		else:
			_session.sender.undo()
	elif key.ctrl_pressed and code == KEY_Y:
		_session.sender.redo()
	elif (code == KEY_ENTER or code == KEY_KP_ENTER) and prompt.is_open():
		prompt.confirm()
	elif code == KEY_ESCAPE and prompt.is_open():
		prompt.cancel()
	elif _mode.key(key):
		pass
	elif code == KEY_ESCAPE:
		deselect()
	elif code == KEY_O:
		toggle_overrides()
	elif key.ctrl_pressed:
		pass
	elif code == KEY_G:
		toggle_charge_mode()
	elif code == KEY_R:
		enter_mode(retreat)
	elif code == KEY_C:
		toggle_descent_mode()
	elif code == KEY_V:
		sight.toggle_overview()
	elif code == KEY_L:
		sight.toggle_debug()


func _process(_delta: float) -> void:
	_session.jobs.poll()
	if _session.selection.id != -1 and not is_busy():
		if not _mode.hover():
			move.hover()
	var view: Vector2 = get_viewport().get_visible_rect().size
	_session.tray.size.y = 0.0
	_session.tray.position = Vector2(view.x - TableBuilder.TRAY_WIDTH - 16.0, 16.0)
	_overrides.size.y = 0.0
	_overrides.position = Vector2(16.0, 150.0)


## Opens `mode`, leaving the active one. Returns "" or why it cannot open.
func enter_mode(mode: InteractionMode) -> String:
	var error: String = mode.enter_error()
	if error == "":
		_switch_to(mode)
	return error


func toggle_charge_mode() -> String:
	if _mode == charge:
		_leave_mode()
		_refresh_all()
		return ""
	return enter_mode(charge)


func _switch_to(mode: InteractionMode) -> void:
	_mode.exit()
	_mode.active = false
	_mode = mode
	_mode.active = true
	_mode.enter()


## Back to the default mode (Move), which starts afresh.
func _leave_mode() -> void:
	_switch_to(move)


## Selects a model to preview it: its panel, and where Move would take it.
func select_model(id: int) -> void:
	if id != _session.selection.id:
		_leave_mode()
	_session.selection.set_id(id)
	_refresh_all()


func deselect() -> void:
	_leave_mode()
	_session.selection.set_id(-1)
	sight.clear_hover()
	_refresh_all()


func selected_model_id() -> int:
	return _session.selection.id


## Whether events are still being played back (input to the table waits).
func is_busy() -> bool:
	return _session.is_busy()


## Switches the selected model between Drop and Climb down and redraws its area.
func toggle_descent_mode() -> void:
	var selection: Selection = _session.selection
	if selection.id == -1 or is_busy():
		return
	var mode: Transitions.DescentMode = Transitions.DescentMode.CLIMB_DOWN
	if selection.descent_mode() == Transitions.DescentMode.CLIMB_DOWN:
		mode = Transitions.DescentMode.DROP
	selection.set_descent_mode(mode)
	_session.message("Descent: %s" % Selection.descent_name(mode))
	_mode.descent_changed()
	_refresh_all()


## Takes an action with the selected model (the HUD's action buttons).
## Charge opens charge mode and Retreat asks for confirmation first.
func _take_action(action_id: StringName) -> String:
	var model: ModelState = _session.selection.model()
	if model == null or is_busy():
		return "No model selected."
	if action_id == &"charge":
		return toggle_charge_mode()
	if action_id == &"retreat":
		return enter_mode(retreat)
	return _session.send(BeginActionCommand.new(model.player, model.id, action_id))


func toggle_overrides() -> void:
	_overrides.visible = not _overrides.visible
	_refresh_all()


## The UI pieces, for scripted runs that press their buttons.
func hud() -> Hud:
	return _session.hud


func tray() -> DiceTray:
	return _session.tray


func override_panel() -> OverridePanel:
	return _overrides


## The shared parts (for tests).
func session() -> Session:
	return _session


## The confirmation panel's question, or "" when it is closed (for scripted checks).
func confirm_text() -> String:
	return _session.prompt.text()


## Closes the confirmation panel without doing it (Cancel or Escape).
func cancel_confirm() -> void:
	_session.prompt.cancel()


## Scripted hover for screenshots: a 3D point on a floor, or null to follow the mouse again.
func set_hover_override(point: Variant) -> void:
	_session.selection.hover_override = point


## Brings every view in line with the state once the events are played.
## Skipped while events are still playing, so nothing shows ahead of them.
## A pending contact choice opens its mode, and leaving it is answered.
func _refresh_all() -> void:
	if _mode == null or is_busy():
		return
	if ContactMode.is_pending(state) and _mode != contact:
		_switch_to(contact)
	elif not ContactMode.is_pending(state) and _mode == contact:
		_leave_mode()
	var selection: Selection = _session.selection
	for model: ModelState in state.models:
		var view: ModelView = _session.views[model.id]
		view.sync(model)
		view.show_status(model, state.turn.has_activated(model.id), state.turn.active_model_id == model.id, MeleeZone.in_melee(state, model))
	_session.hud.refresh(state, selection.id, selection.descent_mode(), retreat.attack_order(), charge.active, charge.is_rolls())
	_session.hud.show_sight_toggles(sight.is_overview(), sight.is_debug())
	_overrides.refresh(state, selection.id)
	_mode.refresh()
	# Melee links, and the enemy zones while a model is selected to move or charge.
	_session.melee_view.show_links(state)
	var selected: ModelState = selection.model()
	_session.melee_view.show_zones(state, selected if selected != null and _mode.shows_zones() else null)
	sight.refresh(_mode.shows_sight())


## The shared parts, the modes, and the HUD's and tray's buttons wired to them.
func _build_session() -> void:
	var session: Session = _session
	session.selection = Selection.new(state, _camera, session.views)
	session.sender = CommandSender.new(session)
	session.sight = SightOverlay.new(session)
	session.set_host(_refresh_all, select_model, deselect, func() -> void:
		_leave_mode()
		_refresh_all()
	)
	sight = session.sight
	move = MoveMode.new(session)
	charge = ChargeMode.new(session)
	contact = ContactMode.new(session)
	retreat = RetreatMode.new(session)
	_mode = move
	move.active = true

	var sender: CommandSender = session.sender
	sender.restored.connect(_leave_mode)
	var hud_view: Hud = session.hud
	hud_view.action_pressed.connect(func(id: StringName) -> void: _take_action(id))
	hud_view.end_activation_pressed.connect(func() -> void:
		var model: ModelState = session.selection.model()
		if model != null and not is_busy():
			session.send(EndActivationCommand.new(model.player, model.id))
	)
	hud_view.stay_pressed.connect(func() -> void:
		if state.pending != null:
			session.send(DeclineMoveCommand.new(state.pending.player))
	)
	hud_view.first_player_chosen.connect(func(first: int) -> void:
		if state.pending != null:
			session.send(ChooseFirstPlayerCommand.new(state.pending.player, first))
	)
	hud_view.roll_off_pressed.connect(func() -> void: session.send(RollOffCommand.new(0)))
	hud_view.undo_pressed.connect(func() -> void: sender.undo())
	hud_view.redo_pressed.connect(func() -> void: sender.redo())
	hud_view.descent_pressed.connect(toggle_descent_mode)
	hud_view.charge_rolls_pressed.connect(func() -> void: charge.toggle_rolls())
	hud_view.attacker_picked.connect(func(id: int) -> void: retreat.pick_attacker(id))
	hud_view.sight_overview_pressed.connect(sight.toggle_overview)
	hud_view.sight_debug_pressed.connect(sight.toggle_debug)
	session.tray.choice_answered.connect(func(amounts: Array[int]) -> void:
		if state.pending != null:
			session.send(RollChoiceCommand.new(state.pending.player, 0, amounts))
	)
