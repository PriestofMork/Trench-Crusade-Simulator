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
			if _pinned != null:
				confirm_pinned()
		elif key.physical_keycode == KEY_ESCAPE:
			if _pinned != null:
				cancel_pinned()
			else:
				deselect()
		elif key.physical_keycode == KEY_C and not key.ctrl_pressed:
			toggle_descent_mode()
		elif key.physical_keycode == KEY_O:
			toggle_overrides()


func _process(_delta: float) -> void:
	_collect_reach()
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
	if _selected_id != -1 and _views.has(_selected_id):
		_views[_selected_id].set_selected(false)
	_selected_id = id
	_views[id].set_selected(true)
	_refresh_all()


func deselect() -> void:
	if _selected_id != -1 and _views.has(_selected_id):
		_views[_selected_id].set_selected(false)
	_selected_id = -1
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


func _pin(point: Vector3) -> void:
	_pinned = point
	var labels: PackedStringArray = PackedStringArray()
	for roll: Dictionary in _reach.rolls_to(point):
		labels.append(String(roll["label"]))
	_confirm_label.text = "[b]This move needs rolls[/b]\n%s\n%.1f\" of %.1f\"" % [
		"  -  ".join(labels), _reach.cost_to(point), _reach.budget
	]
	_confirm_panel.visible = true


func _unpin() -> void:
	_pinned = null
	if _confirm_panel != null:
		_confirm_panel.visible = false


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
func take_action(action_id: StringName) -> String:
	var model: ModelState = state.get_model(_selected_id)
	if model == null or is_busy():
		return "No model selected."
	return send(BeginActionCommand.new(model.player, model.id, action_id))


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
	_unpin()
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
		GameEvent.Kind.PLAYER_TO_ACT:
			pass


func _on_decision(decision: PendingDecision) -> void:
	match decision.kind:
		PendingDecision.Kind.ROLL_CHOICE:
			_tray.ask_choice(decision)
		PendingDecision.Kind.MOVE:
			if _selected_id != decision.model_id:
				select_model(decision.model_id)


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
		view.show_status(model, state.turn.has_activated(model.id), state.turn.active_model_id == model.id)
	_hud.refresh(state, _selected_id, descent_mode())
	_overrides.refresh(state, _selected_id)
	_refresh_reach()


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
	var budget: float = _move_budget(_selected_id) if _selected_id != -1 else -1.0
	if budget < 0.0:
		_clear_reach()
		return
	var model: ModelState = state.get_model(_selected_id)
	var mode: Transitions.DescentMode = descent_mode()
	var key: String = "%d|%.3f|%s|%d" % [_selected_id, budget, str(model.position), mode]
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
	_reach_task = WorkerThreadPool.add_task(_build_reach.bind(_selected_id, budget, mode))


func _clear_reach() -> void:
	_unpin()
	_reach = null
	_reach_key = ""
	_indicator.show_field(null)
	_preview.hide_all()
	_distance_label.visible = false


## On a worker thread: only reads positions and terrain, which do not change
## while a field is being built (nothing can move without one).
func _build_reach(id: int, budget: float, mode: Transitions.DescentMode) -> void:
	var field: ReachField = ReachField.new(state, id, budget, ReachField.CELL_SIZE, mode)
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
	if _selected_id == -1 or _reach == null or is_busy():
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


## Up direction of the floor under a base at `base` (for tilting the views):
## the surface at that height whose footprint the centre is deepest inside,
## level if there is none (on a wall, in the air). A base half over a ledge
## takes its own floor's tilt. Reads terrain only.
func _floor_up_at(base: Vector3) -> Vector3:
	var field: HeightField = state.height_field()
	var p: Vector2 = Vector2(base.x, base.z)
	var best: int = -1
	var best_depth: float = INF
	for s: int in field.surfaces_matching(p, base.y, 0.02):
		var depth: float = field.surfaces[s].shape.signed_distance(p)
		if depth < best_depth:
			best_depth = depth
			best = s
	if best == -1:
		return Vector3.UP
	var gradient: Vector2 = field.surfaces[best].gradient
	return Vector3(-gradient.x, 1.0, -gradient.y).normalized()


## Up direction of the floor a destination is on.
func _floor_normal(point: Vector3) -> Vector3:
	if _reach == null:
		return Vector3.UP
	var surfaces: PackedInt32Array = _reach.legality.surfaces_at(point)
	if surfaces.is_empty():
		return Vector3.UP
	var gradient: Vector2 = _reach.field.surfaces[surfaces[surfaces.size() - 1]].gradient
	return Vector3(-gradient.x, 1.0, -gradient.y).normalized()


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
		view.floor_normal = _floor_up_at
		view.setup(model)
		_models_root.add_child(view)
		_views[model.id] = view


func _build_overlays() -> void:
	_indicator = MovementIndicator.new()
	add_child(_indicator)
	_preview = PathPreview.new()
	add_child(_preview)

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
	confirm.pressed.connect(func() -> void: confirm_pinned())
	confirm_row.add_child(confirm)
	var cancel: Button = UiStyle.button("Cancel (Esc)", "CancelMoveButton")
	cancel.pressed.connect(func() -> void: cancel_pinned())
	confirm_row.add_child(cancel)
	_confirm_panel.visible = false
	layer.add_child(_confirm_panel)

	_overrides = OverridePanel.new()
	_overrides.send = func(command: Command) -> void: send(command)
	layer.add_child(_overrides)
