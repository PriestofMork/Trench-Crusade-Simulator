class_name MovePath
extends RefCounted
## Checks one path for a model across the floors of the table, against a
## movement budget. The path starts at the model's current position and runs
## through `waypoints` (3D points, each on a floor); the model ends on the
## last one. Pure geometry: whether the model may move at all is up to the
## command that uses this (MoveCommand).
##
## Legal only if every segment is a legal walk or roll-free wall crossing (see
## MoveLegality: every point passable, every change of floor an allowed
## transition), the end is somewhere the model may stop, and the total cost
## (walks along the surface, wall crossings as Transitions prices them, plus
## the surcharge for stopping on a low obstacle) fits the budget.

enum Rejection { NONE, INVALID, TOO_FAR, BLOCKED, TOO_CLOSE_TO_ENEMY, NEEDS_ROLL }

const EPSILON: float = 0.0001

var model_id: int
var waypoints: Array[Vector3]
var budget: float
## "" if legal, else why not.
var error: String = ""
## Why it is not legal, as a category the UI can react to.
var rejection: Rejection = Rejection.INVALID
## What the path costs, INF if it is not legal.
var cost: float = INF
## Where the model ends, exactly on the floor.
var end_position: Vector3 = Vector3.ZERO


## `p_budget` negative means the model's full Movement characteristic.
func _init(state: GameState, p_model_id: int, p_waypoints: Array[Vector3], p_budget: float = -1.0) -> void:
	model_id = p_model_id
	waypoints = p_waypoints
	budget = p_budget
	error = _check(state)


func is_legal() -> bool:
	return error == ""


func _check(state: GameState) -> String:
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return "No model with id %d." % model_id
	if budget < 0.0:
		budget = model.movement
	if waypoints.is_empty():
		return "A move needs at least one waypoint."
	# Every way of moving costs at least the distance on the table plane.
	var flat: float = plan_length(model.position, waypoints)
	if flat > budget + EPSILON:
		rejection = Rejection.TOO_FAR
		return _too_far(flat, budget)

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
	if total > budget + EPSILON:
		rejection = Rejection.TOO_FAR
		return _too_far(total, budget)
	var end_surfaces: PackedInt32Array = legality.surfaces_at(previous)
	var floor_height: float = legality.field.surface_height(end_surfaces[0], Vector2(previous.x, previous.z))
	end_position = Vector3(previous.x, floor_height, previous.z)
	cost = total
	rejection = Rejection.NONE
	return ""


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
	return "Too far: the move costs %.1f\" but only %.1f\" of movement is allowed." % [length, left]


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
