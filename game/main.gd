extends Node3D
## Main scene: builds a GameState through commands, shows it, turns clicks and
## button presses into commands, and plays back the events core returns, in
## order. Never changes the state directly. Two players share the screen and
## mouse (hotseat); every prompt names the player who answers it.
##
## Left click a model: select it (a preview; the activation starts with its
## first action). Left click inside the blue area: take the Move action there
## (or make the move a Dash granted). Escape: deselect. O: override panel.
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
var _indicator: MovementIndicator
var _preview: PathPreview
var _distance_label: Label
var _hud: Hud
var _tray: DiceTray
var _overrides: OverridePanel
## When set, hover follows this 3D point instead of the mouse (for scripted screenshots).
var _hover_override: Variant = null

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
		if key.physical_keycode == KEY_ESCAPE:
			deselect()
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


## Runs a command and plays back its events. Returns "" or why it was rejected.
func send(command: Command) -> String:
	var result: CommandResult = state.submit(command)
	if not result.ok():
		_hud.show_message("[color=#%s]%s[/color]" % [UiStyle.BAD_COLOUR.to_html(false), result.error])
		_refresh_all()
		return result.error
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
	_refresh_all()


func selected_model_id() -> int:
	return _selected_id


## Moves the selected model to `point` along the reach field's path: answers
## a pending move, or takes the Move action first. Returns "" or why not.
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
	return send(MoveCommand.new(state.pending.player, model.id, path))


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


func answer_roll_choice(amount: int) -> String:
	if state.pending == null:
		return "Nothing to answer."
	return send(RollChoiceCommand.new(state.pending.player, amount))


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
		GameEvent.Kind.ACTIVATION_ENDED:
			if event.data.get("reason", "") == "failed risky roll":
				_tray.note_activation_ended()
				_hud.show_message("Failed risky roll: model %d's activation ends." % event.model_id)
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
	var shown: Array[Vector3] = path
	if _reach != null and _reach.model_id == event.model_id:
		shown = _display_path(path[0], path.slice(1))
	_clear_reach()
	_playing = true
	_views[event.model_id].slide_along(shown, func() -> void:
		_views[event.model_id].sync(state.get_model(event.model_id))
		_resume()
	)


## Brings every view in line with the state once the events are played.
## Skipped while events are still playing, so nothing shows ahead of them.
func _refresh_all() -> void:
	if _hud == null or is_busy():
		return
	for model: ModelState in state.models:
		var view: ModelView = _views[model.id]
		view.sync(model)
		view.show_status(model, state.turn.has_activated(model.id), state.turn.active_model_id == model.id)
	_hud.refresh(state, _selected_id)
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
	var key: String = "%d|%.3f|%s" % [_selected_id, budget, str(model.position)]
	if key == _reach_key:
		return
	_clear_reach()
	_reach_key = key
	if _reach_task != -1:
		# A stale build: let it finish, its result is dropped in _collect_reach().
		WorkerThreadPool.wait_for_task_completion(_reach_task)
		_reach_task = -1
	_built_field = null
	# The height field is shared; build it here so the worker only reads it.
	state.height_field()
	_reach_task_key = key
	_reach_started_usec = Time.get_ticks_usec()
	_reach_task = WorkerThreadPool.add_task(_build_reach.bind(_selected_id, budget))


func _clear_reach() -> void:
	_reach = null
	_reach_key = ""
	_indicator.show_field(null)
	_preview.hide_all()
	_distance_label.visible = false


## On a worker thread: only reads positions and terrain, which do not change
## while a field is being built (nothing can move without one).
func _build_reach(id: int, budget: float) -> void:
	var field: ReachField = ReachField.new(state, id, budget)
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
	print("Reach field for model %d (%.1f\"): %d states, %.1f ms on a worker, indicator mesh %.1f ms" % [
		field.model_id, field.budget, field.state_count(), (computed - _reach_started_usec) / 1000.0,
		(Time.get_ticks_usec() - computed) / 1000.0
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
		move_selected_to(destination)
	else:
		deselect()


func _update_hover() -> void:
	if _selected_id == -1 or _reach == null or is_busy():
		return
	var point: Variant = _hover_override
	if point == null:
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
	if not path.is_empty():
		shown = _display_path(model.position, path)
		shown.remove_at(0)
	_preview.show_preview(model.position, shown, target, model.base_radius_inches(), _floor_normal(target))
	if path.is_empty():
		_distance_label.visible = false
		return
	var cost: float = _reach.cost_to(target)
	var surcharge: float = _reach.surcharge_at(target)
	_distance_label.text = "%.1f\" of %.1f\"" % [cost, _reach.budget]
	if surcharge > 0.0:
		_distance_label.text += "  (incl. %.1f\" to stop on the obstacle)" % surcharge
	_distance_label.position = _camera.unproject_position(target) + Vector2(18, -34)
	_distance_label.visible = true


func _over_ui(screen_position: Vector2) -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP and hovered.get_global_rect().has_point(screen_position)


## The path as it is drawn and played: each climb or drop split into its
## vertical part and its horizontal part (up: rise at the wall, then onto the
## top; down: step off the edge, then drop), so it reads as one motion along
## the ground, straight up the wall and on.
func _display_path(start: Vector3, path: Array[Vector3]) -> Array[Vector3]:
	var shown: Array[Vector3] = [start]
	var previous: Vector3 = start
	for point: Vector3 in path:
		var kind: Transitions.Kind = _reach.segment_kind(previous, point)
		if kind != Transitions.Kind.WALK and kind != Transitions.Kind.NONE:
			if point.y > previous.y:
				shown.append(Vector3(previous.x, point.y, previous.z))
			else:
				shown.append(Vector3(point.x, previous.y, point.z))
		shown.append(point)
		previous = point
	return shown


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

	_tray = DiceTray.new()
	_tray.custom_minimum_size = Vector2(TRAY_WIDTH, 0)
	_tray.choice_answered.connect(func(amount: int) -> void: answer_roll_choice(amount))
	layer.add_child(_tray)

	_overrides = OverridePanel.new()
	_overrides.send = func(command: Command) -> void: send(command)
	layer.add_child(_overrides)
