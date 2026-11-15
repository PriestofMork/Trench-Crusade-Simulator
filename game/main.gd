extends Node3D
## Main scene: builds a GameState through commands, shows it, and turns clicks
## into commands. Never changes the state directly.
##
## Left click a model: select it. Left click inside the blue area: move there.
## Left click elsewhere on the table or Escape: deselect.
## R: give the selected model its full movement back (temporary, until activations).

const TABLE_THICKNESS: float = 1.0

## Starting terrain: footprint centre (x, z), size, and turn about the vertical axis in degrees.
const STARTING_TERRAIN: Array[Dictionary] = [
	{"center": Vector2(14, 16), "size": Vector3(6, 3, 4), "turn": 0.0},
	{"center": Vector2(34, 32), "size": Vector3(4, 5, 8), "turn": 0.0},
	{"center": Vector2(24, 24), "size": Vector3(8, 2, 3), "turn": 30.0},
	{"center": Vector2(36, 12), "size": Vector3(3, 4, 3), "turn": 15.0},
	{"center": Vector2(11, 32), "size": Vector3(1, 2.5, 7), "turn": -20.0},
]

## Starting models: owner, position (x, z), base size in mm, Movement in inches.
const STARTING_MODELS: Array[Dictionary] = [
	{"player": 0, "at": Vector2(18, 20), "base": 32, "movement": 6.0},
	{"player": 0, "at": Vector2(13, 22), "base": 25, "movement": 5.0},
	{"player": 0, "at": Vector2(28, 16), "base": 40, "movement": 7.0},
	{"player": 1, "at": Vector2(19, 28), "base": 50, "movement": 6.0},
	{"player": 1, "at": Vector2(30, 26), "base": 32, "movement": 8.0},
	{"player": 1, "at": Vector2(40, 36), "base": 60, "movement": 4.0},
]

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
## When set, hover follows this table point instead of the mouse (for scripted screenshots).
var _hover_override: Variant = null

@onready var _camera: TableCamera = $TableCamera
@onready var _table_root: Node3D = $Table
@onready var _models_root: Node3D = $Models


func _ready() -> void:
	state = GameState.new(1)
	_build_table()
	_place_starting_terrain()
	_build_terrain_views()
	_place_starting_models()
	_build_model_views()
	_build_overlays()
	_camera.set_table_bounds(state.table_width, state.table_depth)
	_update_status()


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
	_update_hover()


## Selects a model and shows where it can move.
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
	# Set first so _send() leaves the moving view and the reach field to the slide.
	_sliding = true
	var error: String = _send(MoveCommand.new(_selected_id, path))
	if error != "":
		_sliding = false
	else:
		var slide: Array[Vector3] = [start]
		slide.append_array(path)
		_preview.hide_all()
		_distance_label.visible = false
		_indicator.show_field(null)
		var id: int = _selected_id
		_views[id].slide_along(slide, _on_slide_done.bind(id))
	return error


func selected_model_id() -> int:
	return _selected_id


func is_sliding() -> bool:
	return _sliding


## Scripted hover for screenshots: a table point, or null to follow the mouse again.
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
	var started: int = Time.get_ticks_usec()
	_reach = ReachField.new(state, _selected_id)
	var computed: int = Time.get_ticks_usec()
	_indicator.show_field(_reach)
	var finished: int = Time.get_ticks_usec()
	print("Reach field for model %d: %d x %d nodes, %.1f ms, indicator mesh %.1f ms" % [
		_selected_id, _reach.size_x, _reach.size_z,
		(computed - started) / 1000.0, (finished - computed) / 1000.0
	])
	_update_status()


func _on_left_click(screen_position: Vector2) -> void:
	var picked: int = _pick_model(screen_position)
	if picked != -1:
		select_model(picked)
		return
	if _selected_id == -1:
		return
	var ground: Variant = _ground_point(screen_position)
	if ground != null and _reach != null and _reach.is_reachable(ground):
		move_selected_to(ground)
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
		point = _ground_point(mouse)
	if point == null:
		_preview.hide_all()
		_distance_label.visible = false
		return
	var target: Vector3 = point
	var model: ModelState = state.get_model(_selected_id)
	var path: Array[Vector3] = _reach.path_to(target)
	_preview.show_preview(model.position, path, target, model.base_radius_inches())
	if path.is_empty():
		_distance_label.visible = false
		return
	_distance_label.text = "%.1f\"" % MoveCommand.path_length(model.position, path)
	_distance_label.position = _camera.unproject_position(target) + Vector2(18, -34)
	_distance_label.visible = true


## The model under the screen position, or -1.
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
	return best_id


## Where the screen position meets the tabletop (y = 0), or null if it misses the table.
func _ground_point(screen_position: Vector2) -> Variant:
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	if direction.y >= -0.0001:
		return null
	var t: float = -origin.y / direction.y
	var point: Vector3 = origin + direction * t
	point.y = 0.0
	if point.x < 0.0 or point.z < 0.0 or point.x > state.table_width or point.z > state.table_depth:
		return null
	return point


func _update_status() -> void:
	if _status_label == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	if _selected_id != -1:
		var model: ModelState = state.get_model(_selected_id)
		lines.append("Model %d (player %d, %d mm base): Movement %.0f\", %.1f\" left" % [
			model.id, model.player + 1, model.base_mm, model.movement, model.movement_left
		])
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


func _place_starting_terrain() -> void:
	for entry: Dictionary in STARTING_TERRAIN:
		var center: Vector2 = entry["center"]
		var size: Vector3 = entry["size"]
		var turn: float = entry["turn"]
		var command: PlaceTerrainCommand = PlaceTerrainCommand.new(
			Vector3(center.x, size.y / 2.0, center.y), size, deg_to_rad(turn)
		)
		var error: String = state.execute(command)
		if error != "":
			push_error("Starting terrain rejected: %s" % error)


func _build_terrain_views() -> void:
	for piece: TerrainPiece in state.terrain:
		var view: TerrainView = TerrainView.new()
		view.setup(piece)
		_table_root.add_child(view)


func _place_starting_models() -> void:
	for entry: Dictionary in STARTING_MODELS:
		var at: Vector2 = entry["at"]
		var command: PlaceModelCommand = PlaceModelCommand.new(
			entry["player"], Vector3(at.x, 0.0, at.y), entry["base"], entry["movement"]
		)
		var error: String = state.execute(command)
		if error != "":
			push_error("Starting placement rejected: %s" % error)


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
