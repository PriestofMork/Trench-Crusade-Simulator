class_name MoveCommand
extends Command
## Moves a model along a polyline on flat ground. The path starts at the model's
## current position and runs through `waypoints`; the model ends on the last one.
##
## Valid only if the path is no longer than the model's remaining movement, at
## no point along it does the base overlap blocking terrain or an enemy base,
## leave the table, or come within 1" of an enemy base, and at the end it does
## not overlap any base. Friendly bases may be passed through on the way.

enum Rejection { NONE, INVALID, TOO_FAR, BLOCKED, TOO_CLOSE_TO_ENEMY }

const EPSILON: float = 0.0001

var model_id: int
var waypoints: Array[Vector3]
## Why the last validate() failed, as a category the UI can react to.
var rejection: Rejection = Rejection.NONE


func _init(p_model_id: int, p_waypoints: Array[Vector3]) -> void:
	model_id = p_model_id
	waypoints = p_waypoints


func validate(state: GameState) -> String:
	rejection = Rejection.INVALID
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return "No model with id %d." % model_id
	if waypoints.is_empty():
		return "A move needs at least one waypoint."
	for point: Vector3 in waypoints:
		if absf(point.y - model.position.y) > EPSILON:
			return "Moves must stay on flat ground."

	var length: float = path_length(model.position, waypoints)
	if length > model.movement_left + EPSILON:
		rejection = Rejection.TOO_FAR
		return "Too far: the path is %.1f\" but only %.1f\" of movement is left." % [
			length, model.movement_left
		]

	var legality: MoveLegality = MoveLegality.new(state, model)
	var previous: Vector2 = _flat(model.position)
	for point: Vector3 in waypoints:
		var next: Vector2 = _flat(point)
		var result: MoveLegality.Result = legality.segment_result(previous, next)
		if result != MoveLegality.Result.OK:
			return _reject(result)
		previous = next
	var end_result: MoveLegality.Result = legality.point_result(previous)
	if end_result != MoveLegality.Result.OK:
		return _reject(end_result)
	rejection = Rejection.NONE
	return ""


func _reject(result: MoveLegality.Result) -> String:
	if result == MoveLegality.Result.ENEMY:
		rejection = Rejection.TOO_CLOSE_TO_ENEMY
	else:
		rejection = Rejection.BLOCKED
	return MoveLegality.describe(result)


func apply(state: GameState) -> void:
	var model: ModelState = state.get_model(model_id)
	var length: float = path_length(model.position, waypoints)
	model.position = waypoints[waypoints.size() - 1]
	model.movement_left = maxf(model.movement_left - length, 0.0)


## Length of the path from `start` through `points`, measured on the table plane.
static func path_length(start: Vector3, points: Array[Vector3]) -> float:
	var total: float = 0.0
	var previous: Vector2 = _flat(start)
	for point: Vector3 in points:
		var next: Vector2 = _flat(point)
		total += previous.distance_to(next)
		previous = next
	return total


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
