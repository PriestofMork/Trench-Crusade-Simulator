extends Node3D
## Main scene: builds a GameState through commands, shows it, turns clicks and
## button presses into commands, and plays back the events core returns, in
## order. Never changes the state directly. Two players share the screen and
## mouse (hotseat); every prompt names the player who answers it.
##
## Left click a model: select it (a preview; the activation starts with its
## first action). Left click inside the blue area: take the Move action there
## (or make the move a Dash granted); a move may be made in several clicks
## while it has distance left. Left click inside the orange area (only with
## rolls): the route and its rolls are pinned and wait for Confirm (or Enter);
## Escape cancels. C (or the HUD button): switch the selected model's descent
## mode between Drop and Climb down, which redraws its area. Escape:
## deselect. O: override panel.
## G (or the Charge button): charge mode (brief 007). Every enemy in range is
## labelled with what the charge needs; hovering one previews the charge
## path; clicking it asks for confirmation, then the D6 rolls. If the charge
## reaches with distance to spare, the places it may end are an arc around
## the target's base: hover to see who else would be charged, click to pick
## (Enter keeps first contact). R (or the Retreat button), in melee: lists
## the free attacks, asks for confirmation, plays them, then the move.
## Ctrl+Z / Ctrl+Y: undo / redo (also HUD buttons).
## While the dice tumble, a click or a key skips to the result.

const TABLE_THICKNESS: float = 1.0
## The table set-up loaded at start (terrain and models).
const TABLE_FILE: String = "res://data/tables/height_test_table.json"
## The action a click on the table takes.
const CLICK_ACTION: StringName = &"move"
const TRAY_WIDTH: float = 420.0

var state: GameState

var _views: Dictionary[int, ModelView] = {}
var _selected_id: int = -1
var _reach: ReachField
var _reach_key: String = ""
## Built reach fields by key (model, budget, position, descent mode), each
## [field, layers, indicator mesh], so switching the descent mode back or
## selecting a model again is instant. Emptied whenever the state changes.
var _reach_cache: Dictionary[String, Array] = {}
## Descent mode per model id (Drop if not set).
var _descent: Dictionary[int, Transitions.DescentMode] = {}
var _indicator: MovementIndicator
var _preview: PathPreview
var _distance_label: Label
var _hud: Hud
var _tray: DiceTray
var _overrides: OverridePanel
## When set, hover follows this 3D point instead of the mouse (for scripted screenshots).
var _hover_override: Variant = null
## An orange destination waiting for confirmation (ruling 7 of brief 006), or null.
var _pinned: Variant = null
var _confirm_panel: PanelContainer
var _confirm_label: RichTextLabel
## What the confirmation panel is asking about: &"move" (a pinned orange
## move), &"charge" or &"retreat"; &"" when it is closed.
var _confirming: StringName = &""
## Melee links, enemy zones, charge labels and the contact arc.
var _melee_view: MeleeView
## Brief 008: the sight line on hover, the overview and the debug cylinders.
var _sight_view: SightView
## Sight answers for the current state, "viewer>target" -> result. Dropped
## whenever the state changes; never worked out by a view.
var _sight_cache: Dictionary[String, SightResult] = {}
## The sight overview (V): marks what the selected model sees, dims the rest.
var _sight_overview: bool = false
## The debug view (L): every model's sight cylinder, tilted.
var _sight_debug: bool = false
## The enemy under the cursor while a model is selected, or -1.
var _sight_hover: int = -1

## Charge mode (brief 007): on while the selected model picks a target. The
## plans (by declared target) are worked out on a worker thread.
var _charge_mode: bool = false
var _charge_plans: Dictionary[int, ChargePlan] = {}
var _charge_task: int = -1
var _built_plans: Dictionary[int, ChargePlan] = {}
var _built_plans_ready: bool = false
## The target the confirmation panel would charge.
var _charge_target: int = -1
## The contact position under the cursor (CHARGE_CONTACT), or -1.
var _contact_hover: int = -1
## The free attacks of the retreat being played, as tray lines.
var _free_attack_lines: PackedStringArray = PackedStringArray()
## FREE_ATTACK_ORDER: the attackers picked so far, in order.
var _attack_order: Array[int] = []

## Events waiting to be played back, and whether one is playing (dice, a slide).
var _queue: Array[GameEvent] = []
var _playing: bool = false
## Every event played, for logs and scripted checks.
var event_log: Array[GameEvent] = []

# The reach field is built on a worker thread so selecting stays responsive.
var _reach_task: int = -1
var _reach_task_key: String = ""
var _reach_started_usec: int = 0
var _built_mutex: Mutex = Mutex.new()
var _built_field: ReachField = null
var _built_layers: Array[ReachField.Layer] = []

@onready var _camera: TableCamera = $TableCamera
@onready var _table_root: Node3D = $Table
@onready var _models_root: Node3D = $Models


func _ready() -> void:
	state = GameState.new(1)
	_build_table()
	for command: Command in TableSetup.commands(TableSetup.load_file(TABLE_FILE)):
		var error: String = state.execute(command)
		if error != "":
			push_error("Table set-up rejected: %s" % error)
	_build_terrain_views()
	_build_model_views()
	_build_overlays()
	_camera.set_table_bounds(state.table_width, state.table_depth)
	send(StartGameCommand.new())


func _exit_tree() -> void:
	if _reach_task != -1:
		WorkerThreadPool.wait_for_task_completion(_reach_task)
		_reach_task = -1
	_wait_for_charge_task()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if not button.pressed:
			return
		if _tray.is_animating():
			_tray.skip()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and not is_busy():
			_on_left_click(button.position)
	elif event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		if _tray.is_animating():
			_tray.skip()
			return
		if key.ctrl_pressed and key.physical_keycode == KEY_Z:
			if key.shift_pressed:
				redo()
			else:
				undo()
		elif key.ctrl_pressed and key.physical_keycode == KEY_Y:
			redo()
		elif key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
			if _confirming != &"":
				confirm()
			elif _contact_pending():
				choose_contact(state.pending.default_index)
		elif key.physical_keycode == KEY_ESCAPE:
			if _confirming != &"":
				cancel_confirm()
			elif _charge_mode:
				exit_charge_mode()
			else:
				deselect()
		elif key.physical_keycode == KEY_G and not key.ctrl_pressed:
			toggle_charge_mode()
		elif key.physical_keycode == KEY_R and not key.ctrl_pressed:
			request_retreat()
		elif key.physical_keycode == KEY_C and not key.ctrl_pressed:
			toggle_descent_mode()
		elif key.physical_keycode == KEY_O:
			toggle_overrides()
		elif key.physical_keycode == KEY_V and not key.ctrl_pressed:
			toggle_sight_overview()
		elif key.physical_keycode == KEY_L and not key.ctrl_pressed:
			toggle_sight_debug()


func _process(_delta: float) -> void:
	_collect_reach()
	_collect_charges()
	_update_hover()
	var view: Vector2 = get_viewport().get_visible_rect().size
	_tray.size.y = 0.0
	_tray.position = Vector2(view.x - TRAY_WIDTH - 16.0, 16.0)
	_overrides.size.y = 0.0
	_overrides.position = Vector2(16.0, 150.0)
	_confirm_panel.size = Vector2(0.0, 0.0)
	_confirm_panel.position = Vector2((view.x - _confirm_panel.size.x) / 2.0, view.y - _confirm_panel.size.y - 24.0)


## Runs a command and plays back its events. Returns "" or why it was rejected.
func send(command: Command) -> String:
	var result: CommandResult = state.submit(command)
	if not result.ok():
		_hud.show_message("[color=#%s]%s[/color]" % [UiStyle.BAD_COLOUR.to_html(false), result.error])
		_refresh_all()
		return result.error
	_state_changed()
	_hud.show_message("")
	_queue.append_array(result.events)
	_pump()
	return ""


## Whether events are still being played back (input to the table waits).
func is_busy() -> bool:
	return _playing or not _queue.is_empty()


## Selects a model to preview it: its panel, and where Move would take it.
func select_model(id: int) -> void:
	if _charge_mode and id != _selected_id:
		exit_charge_mode()
	if _selected_id != -1 and _views.has(_selected_id):
		_views[_selected_id].set_selected(false)
	_selected_id = id
	_views[id].set_selected(true)
	_refresh_all()


func deselect() -> void:
	if _charge_mode:
		exit_charge_mode()
	if _selected_id != -1 and _views.has(_selected_id):
		_views[_selected_id].set_selected(false)
	_selected_id = -1
	_sight_hover = -1
	_sight_view.hide_line()
	_unpin()
	_refresh_all()


func selected_model_id() -> int:
	return _selected_id


## What a click on a destination does: a blue one moves at once; an orange
## one (only with rolls) is pinned with its route and rolls and waits for
## confirm_pinned() (ruling 7). Returns "" or why not.
func request_move_to(point: Vector3) -> String:
	if _selected_id == -1 or _reach == null or is_busy():
		return "No model selected."
	if not _reach.is_reachable(point):
		return "Out of reach."
	if _reach.needs_rolls(point):
		_pin(point)
		return ""
	_unpin()
	return move_selected_to(point)


## The pinned orange destination, or null.
func pinned_destination() -> Variant:
	return _pinned


## Makes the pinned move.
func confirm_pinned() -> String:
	if _pinned == null:
		return "Nothing to confirm."
	var point: Vector3 = _pinned
	_unpin()
	return move_selected_to(point)


func cancel_pinned() -> void:
	_unpin()
	_hud.show_message("Move cancelled.")


## What the confirmation panel asks about, done (Confirm or Enter).
func confirm() -> String:
	match _confirming:
		&"move":
			return confirm_pinned()
		&"charge":
			return confirm_charge()
		&"retreat":
			return confirm_retreat()
	return "Nothing to confirm."


## Closes the confirmation panel without doing it (Cancel or Escape).
func cancel_confirm() -> void:
	match _confirming:
		&"move":
			cancel_pinned()
		&"charge":
			_close_confirm()
			_charge_target = -1
			_hud.show_message("Charge not declared. Pick another target, or Esc to leave charge mode.")
		&"retreat":
			_close_confirm()
			_hud.show_message("Retreat cancelled.")


## The confirmation panel's question, or "" when it is closed (for scripted checks).
func confirm_text() -> String:
	return _confirm_label.get_parsed_text() if _confirming != &"" else ""


func _ask_confirm(kind: StringName, text: String) -> void:
	_confirming = kind
	_confirm_label.text = text
	_confirm_panel.visible = true


func _close_confirm() -> void:
	_confirming = &""
	if _confirm_panel != null:
		_confirm_panel.visible = false


func _pin(point: Vector3) -> void:
	_pinned = point
	var labels: PackedStringArray = PackedStringArray()
	for roll: Dictionary in _reach.rolls_to(point):
		labels.append(String(roll["label"]))
	_ask_confirm(&"move", "[b]This move needs rolls[/b]\n%s\n%.1f\" of %.1f\"" % [
		"  -  ".join(labels), _reach.cost_to(point), _reach.budget
	])


func _unpin() -> void:
	_pinned = null
	if _confirming == &"move":
		_close_confirm()


## Moves the selected model to `point` along the reach field's path: answers
## a pending move, or takes the Move action first. Orange destinations move
## without asking here (request_move_to() asks). Returns "" or why not.
func move_selected_to(point: Vector3) -> String:
	if _selected_id == -1 or _reach == null or is_busy():
		return "No model selected."
	var path: Array[Vector3] = _reach.path_to(point)
	if path.is_empty():
		return "Out of reach."
	var model: ModelState = state.get_model(_selected_id)
	if not _move_pending_for(_selected_id):
		var error: String = send(BeginActionCommand.new(model.player, model.id, CLICK_ACTION))
		if error != "":
			return error
	return send(MoveCommand.new(state.pending.player, model.id, path, _reach.descent_mode))


## Takes an action with the selected model (the HUD's action buttons).
## Charge opens charge mode and Retreat asks for confirmation first.
func take_action(action_id: StringName) -> String:
	var model: ModelState = state.get_model(_selected_id)
	if model == null or is_busy():
		return "No model selected."
	if action_id == &"charge":
		return toggle_charge_mode()
	if action_id == &"retreat":
		return request_retreat()
	return send(BeginActionCommand.new(model.player, model.id, action_id))


## Why the selected model may not take `action_id` now, or "".
func _action_error(action_id: StringName) -> String:
	var model: ModelState = state.get_model(_selected_id)
	if model == null:
		return "No model selected."
	var error: String = TurnFlow.activation_error(state, model.player, model)
	if error == "":
		error = BeginActionCommand.unavailable_reason(state, model, action_id)
	return error


func is_charge_mode() -> bool:
	return _charge_mode


## Whether charge mode has worked out its plans.
func is_charge_ready() -> bool:
	return _charge_mode and _charge_task == -1


func charge_plans() -> Dictionary[int, ChargePlan]:
	return _charge_plans


func toggle_charge_mode() -> String:
	if _charge_mode:
		exit_charge_mode()
		return ""
	return enter_charge_mode()


## Charge mode for the selected model: works out the charge against every
## enemy in range on a worker thread, then labels them.
func enter_charge_mode() -> String:
	if is_busy():
		return "Wait for the move to finish."
	var error: String = _action_error(&"charge")
	if error != "":
		_hud.show_message("[color=#%s]Charge: %s[/color]" % [UiStyle.BAD_COLOUR.to_html(false), error])
		return error
	_unpin()
	_charge_mode = true
	_charge_plans = {}
	_charge_target = -1
	_clear_reach()
	_wait_for_charge_task()
	_built_plans_ready = false
	# The height field and the sight terrain are shared; build them here so
	# the worker only reads them.
	state.height_field()
	state.sight_terrain()
	_charge_task = WorkerThreadPool.add_task(_build_charges.bind(_selected_id))
	_hud.show_message("Charge mode: working out the charges…")
	_refresh_all()
	return ""


func exit_charge_mode() -> void:
	if not _charge_mode:
		return
	_charge_mode = false
	_wait_for_charge_task()
	_charge_plans = {}
	_charge_target = -1
	if _confirming == &"charge":
		_close_confirm()
	_melee_view.clear_charge_labels()
	_preview.hide_all()
	_distance_label.visible = false
	_hud.show_message("")
	_refresh_all()


## On a worker thread: only reads the state, which cannot change while
## charge mode is working (nothing is sent until it is ready).
func _build_charges(charger_id: int) -> void:
	var planner: ChargePlanner = ChargePlanner.new(state, charger_id)
	var plans: Dictionary[int, ChargePlan] = {}
	# Every enemy in range: those the charger cannot see get a "not visible" plan.
	for target: ModelState in planner.in_range():
		plans[target.id] = planner.plan(target.id)
	_built_mutex.lock()
	_built_plans = plans
	_built_plans_ready = true
	_built_mutex.unlock()


func _collect_charges() -> void:
	if _charge_task == -1 or not WorkerThreadPool.is_task_completed(_charge_task):
		return
	WorkerThreadPool.wait_for_task_completion(_charge_task)
	_charge_task = -1
	_built_mutex.lock()
	var plans: Dictionary[int, ChargePlan] = _built_plans
	_built_plans = {}
	_built_mutex.unlock()
	if not _charge_mode:
		return
	_charge_plans = plans
	_melee_view.show_charge_labels(state, plans)
	var reachable: int = 0
	var unseen: int = 0
	for plan: ChargePlan in plans.values():
		if plan.reachable():
			reachable += 1
		if plan.not_visible:
			unseen += 1
	_hud.show_message("Charge mode: %d enemies in range, %d not visible, %d reachable. Hover one to see the path, click to charge. Esc leaves." % [
		plans.size(), unseen, reachable
	])


func _wait_for_charge_task() -> void:
	if _charge_task != -1:
		WorkerThreadPool.wait_for_task_completion(_charge_task)
		_charge_task = -1
		_built_plans = {}


## Charge mode: clicking an enemy asks to confirm the charge against it.
func request_charge(target_id: int) -> String:
	if not _charge_mode or _charge_task != -1:
		return "Not in charge mode."
	if not _charge_plans.has(target_id):
		_hud.show_message("Model %d cannot be charged: it is not an enemy within 12\" ." % target_id)
		return "Not a target."
	var plan: ChargePlan = _charge_plans[target_id]
	if not plan.reachable():
		_hud.show_message("[color=#%s]%s[/color]" % [UiStyle.BAD_COLOUR.to_html(false), plan.error])
		return plan.error
	_charge_target = target_id
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Charge model %d?[/b]" % target_id)
	if plan.interposed():
		lines.append("[color=#%s]Model %d is in the way: the charge is against model %d instead.[/color]" % [
			UiStyle.GOLD_COLOUR.to_html(false), plan.interposers[0], plan.target_id
		])
	var model: ModelState = state.get_model(_selected_id)
	lines.append("%.1f\" to base contact; Movement %s\" + D6 (%s)." % [plan.length, str(model.movement), plan.label()])
	lines.append("The D6 is rolled once it is declared; the declaration stands whatever the roll.")
	_ask_confirm(&"charge", "\n".join(lines))
	return ""


## Declares the charge waiting for confirmation: the D6 rolls in the tray.
func confirm_charge() -> String:
	if _charge_target == -1:
		return "No charge to confirm."
	var model: ModelState = state.get_model(_selected_id)
	var target: int = _charge_target
	_close_confirm()
	exit_charge_mode()
	return send(BeginActionCommand.new(model.player, model.id, &"charge", target))


func _contact_pending() -> bool:
	return state.pending != null and state.pending.kind == PendingDecision.Kind.CHARGE_CONTACT


## Answers the contact choice: the charger ends at position `index`.
func choose_contact(index: int) -> String:
	if not _contact_pending():
		return "No contact to choose."
	return send(ChooseContactCommand.new(state.pending.player, index))


## Retreat (R or the button): lists the free attacks and asks to confirm.
func request_retreat() -> String:
	if is_busy():
		return "Wait for the move to finish."
	var error: String = _action_error(&"retreat")
	if error != "":
		_hud.show_message("[color=#%s]Retreat: %s[/color]" % [UiStyle.BAD_COLOUR.to_html(false), error])
		return error
	var model: ModelState = state.get_model(_selected_id)
	var enemies: Array[int] = MeleeZone.enemy_ids_within(state, model)
	var names: PackedStringArray = PackedStringArray()
	for id: int in enemies:
		names.append("model %d" % id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Retreat model %d?[/b]" % model.id)
	lines.append("Free attacks first: %s%s." % [
		", ".join(names), " (%s picks the order)" % UiStyle.player_bb(1 - model.player) if enemies.size() > 1 else ""
	])
	lines.append("Then it moves up to %.1f\" and must end more than 1\" from every enemy." % TurnFlow.movement_budget(state, model))
	_ask_confirm(&"retreat", "\n".join(lines))
	return ""


func confirm_retreat() -> String:
	_close_confirm()
	var model: ModelState = state.get_model(_selected_id)
	if model == null:
		return "No model selected."
	return send(BeginActionCommand.new(model.player, model.id, &"retreat"))


## FREE_ATTACK_ORDER: the enemy player picks the next attacker; once every
## attacker is picked the order is sent.
func pick_attacker(attacker_id: int) -> String:
	var pending: PendingDecision = state.pending
	if pending == null or pending.kind != PendingDecision.Kind.FREE_ATTACK_ORDER:
		return "No order to pick."
	if _attack_order.has(attacker_id) or not pending.model_ids.has(attacker_id):
		return "Not an attacker left to pick."
	_attack_order.append(attacker_id)
	if _attack_order.size() < pending.model_ids.size():
		_refresh_all()
		return ""
	var order: Array[int] = _attack_order.duplicate()
	_attack_order.clear()
	return send(ChooseAttackOrderCommand.new(pending.player, order))


func end_activation() -> String:
	var model: ModelState = state.get_model(_selected_id)
	if model == null or is_busy():
		return "No model selected."
	return send(EndActivationCommand.new(model.player, model.id))


func stay() -> String:
	if state.pending == null:
		return "Nothing to decline."
	return send(DeclineMoveCommand.new(state.pending.player))


func choose_first_player(first: int) -> String:
	if state.pending == null:
		return "Nothing to choose."
	return send(ChooseFirstPlayerCommand.new(state.pending.player, first))


func roll_off() -> String:
	return send(RollOffCommand.new(0))


func answer_roll_choice(amounts: Array[int]) -> String:
	if state.pending == null:
		return "Nothing to answer."
	return send(RollChoiceCommand.new(state.pending.player, 0, amounts))


## Takes the last step back (not a rule command: core restores its snapshot).
## The views are brought back in line with the restored state.
func undo() -> String:
	if _tray.is_animating():
		_tray.skip()
	if is_busy():
		return "Wait for the move to finish."
	_wait_for_reach_task()
	if not state.undo():
		_hud.show_message("Nothing to undo.")
		return "Nothing to undo."
	_state_changed()
	_after_restore("Undone.")
	return ""


## Does the last undone step again; it plays back like any command.
func redo() -> String:
	if _tray.is_animating():
		_tray.skip()
	if is_busy():
		return "Wait for the move to finish."
	_wait_for_reach_task()
	if not state.can_redo():
		_hud.show_message("Nothing to redo.")
		return "Nothing to redo."
	var result: CommandResult = state.redo()
	_state_changed()
	if not result.ok():
		_hud.show_message(result.error)
		return result.error
	_hud.show_message("Redone.")
	_queue.append_array(result.events)
	_pump()
	return ""


func _after_restore(message: String) -> void:
	_sight_cache.clear()
	_unpin()
	_close_confirm()
	exit_charge_mode()
	_attack_order.clear()
	_clear_reach()
	_tray.close()
	# A restored roll waiting on a marker prompt shows it again.
	var pending: PendingDecision = state.pending
	if state.active_roll != null:
		_tray.begin(state.active_roll)
		if pending != null and pending.kind == PendingDecision.Kind.ROLL_CHOICE:
			_tray.ask_choice(pending)
	_hud.show_message(message)
	_refresh_all()


func _wait_for_reach_task() -> void:
	if _reach_task != -1:
		WorkerThreadPool.wait_for_task_completion(_reach_task)
		_reach_task = -1
		_built_field = null


## The selected model's descent mode (how drops of 3" or more are taken).
func descent_mode() -> Transitions.DescentMode:
	return _descent.get(_selected_id, Transitions.DescentMode.DROP)


## Switches the selected model between Drop and Climb down and redraws its area.
func toggle_descent_mode() -> void:
	if _selected_id == -1 or is_busy():
		return
	var mode: Transitions.DescentMode = Transitions.DescentMode.CLIMB_DOWN
	if descent_mode() == Transitions.DescentMode.CLIMB_DOWN:
		mode = Transitions.DescentMode.DROP
	_descent[_selected_id] = mode
	_hud.show_message("Descent: %s" % _descent_name(mode))
	_refresh_all()


static func _descent_name(mode: Transitions.DescentMode) -> String:
	return "Climb down" if mode == Transitions.DescentMode.CLIMB_DOWN else "Drop"


## The state changed: built reach fields no longer hold, and the status line
## shows what core waits for now (even while events still play back).
func _state_changed() -> void:
	_reach_cache.clear()
	_sight_cache.clear()
	_attack_order.clear()
	_hud.refresh_status(state)


func toggle_overrides() -> void:
	_overrides.visible = not _overrides.visible
	_refresh_all()


## The UI pieces, for scripted runs that press their buttons.
func hud() -> Hud:
	return _hud


func tray() -> DiceTray:
	return _tray


func override_panel() -> OverridePanel:
	return _overrides


## Whether the selected model's reach field is ready (it is built in the background).
func is_reach_ready() -> bool:
	return _selected_id != -1 and _reach != null and _reach.model_id == _selected_id and _reach_task == -1


## Whether the selected model shows a movement indicator.
func has_move_preview() -> bool:
	return _reach_key != ""


## Where a click on `point` (on a floor) would send the selected model, or null.
func destination_for(point: Vector3) -> Variant:
	return _destination_for(point)


## Scripted hover for screenshots: a 3D point on a floor, or null to follow the mouse again.
func set_hover_override(point: Variant) -> void:
	_hover_override = point


func _pump() -> void:
	while not _playing and not _queue.is_empty():
		var event: GameEvent = _queue.pop_front()
		event_log.append(event)
		print("event: ", event.describe())
		_play(event)
	if not _playing and _queue.is_empty():
		_refresh_all()


func _resume() -> void:
	_playing = false
	_pump()


func _play(event: GameEvent) -> void:
	match event.kind:
		GameEvent.Kind.TURN_STARTED:
			_hud.show_message("Turn %d begins." % event.data["turn"])
		GameEvent.Kind.FIRST_PLAYER_CHOSEN:
			_hud.show_message("%s activates first." % UiStyle.player_bb(event.player))
		GameEvent.Kind.ACTIVATION_STARTED:
			_tray.close()
			if _selected_id != event.model_id:
				select_model(event.model_id)
		GameEvent.Kind.MODEL_STOOD_UP:
			_hud.show_message("Model %d stands up: half movement this activation." % event.model_id)
		GameEvent.Kind.ROLL_REQUESTED:
			_tray.begin(event.roll)
		GameEvent.Kind.ROLL_CHOICE_MADE:
			_tray.add_choice(event)
		GameEvent.Kind.DECISION_NEEDED:
			_on_decision(event.decision)
		GameEvent.Kind.ROLL_RESOLVED:
			_playing = true
			_tray.show_result(event.result, _resume)
		GameEvent.Kind.MODEL_MOVED:
			_play_move(event)
		GameEvent.Kind.MODEL_FELL:
			_play_fall(event)
		GameEvent.Kind.MOVE_ROLL_POINT:
			_hud.show_message("Model %d: %s" % [event.model_id, event.data.get("roll", "")])
		GameEvent.Kind.INJURY_APPLIED:
			_tray.show_effect(String(event.data.get("short", "")))
			_hud.show_message(String(event.data.get("text", "")))
		GameEvent.Kind.MODEL_WENT_DOWN:
			_views[event.model_id].sync(state.get_model(event.model_id))
		GameEvent.Kind.MODEL_OUT_OF_ACTION:
			_views[event.model_id].visible = false
			if _selected_id == event.model_id:
				deselect()
		GameEvent.Kind.MARKERS_GAINED:
			_hud.show_message("Model %d: %s (+%d)" % [event.model_id, event.data.get("reason", ""), int(event.data.get("count", 0))])
		GameEvent.Kind.MOVE_STOPPED:
			_hud.show_message("Model %d's move stops: %s." % [event.model_id, event.data.get("reason", "")])
		GameEvent.Kind.ACTIVATION_ENDED:
			var reason: String = event.data.get("reason", "")
			if reason in ["failed risky roll", "went Down", "taken Out of Action"]:
				_tray.note_activation_ended()
				_hud.show_message("Model %d %s: its activation ends." % [
					event.model_id, "failed a risky roll" if reason == "failed risky roll" else reason
				])
		GameEvent.Kind.OVERRIDE_APPLIED:
			_hud.show_message("Override: %s" % event.data.get("text", ""))
		GameEvent.Kind.CHARGE_DECLARED:
			var text: String = "Model %d charges model %d." % [event.model_id, int(event.data["target_id"])]
			if event.data.get("interposed", false):
				text = "Model %d charges model %d (in the way of model %d)." % [
					event.model_id, int(event.data["target_id"]), int(event.data["declared_id"])
				]
			_hud.show_message(text)
		GameEvent.Kind.CHARGE_DISTANCE:
			var reaches: bool = event.data["reaches"]
			_tray.show_effect("%s %.1f\" of %.1f\" needed" % [
				"Charge reaches:" if reaches else "Charge falls short:", float(event.data["distance"]), float(event.data["length"])
			])
		GameEvent.Kind.CHARGE_FAILED:
			_tray.show_effect("Charge failed: %.1f\" of %.1f\"" % [float(event.data["distance"]), float(event.data["length"])])
			_hud.show_message("Model %d's charge falls short; it stops outside every enemy's 1\" zone." % event.model_id)
		GameEvent.Kind.CHARGED:
			var charged: Array = event.data["charged"]
			_hud.show_message("Model %d is in melee: charged %s." % [
				event.model_id, ", ".join(charged.map(func(id: int) -> String: return "model %d" % id))
			])
		GameEvent.Kind.RETREAT_STARTED:
			_free_attack_lines.clear()
			_hud.show_message("Model %d retreats." % event.model_id)
		GameEvent.Kind.FREE_ATTACK:
			_free_attack_lines.append("Model %d makes a free melee attack against model %d." % [
				event.model_id, int(event.data["target_id"])
			])
			var lines: PackedStringArray = _free_attack_lines.duplicate()
			if event.data.get("temporary", false):
				lines.append("[color=#%s](Temporary: attacks are not in the game yet.)[/color]" % UiStyle.DIM_COLOUR.to_html(false))
			_tray.show_notes("Free attacks", lines)
			_playing = true
			get_tree().create_timer(0.7).timeout.connect(_resume)
		GameEvent.Kind.PLAYER_TO_ACT:
			pass


func _on_decision(decision: PendingDecision) -> void:
	match decision.kind:
		PendingDecision.Kind.ROLL_CHOICE:
			_tray.ask_choice(decision)
		PendingDecision.Kind.MOVE:
			if _selected_id != decision.model_id:
				select_model(decision.model_id)
		PendingDecision.Kind.CHARGE_CONTACT:
			if _selected_id != decision.model_id:
				select_model(decision.model_id)
			_hud.show_message("Click a spot on the arc to end the charge there (Enter keeps first contact).")
		PendingDecision.Kind.FREE_ATTACK_ORDER:
			_attack_order.clear()


func _play_move(event: GameEvent) -> void:
	var raw: Array = event.data["path"]
	var path: Array[Vector3] = []
	for point: Vector3 in raw:
		path.append(point)
	var shown: Array[Vector3] = _shown_path(path, event.data.get("kinds", []))
	_clear_reach()
	_playing = true
	var end: Vector3 = path[path.size() - 1]
	_views[event.model_id].slide_along(shown, func() -> void:
		_views[event.model_id].place_at(end)
		_resume()
	)


## A failed jump: up the arc to over the gap, straight down, and over to
## where it can stop.
func _play_fall(event: GameEvent) -> void:
	var from: Vector3 = event.data["from"]
	var over: Vector3 = event.data["over"]
	var to: Vector3 = event.data["to"]
	var shown: Array[Vector3] = [from]
	var far: Vector3 = from + (over - from) * 2.0
	shown.append_array(ModelView.jump_arc(from, far, true))
	shown.append(Vector3(over.x, to.y, over.z))
	shown.append(to)
	_hud.show_message("Model %d falls %.1f\"." % [event.model_id, float(event.data["height"])])
	_clear_reach()
	_playing = true
	_views[event.model_id].slide_along(shown, func() -> void:
		_views[event.model_id].place_at(to)
		_resume()
	)


## A path as it is drawn and played, from its points (start first) and how
## each segment is taken: climbs straight up or down the wall at the touch
## point, drops off the edge then straight down, jumps along an arc.
func _shown_path(path: Array[Vector3], kinds: Array) -> Array[Vector3]:
	var shown: Array[Vector3] = [path[0]]
	for i: int in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var kind: Transitions.Kind = kinds[i - 1] if i - 1 < kinds.size() else Transitions.Kind.WALK
		match kind:
			Transitions.Kind.GAP_JUMP:
				shown.append_array(ModelView.jump_arc(a, b))
			Transitions.Kind.WALK, Transitions.Kind.NONE:
				shown.append(b)
			_:
				if b.y > a.y:
					shown.append(Vector3(a.x, b.y, a.z))
				else:
					shown.append(Vector3(b.x, a.y, b.z))
				shown.append(b)
	return shown


## Brings every view in line with the state once the events are played.
## Skipped while events are still playing, so nothing shows ahead of them.
func _refresh_all() -> void:
	if _hud == null or is_busy():
		return
	for model: ModelState in state.models:
		var view: ModelView = _views[model.id]
		view.sync(model)
		view.show_status(model, state.turn.has_activated(model.id), state.turn.active_model_id == model.id, MeleeZone.in_melee(state, model))
	_hud.refresh(state, _selected_id, descent_mode(), _attack_order, _charge_mode)
	_hud.show_sight_toggles(_sight_overview, _sight_debug)
	_overrides.refresh(state, _selected_id)
	_refresh_reach()
	_refresh_melee()
	_refresh_sight()


## Melee links, enemy zones while a model is selected to move or charge, and
## the contact arc while a contact is to be chosen.
func _refresh_melee() -> void:
	_melee_view.show_links(state)
	var selected: ModelState = state.get_model(_selected_id)
	var moving: bool = selected != null and (_reach_key != "" or _charge_mode or _contact_pending())
	_melee_view.show_zones(state, selected if moving else null)
	if _contact_pending():
		_melee_view.show_contact_arc(state.pending.positions)
	else:
		_melee_view.clear_contact_arc()
		_set_contact_hover(-1)


func _move_pending_for(id: int) -> bool:
	var pending: PendingDecision = state.pending
	return pending != null and pending.kind == PendingDecision.Kind.MOVE and pending.model_id == id


## How far the selected model could move now: the pending move's budget, or
## what the Move action would give if it may take it, else -1.
func _move_budget(id: int) -> float:
	var model: ModelState = state.get_model(id)
	if model == null:
		return -1.0
	if _move_pending_for(id):
		return state.pending.budget
	if TurnFlow.activation_error(state, model.player, model) != "":
		return -1.0
	if BeginActionCommand.unavailable_reason(state, model, CLICK_ACTION) != "":
		return -1.0
	return state.rules.action(CLICK_ACTION).behaviour.move_budget_preview(state, model)


func _refresh_reach() -> void:
	var budget: float = _move_budget(_selected_id) if _selected_id != -1 and not _charge_mode else -1.0
	if budget < 0.0:
		_clear_reach()
		return
	var model: ModelState = state.get_model(_selected_id)
	var mode: Transitions.DescentMode = descent_mode()
	var zones: EnemyZones = state.pending.zones if _move_pending_for(_selected_id) else null
	var key: String = "%d|%.3f|%s|%d|%s" % [_selected_id, budget, str(model.position), mode, zones.describe() if zones != null else ""]
	if key == _reach_key:
		return
	_clear_reach()
	_reach_key = key
	if _reach_cache.has(key):
		var cached: Array = _reach_cache[key]
		_reach = cached[0]
		_indicator.mesh = cached[2]
		print("Reach field for model %d (%.1f\", %s): from the cache" % [_selected_id, budget, _descent_name(mode)])
		return
	if _reach_task != -1:
		# A stale build: let it finish, its result is dropped in _collect_reach().
		WorkerThreadPool.wait_for_task_completion(_reach_task)
		_reach_task = -1
	_built_field = null
	# The height field is shared; build it here so the worker only reads it.
	state.height_field()
	_reach_task_key = key
	_reach_started_usec = Time.get_ticks_usec()
	_reach_task = WorkerThreadPool.add_task(_build_reach.bind(_selected_id, budget, mode, zones))


func _clear_reach() -> void:
	_unpin()
	_reach = null
	_reach_key = ""
	_indicator.show_field(null)
	_preview.hide_all()
	_distance_label.visible = false


## On a worker thread: only reads positions and terrain, which do not change
## while a field is being built (nothing can move without one).
func _build_reach(id: int, budget: float, mode: Transitions.DescentMode, zones: EnemyZones = null) -> void:
	var field: ReachField = ReachField.new(state, id, budget, ReachField.CELL_SIZE, mode, zones)
	var layers: Array[ReachField.Layer] = field.contour_layers()
	_built_mutex.lock()
	_built_field = field
	_built_layers = layers
	_built_mutex.unlock()


func _collect_reach() -> void:
	if _reach_task == -1 or not WorkerThreadPool.is_task_completed(_reach_task):
		return
	WorkerThreadPool.wait_for_task_completion(_reach_task)
	_reach_task = -1
	_built_mutex.lock()
	var field: ReachField = _built_field
	var layers: Array[ReachField.Layer] = _built_layers
	_built_field = null
	_built_mutex.unlock()
	if field == null or _reach_task_key != _reach_key:
		return
	var computed: int = Time.get_ticks_usec()
	_reach = field
	_indicator.show_field(field, layers)
	_reach_cache[_reach_key] = [field, layers, _indicator.mesh]
	print("Reach field for model %d (%.1f\", %s): %d states, %.1f ms on a worker, indicator mesh %.1f ms" % [
		field.model_id, field.budget, _descent_name(field.descent_mode), field.state_count(),
		(computed - _reach_started_usec) / 1000.0, (Time.get_ticks_usec() - computed) / 1000.0
	])


func _on_left_click(screen_position: Vector2) -> void:
	var picked: int = _pick_model(screen_position)
	if _charge_mode:
		if picked != -1 and state.get_model(picked).player != state.get_model(_selected_id).player:
			request_charge(picked)
		elif picked == _selected_id:
			pass
		else:
			exit_charge_mode()
			if picked != -1:
				select_model(picked)
		return
	if _contact_pending():
		if _contact_hover != -1:
			choose_contact(_contact_hover)
		else:
			_hud.show_message("Click a spot on the arc around the target (Enter keeps first contact).")
		return
	if picked != -1:
		select_model(picked)
		return
	if _selected_id == -1:
		return
	if _reach == null:
		deselect()
		return
	var destination: Variant = _destination_for(_floor_point(screen_position))
	if destination != null:
		request_move_to(destination)
	elif _pinned != null:
		cancel_pinned()
	else:
		deselect()


func _update_hover() -> void:
	if _selected_id == -1 or is_busy():
		return
	if _charge_mode:
		_update_charge_hover()
		return
	if _contact_pending():
		_update_contact_hover()
		return
	if _update_sight_hover():
		return
	if _reach == null:
		return
	var point: Variant = _hover_override
	if _pinned != null:
		point = _pinned
	elif point == null:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		if _pick_model(mouse) != -1 or _over_ui(mouse):
			_preview.hide_all()
			_distance_label.visible = false
			return
		point = _floor_point(mouse)
	if point == null:
		_preview.hide_all()
		_distance_label.visible = false
		return
	var target: Vector3 = point
	var model: ModelState = state.get_model(_selected_id)
	var path: Array[Vector3] = []
	var destination: Variant = _destination_for(point)
	if destination != null:
		target = destination
		path = _reach.path_to(target)
	var shown: Array[Vector3] = []
	var rolls: Array[Dictionary] = []
	if not path.is_empty():
		shown = _display_path(model.position, path)
		shown.remove_at(0)
		rolls = _reach.rolls_to(target)
	_preview.show_preview(
		model.position, shown, target, model.base_radius_inches(), _floor_normal(target), not rolls.is_empty()
	)
	var roll_points: Array[Vector3] = []
	var labels: PackedStringArray = PackedStringArray()
	for roll: Dictionary in rolls:
		roll_points.append(roll["at"])
		labels.append(String(roll["label"]))
	_preview.show_roll_points(roll_points)
	if path.is_empty():
		_distance_label.visible = false
		return
	var cost: float = _reach.cost_to(target)
	var surcharge: float = _reach.surcharge_at(target)
	_distance_label.text = "%.1f\" of %.1f\"" % [cost, _reach.budget]
	if surcharge > 0.0:
		_distance_label.text += "  (incl. %.1f\" to stop on the obstacle)" % surcharge
	if not labels.is_empty():
		_distance_label.text = "  -  ".join(labels) + "\n" + _distance_label.text
		if _pinned == null:
			_distance_label.text += "   (click to confirm)"
	_distance_label.position = _camera.unproject_position(target) + Vector2(18, -34)
	_distance_label.visible = true


## Charge mode: the charge path to the enemy under the cursor (or the
## scripted hover point), with what it needs.
func _update_charge_hover() -> void:
	var target: int = -1
	if _confirming == &"charge":
		target = _charge_target
	elif _hover_override != null:
		target = _model_near(_hover_override)
	else:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		if not _over_ui(mouse):
			target = _pick_model(mouse)
	if target == -1 or not _charge_plans.has(target):
		_preview.hide_all()
		_distance_label.visible = false
		return
	var plan: ChargePlan = _charge_plans[target]
	var model: ModelState = state.get_model(_selected_id)
	if not plan.reachable():
		_preview.hide_all()
		_distance_label.text = "Model %d: %s" % [target, plan.label()]
	else:
		var shown: Array[Vector3] = _charge_display_path(model, plan.path)
		shown.remove_at(0)
		_preview.show_preview(model.position, shown, plan.contact(), model.base_radius_inches(), Vector3.UP, not plan.is_certain())
		_preview.show_roll_points([] as Array[Vector3])
		var text: String = "Charge model %d: %.1f\" - %s" % [target, plan.length, plan.label()]
		if plan.interposed():
			text = "Model %d is in the way of model %d: charges it instead\n%.1f\" - %s" % [plan.interposers[0], target, plan.length, plan.label()]
		_distance_label.text = text
	_distance_label.position = _camera.unproject_position(state.get_model(target).position) + Vector2(18, -60)
	_distance_label.visible = true


## A charge path as drawn: climbs straight up and down (see _shown_path()).
func _charge_display_path(model: ModelState, path: Array[Vector3]) -> Array[Vector3]:
	var legality: MoveLegality = ChargePlanner.legality_for(state, model)
	var points: Array[Vector3] = [model.position]
	points.append_array(path)
	var kinds: Array = []
	for i: int in range(1, points.size()):
		legality.segment_cost(points[i - 1], points[i])
		kinds.append(legality.last_kind)
	return _shown_path(points, kinds)


## The contact choice: the arc position nearest the cursor, the base it
## would have there, and the enemies it would count as charging.
func _update_contact_hover() -> void:
	var decision: PendingDecision = state.pending
	var point: Variant = _hover_override
	if point == null:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		point = null if _over_ui(mouse) else _floor_point(mouse)
	var best: int = -1
	if point != null:
		var at: Vector3 = point
		var best_distance: float = 0.8
		for i: int in decision.positions.size():
			var d: float = Vector2(at.x, at.z).distance_to(Vector2(decision.positions[i].x, decision.positions[i].z))
			if d < best_distance:
				best_distance = d
				best = i
	_set_contact_hover(best)


func _set_contact_hover(index: int) -> void:
	if index == _contact_hover:
		return
	_contact_hover = index
	for view: ModelView in _views.values():
		view.set_highlighted(false)
	if index == -1 or not _contact_pending():
		_melee_view.show_contact_hover(null, 0.0)
		_distance_label.visible = false
		return
	var decision: PendingDecision = state.pending
	var model: ModelState = state.get_model(decision.model_id)
	_melee_view.show_contact_hover(decision.positions[index], model.base_radius_inches())
	var charged: Array = decision.charged_ids[index]
	for id: int in charged:
		_views[id].set_highlighted(true)
	_distance_label.text = "Ends here: charges %s%s" % [
		", ".join(charged.map(func(id: int) -> String: return "model %d" % id)),
		"  (first contact)" if index == decision.default_index else ""
	]
	_distance_label.position = _camera.unproject_position(decision.positions[index]) + Vector2(18, -34)
	_distance_label.visible = true


## The contact position under the cursor, or -1 (for scripted checks).
func contact_hover() -> int:
	return _contact_hover


# --- Sight (brief 008) -----------------------------------------------------


## Whether `viewer_id` can see `target_id` now, with the clear segment: from
## core, kept until the state changes.
func sight(viewer_id: int, target_id: int) -> SightResult:
	var key: String = "%d>%d" % [viewer_id, target_id]
	var cached: SightResult = _sight_cache.get(key)
	if cached != null:
		return cached
	var result: SightResult = state.rules.sight.check(state, state.get_model(viewer_id), state.get_model(target_id))
	_sight_cache[key] = result
	return result


func is_sight_overview() -> bool:
	return _sight_overview


func is_sight_debug() -> bool:
	return _sight_debug


func toggle_sight_overview() -> void:
	_sight_overview = not _sight_overview
	_hud.show_message("Sight overview %s." % ("on: green rings mark the enemies the selected model can see" if _sight_overview else "off"))
	_refresh_all()


func toggle_sight_debug() -> void:
	_sight_debug = not _sight_debug
	_refresh_all()


## The enemy whose sight is shown on hover, or -1 (for scripted checks).
func sight_hover() -> int:
	return _sight_hover


func sight_view() -> SightView:
	return _sight_view


## The enemies of `viewer` on the table that it can and cannot see.
func _enemies_by_sight(viewer: ModelState) -> Array:
	var seen: Array[int] = []
	var unseen: Array[int] = []
	for model: ModelState in state.models_on_table():
		if model.player == viewer.player:
			continue
		if sight(viewer.id, model.id).visible:
			seen.append(model.id)
		else:
			unseen.append(model.id)
	return [seen, unseen]


## The overview's hidden enemies of the selected model (empty when it is off).
func _overview_unseen() -> Array[int]:
	var selected: ModelState = state.get_model(_selected_id)
	if not _sight_overview or selected == null or not selected.on_table() or _charge_mode:
		return [] as Array[int]
	return _enemies_by_sight(selected)[1]


## The overview marks, the dimming and the debug cylinders, from the state.
func _refresh_sight() -> void:
	if _sight_view == null:
		return
	var selected: ModelState = state.get_model(_selected_id)
	var seen: Array[int] = []
	var unseen: Array[int] = []
	if _sight_overview and selected != null and selected.on_table() and not _charge_mode:
		var split: Array = _enemies_by_sight(selected)
		seen = split[0]
		unseen = split[1]
	for id: int in _views:
		_views[id].set_dimmed(unseen.has(id))
	_sight_view.show_seen(state, seen)
	_show_not_visible_labels(unseen)
	if _sight_debug:
		var cylinders: Array[SightCylinder] = []
		for model: ModelState in state.models_on_table():
			cylinders.append(SightCylinder.for_model(state, model))
		_sight_view.show_cylinders(cylinders)
	else:
		_sight_view.hide_cylinders()


## "not visible" over the overview's hidden enemies plus the hovered one.
func _show_not_visible_labels(unseen: Array[int]) -> void:
	var ids: Array[int] = unseen.duplicate()
	if _sight_hover != -1 and _selected_id != -1 and not _charge_mode and not ids.has(_sight_hover) and not sight(_selected_id, _sight_hover).visible:
		ids.append(_sight_hover)
	_sight_view.show_not_visible(state, ids)


## With a model selected (not charging), hovering an enemy shows the sight
## line to it or marks it not visible. Returns whether an enemy is hovered
## (the move preview then stays hidden).
func _update_sight_hover() -> bool:
	var selected: ModelState = state.get_model(_selected_id)
	var target: int = -1
	if _pinned == null and _hover_override == null and selected != null and selected.on_table():
		var mouse: Vector2 = get_viewport().get_mouse_position()
		if not _over_ui(mouse):
			var picked: int = _pick_model(mouse)
			if picked != -1 and state.get_model(picked).player != selected.player:
				target = picked
	if target != _sight_hover:
		_sight_hover = target
		_show_not_visible_labels(_overview_unseen())
	if target == -1:
		_sight_view.hide_line()
		return false
	_preview.hide_all()
	var result: SightResult = sight(_selected_id, target)
	if result.visible:
		_sight_view.show_line(result.from, result.to)
		_distance_label.text = "Model %d: visible" % target
	else:
		_sight_view.hide_line()
		_distance_label.text = "Model %d: not visible" % target
	_distance_label.position = _camera.unproject_position(state.get_model(target).position) + Vector2(18, -60)
	_distance_label.visible = true
	return true


## The model whose base is nearest a table point (within 2"), or -1.
func _model_near(point: Vector3) -> int:
	var best: int = -1
	var best_distance: float = 2.0
	for model: ModelState in state.models_on_table():
		var d: float = Vector2(point.x, point.z).distance_to(Vector2(model.position.x, model.position.z))
		if d < best_distance:
			best_distance = d
			best = model.id
	return best


func _over_ui(screen_position: Vector2) -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP and hovered.get_global_rect().has_point(screen_position)


## The path as it is drawn in the preview: see _shown_path(), with the kinds
## of its segments from the reach field.
func _display_path(start: Vector3, path: Array[Vector3]) -> Array[Vector3]:
	var points: Array[Vector3] = [start]
	points.append_array(path)
	var kinds: Array = []
	for i: int in range(1, points.size()):
		kinds.append(_reach.segment_kind(points[i - 1], points[i]))
	return _shown_path(points, kinds)


## Up direction of the floor a destination is on: the tilt core gives a
## model standing there (SightCylinder.tilt_at()).
func _floor_normal(point: Vector3) -> Vector3:
	return SightCylinder.tilt_at(state, point)


## Where the selected model's centre goes for a point on a floor: the closest
## valid centre within a base radius, since the indicator shows where the base
## edge can reach. Null if there is none (or `point` is null).
func _destination_for(point: Variant) -> Variant:
	if point == null or _reach == null:
		return null
	return _reach.closest_destination(point, _reach.base_radius())


## The model under the screen position, or -1. Terrain in front hides it.
func _pick_model(screen_position: Vector2) -> int:
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var best_id: int = -1
	var best_t: float = INF
	for id: int in _views:
		var t: float = _views[id].ray_hit_distance(origin, direction)
		if t < best_t:
			best_t = t
			best_id = id
	var hit: TerrainPicker.Hit = TerrainPicker.pick(state, origin, direction)
	if hit != null and hit.distance < best_t:
		return -1
	return best_id


## The point on the table or terrain the screen position points at, or null.
func _floor_point(screen_position: Variant) -> Variant:
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var hit: TerrainPicker.Hit = TerrainPicker.pick(state, origin, direction)
	return hit.point if hit != null else null


func _build_table() -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(state.table_width, TABLE_THICKNESS, state.table_depth)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.31, 0.24)
	var table: MeshInstance3D = MeshInstance3D.new()
	table.name = "TableTop"
	table.mesh = box
	table.material_override = material
	# Top face at y = 0; the table spans x in [0, width] and z in [0, depth].
	table.position = Vector3(state.table_width / 2.0, -TABLE_THICKNESS / 2.0, state.table_depth / 2.0)
	_table_root.add_child(table)


func _build_terrain_views() -> void:
	for piece: TerrainPiece in state.terrain:
		var view: TerrainView = TerrainView.new()
		view.setup(piece)
		_table_root.add_child(view)


func _build_model_views() -> void:
	for model: ModelState in state.models:
		var view: ModelView = ModelView.new()
		view.state = state
		view.setup(model)
		_models_root.add_child(view)
		_views[model.id] = view


func _build_overlays() -> void:
	_indicator = MovementIndicator.new()
	add_child(_indicator)
	_preview = PathPreview.new()
	add_child(_preview)
	_melee_view = MeleeView.new()
	add_child(_melee_view)
	_sight_view = SightView.new()
	add_child(_sight_view)

	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Ui"
	add_child(layer)
	_distance_label = Label.new()
	_distance_label.name = "DistanceLabel"
	_distance_label.add_theme_font_size_override("font_size", 22)
	_distance_label.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	_distance_label.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.12))
	_distance_label.add_theme_constant_override("outline_size", 6)
	_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_distance_label.visible = false
	layer.add_child(_distance_label)

	_hud = Hud.new()
	layer.add_child(_hud)
	_hud.action_pressed.connect(func(id: StringName) -> void: take_action(id))
	_hud.end_activation_pressed.connect(func() -> void: end_activation())
	_hud.stay_pressed.connect(func() -> void: stay())
	_hud.first_player_chosen.connect(func(first: int) -> void: choose_first_player(first))
	_hud.roll_off_pressed.connect(func() -> void: roll_off())
	_hud.undo_pressed.connect(func() -> void: undo())
	_hud.redo_pressed.connect(func() -> void: redo())
	_hud.descent_pressed.connect(func() -> void: toggle_descent_mode())
	_hud.attacker_picked.connect(func(id: int) -> void: pick_attacker(id))
	_hud.sight_overview_pressed.connect(func() -> void: toggle_sight_overview())
	_hud.sight_debug_pressed.connect(func() -> void: toggle_sight_debug())

	_tray = DiceTray.new()
	_tray.custom_minimum_size = Vector2(TRAY_WIDTH, 0)
	_tray.choice_answered.connect(func(amounts: Array[int]) -> void: answer_roll_choice(amounts))
	layer.add_child(_tray)

	_confirm_panel = PanelContainer.new()
	_confirm_panel.name = "ConfirmMove"
	_confirm_panel.add_theme_stylebox_override("panel", UiStyle.panel(Color(1.0, 0.55, 0.15)))
	var confirm_box: VBoxContainer = VBoxContainer.new()
	_confirm_panel.add_child(confirm_box)
	_confirm_label = UiStyle.rich(17)
	_confirm_label.custom_minimum_size = Vector2(460, 0)
	confirm_box.add_child(_confirm_label)
	var confirm_row: HBoxContainer = HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 8)
	confirm_box.add_child(confirm_row)
	var confirm: Button = UiStyle.button("Confirm (Enter)", "ConfirmMoveButton")
	confirm.pressed.connect(func() -> void: confirm())
	confirm_row.add_child(confirm)
	var cancel: Button = UiStyle.button("Cancel (Esc)", "CancelMoveButton")
	cancel.pressed.connect(func() -> void: cancel_confirm())
	confirm_row.add_child(cancel)
	_confirm_panel.visible = false
	layer.add_child(_confirm_panel)

	_overrides = OverridePanel.new()
	_overrides.send = func(command: Command) -> void: send(command)
	layer.add_child(_overrides)
