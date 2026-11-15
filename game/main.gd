extends Node3D
## Main scene: builds a GameState through commands, shows it, and turns clicks
## into commands. Never changes the state directly.
##
## Left click a model: select it. Left click inside the blue area: move so the
## base reaches as far towards the click as it legally can. The cursor points
## at whatever floor is under it (move the camera to reach the table under a
## bridge). Left click elsewhere or Escape: deselect.
## R: give the selected model its full movement back (temporary, until activations).

const TABLE_THICKNESS: float = 1.0
## The table set-up loaded at start (terrain and models).
const TABLE_FILE: String = "res://data/tables/height_test_table.json"

var state: GameState

var _views: Dictionary[int, ModelView] = {}
var _selected_id: int = -1
var _reach: ReachField
var _sliding: bool = false
var _indicator: MovementIndicator
var _preview: PathPreview
var _distance_label: Label
var _status_label: Label
var _message: String = ""
## When set, hover follows this 3D point instead of the mouse (for scripted screenshots).
var _hover_override: Variant = null

# The reach field is built on a worker thread so selecting stays responsive.
var _reach_task: int = -1
var _reach_task_model: int = -1
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
	_update_status()


func _exit_tree() -> void:
	if _reach_task != -1:
		WorkerThreadPool.wait_for_task_completion(_reach_task)
		_reach_task = -1


func _unhandled_input(event: InputEvent) -> void:
	if _sliding:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(button.position)
	elif event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE:
			deselect()
		elif key.physical_keycode == KEY_R and _selected_id != -1:
			_send(ResetMovementCommand.new(_selected_id))


func _process(_delta: float) -> void:
	_collect_reach()
	_update_hover()


## Selects a model and starts working out where it can move.
func select_model(id: int) -> void:
	if _selected_id != -1 and _views.has(_selected_id):
		_views[_selected_id].set_selected(false)
	_selected_id = id
	_views[id].set_selected(true)
	_message = ""
	_refresh_reach()


func deselect() -> void:
	if _selected_id != -1 and _views.has(_selected_id):
		_views[_selected_id].set_selected(false)
	_selected_id = -1
	_reach = null
	_indicator.show_field(null)
	_preview.hide_all()
	_distance_label.visible = false
	_update_status()


## Sends a move for the selected model to `point` along the reach field's path.
## Returns "" if the model moves, else why not.
func move_selected_to(point: Vector3) -> String:
	if _selected_id == -1 or _reach == null or _sliding:
		return "No model selected."
	var path: Array[Vector3] = _reach.path_to(point)
	if path.is_empty():
		return "Out of reach."
	var start: Vector3 = state.get_model(_selected_id).position
	var shown: Array[Vector3] = _display_path(start, path)
	# Set first so _send() leaves the moving view and the reach field to the slide.
	_sliding = true
	var error: String = _send(MoveCommand.new(_selected_id, path))
	if error != "":
		_sliding = false
	else:
		_preview.hide_all()
		_distance_label.visible = false
		_indicator.show_field(null)
		var id: int = _selected_id
		_views[id].slide_along(shown, _on_slide_done.bind(id))
	return error


func selected_model_id() -> int:
	return _selected_id


func is_sliding() -> bool:
	return _sliding


## Whether the selected model's reach field is ready (it is built in the background).
func is_reach_ready() -> bool:
	return _selected_id != -1 and _reach != null and _reach.model_id == _selected_id


## Where a click on `point` (on a floor) would send the selected model, or null.
func destination_for(point: Vector3) -> Variant:
	return _destination_for(point)


## Scripted hover for screenshots: a 3D point on a floor, or null to follow the mouse again.
func set_hover_override(point: Variant) -> void:
	_hover_override = point


## Runs a command, shows its outcome, and refreshes everything that depends on state.
func _send(command: Command) -> String:
	var error: String = state.execute(command)
	_message = error
	if error == "":
		for model: ModelState in state.models:
			if not (_sliding and model.id == _selected_id):
				_views[model.id].sync(model)
		if not _sliding:
			_refresh_reach()
	_update_status()
	return error


func _on_slide_done(id: int) -> void:
	_sliding = false
	_views[id].sync(state.get_model(id))
	if id == _selected_id:
		_refresh_reach()


func _refresh_reach() -> void:
	if _selected_id == -1:
		return
	_reach = null
	_indicator.show_field(null)
	_preview.hide_all()
	_distance_label.visible = false
	if _reach_task != -1:
		# A stale build: let it finish, its result is dropped in _collect_reach().
		WorkerThreadPool.wait_for_task_completion(_reach_task)
	_built_field = null
	# The height field is shared; build it here so the worker only reads it.
	state.height_field()
	_reach_task_model = _selected_id
	_reach_started_usec = Time.get_ticks_usec()
	_reach_task = WorkerThreadPool.add_task(_build_reach.bind(_selected_id))
	_update_status()


## On a worker thread: only reads the state, which does not change while a
## field is being built (nothing can move without one).
func _build_reach(id: int) -> void:
	var field: ReachField = ReachField.new(state, id)
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
	if field == null or _reach_task_model != _selected_id or _sliding:
		return
	var computed: int = Time.get_ticks_usec()
	_reach = field
	_indicator.show_field(field, layers)
	print("Reach field for model %d: %d states, %.1f ms (field and layers, on a worker), indicator mesh %.1f ms" % [
		_selected_id, field.state_count(), (computed - _reach_started_usec) / 1000.0,
		(Time.get_ticks_usec() - computed) / 1000.0
	])
	_update_status()


func _on_left_click(screen_position: Vector2) -> void:
	var picked: int = _pick_model(screen_position)
	if picked != -1:
		select_model(picked)
		return
	if _selected_id == -1 or _reach == null:
		return
	var destination: Variant = _destination_for(_floor_point(screen_position))
	if destination != null:
		move_selected_to(destination)
	else:
		deselect()


func _update_hover() -> void:
	if _selected_id == -1 or _reach == null or _sliding:
		return
	var point: Variant = _hover_override
	if point == null:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		if _pick_model(mouse) != -1:
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
	_distance_label.text = "%.1f\"" % cost
	if surcharge > 0.0:
		_distance_label.text += "  (incl. %.1f\" to stop on the obstacle)" % surcharge
	_distance_label.position = _camera.unproject_position(target) + Vector2(18, -34)
	_distance_label.visible = true


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


func _update_status() -> void:
	if _status_label == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	if _selected_id != -1:
		var model: ModelState = state.get_model(_selected_id)
		lines.append("Model %d (player %d, %d mm base): Movement %.0f\", %.1f\" left" % [
			model.id, model.player + 1, model.base_mm, model.movement, model.movement_left
		])
		if _reach == null:
			lines.append("Working out where it can go...")
		else:
			lines.append("Click in the blue area to move.  R: reset movement (temporary).  Esc: deselect.")
	else:
		lines.append("Left click a model to select it.  Right drag: orbit.  Middle drag / WASD: pan.  Wheel: zoom.")
	if _message != "":
		lines.append(_message)
	_status_label.text = "\n".join(lines)


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
	layer.name = "Hud"
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

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_status_label.add_theme_constant_override("outline_size", 5)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status_label.position += Vector2(16, -16)
	layer.add_child(_status_label)
