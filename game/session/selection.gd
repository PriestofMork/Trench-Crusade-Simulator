class_name Selection
extends RefCounted
## The selected model, its descent mode, and what is under the mouse: model
## and floor picking for every mode. Changing the selection itself (and what
## that does to the active mode) is main.gd's select_model() / deselect().

## The selected model, or -1.
var id: int = -1
## When set, hover follows this 3D point instead of the mouse (for scripted screenshots).
var hover_override: Variant = null

var _state: GameState
var _camera: Camera3D
var _views: Dictionary[int, ModelView]
## Descent mode per model id (Drop if not set).
var _descent: Dictionary[int, Transitions.DescentMode] = {}


func _init(state: GameState, camera: Camera3D, views: Dictionary[int, ModelView]) -> void:
	_state = state
	_camera = camera
	_views = views


## Moves the selection ring to `new_id` (-1: none).
func set_id(new_id: int) -> void:
	if id != -1 and _views.has(id):
		_views[id].set_selected(false)
	id = new_id
	if id != -1:
		_views[id].set_selected(true)


func model() -> ModelState:
	return _state.get_model(id)


## The selected model's descent mode (how drops of 3" or more are taken).
func descent_mode() -> Transitions.DescentMode:
	return _descent.get(id, Transitions.DescentMode.DROP)


func set_descent_mode(mode: Transitions.DescentMode) -> void:
	_descent[id] = mode


static func descent_name(mode: Transitions.DescentMode) -> String:
	return "Climb down" if mode == Transitions.DescentMode.CLIMB_DOWN else "Drop"


func mouse() -> Vector2:
	return _camera.get_viewport().get_mouse_position()


## The model whose base is nearest a table point (within 2"), or -1.
func model_near(point: Vector3) -> int:
	var best: int = -1
	var best_distance: float = 2.0
	for model: ModelState in _state.models_on_table():
		var d: float = Vector2(point.x, point.z).distance_to(Vector2(model.position.x, model.position.z))
		if d < best_distance:
			best_distance = d
			best = model.id
	return best


func over_ui(screen_position: Vector2) -> bool:
	var hovered: Control = _camera.get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP and hovered.get_global_rect().has_point(screen_position)


## The model under the screen position, or -1. Terrain in front hides it.
func pick_model(screen_position: Vector2) -> int:
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var best_id: int = -1
	var best_t: float = INF
	for view_id: int in _views:
		var t: float = _views[view_id].ray_hit_distance(origin, direction)
		if t < best_t:
			best_t = t
			best_id = view_id
	var hit: TerrainPicker.Hit = TerrainPicker.pick(_state, origin, direction)
	if hit != null and hit.distance < best_t:
		return -1
	return best_id


## The point on the table or terrain the screen position points at, or null.
func floor_point(screen_position: Variant) -> Variant:
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var hit: TerrainPicker.Hit = TerrainPicker.pick(_state, origin, direction)
	return hit.point if hit != null else null
