class_name MoveCommand
extends Command
## Moves a model along a path across the floors of the table. The path starts
## at the model's current position and runs through `waypoints` (3D points,
## each on a floor); the model ends on the last one.
##
## Valid only if every segment is a legal walk or roll-free wall crossing (see
## MoveLegality: every point passable, every change of floor an allowed
## transition), the end is somewhere the model may stop, and the total cost
## (walks along the surface, wall crossings as Transitions prices them, plus
## the surcharge for stopping on a low obstacle) fits the remaining movement.

enum Rejection { NONE, INVALID, TOO_FAR, BLOCKED, TOO_CLOSE_TO_ENEMY, NEEDS_ROLL }

const EPSILON: float = 0.0001

var model_id: int
var waypoints: Array[Vector3]
## Why the last validate() failed, as a category the UI can react to.
var rejection: Rejection = Rejection.NONE
## What the move costs, set by validate().
var cost: float = INF

var _end_surface_height: float = 0.0


func _init(p_model_id: int, p_waypoints: Array[Vector3]) -> void:
	model_id = p_model_id
	waypoints = p_waypoints


func validate(state: GameState) -> String:
	rejection = Rejection.INVALID
	cost = INF
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return "No model with id %d." % model_id
	if waypoints.is_empty():
		return "A move needs at least one waypoint."
	# Every way of moving costs at least the distance on the table plane.
	var flat: float = plan_length(model.position, waypoints)
	if flat > model.movement_left + EPSILON:
		rejection = Rejection.TOO_FAR
		return _too_far(flat, model.movement_left)

	var legality: MoveLegality = MoveLegality.new(state, model)
	if legality.start_surfaces.is_empty():
		return "The model is not standing on a floor."
	var total: float = 0.0
	var previous: Vector3 = model.position
	for point: Vector3 in waypoints:
		var step: float = legality.segment_cost(previous, point)
		if step == INF:
			return _reject(legality.last_result)
		total += step
		previous = point
	var surcharge: float = legality.stop_surcharge(previous)
	if surcharge == INF:
		return _reject(legality.last_result)
	total += surcharge
	if total > model.movement_left + EPSILON:
		rejection = Rejection.TOO_FAR
		return _too_far(total, model.movement_left)
	var end_surfaces: PackedInt32Array = legality.surfaces_at(previous)
	_end_surface_height = legality.field.surface_height(end_surfaces[0], Vector2(previous.x, previous.z))
	cost = total
	rejection = Rejection.NONE
	return ""


func apply(state: GameState) -> void:
	var model: ModelState = state.get_model(model_id)
	if cost == INF:
		validate(state)
	var end: Vector3 = waypoints[waypoints.size() - 1]
	# Exactly on the floor, so small errors never build up.
	model.position = Vector3(end.x, _end_surface_height, end.z)
	model.movement_left = maxf(model.movement_left - cost, 0.0)


func _reject(result: MoveLegality.Result) -> String:
	match result:
		MoveLegality.Result.ENEMY:
			rejection = Rejection.TOO_CLOSE_TO_ENEMY
		MoveLegality.Result.NEEDS_ROLL:
			rejection = Rejection.NEEDS_ROLL
		_:
			rejection = Rejection.BLOCKED
	return MoveLegality.describe(result)


static func _too_far(length: float, left: float) -> String:
	return "Too far: the move costs %.1f\" but only %.1f\" of movement is left." % [length, left]


## Length of the path from `start` through `points` on the table plane: a lower
## bound on what it costs.
static func plan_length(start: Vector3, points: Array[Vector3]) -> float:
	var total: float = 0.0
	var previous: Vector2 = Vector2(start.x, start.z)
	for point: Vector3 in points:
		var next: Vector2 = Vector2(point.x, point.z)
		total += previous.distance_to(next)
		previous = next
	return total


## What moving `model_id` along `points` would cost, or INF if it is not legal.
static func path_cost(state: GameState, p_model_id: int, points: Array[Vector3]) -> float:
	var command: MoveCommand = MoveCommand.new(p_model_id, points)
	command.validate(state)
	return command.cost
