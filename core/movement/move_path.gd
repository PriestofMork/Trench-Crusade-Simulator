class_name MovePath
extends RefCounted
## Checks one path for a model across the floors of the table, against a
## movement budget. The path starts at the model's current position and runs
## through `waypoints` (3D points, each on a floor); the model ends on the
## last one. Pure geometry: whether the model may move at all is up to the
## command that uses this (MoveCommand).
##
## Legal only if every segment is a legal walk, wall crossing or gap jump (see
## MoveLegality: every point passable, every change of floor an allowed
## transition, every jump within the jump limit), the end is somewhere the
## model may stop, and the total cost (walks along the surface, crossings as
## Transitions prices them, plus the surcharge for stopping on a low
## obstacle) fits the budget. A sheer climb counts in full, so the model must
## have the movement to clear the whole surface before it may try it.
##
## The path may make rolls (brief 006): `segments` says how each segment is
## taken and rolls() lists the rolls in order. MoveCommand carries such a path
## out in stages (MoveExecution).

enum Rejection { NONE, INVALID, TOO_FAR, BLOCKED, TOO_CLOSE_TO_ENEMY, NEEDS_ROLL, TOO_WIDE }

const EPSILON: float = 0.0001

var model_id: int
var waypoints: Array[Vector3]
var budget: float
## How drops of 3" or more are taken (Transitions.DescentMode).
var descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
## How enemy 1" zones are treated (null: the normal rule). See EnemyZones.
var zones: EnemyZones = null
## "" if legal, else why not.
var error: String = ""
## Why it is not legal, as a category the UI can react to.
var rejection: Rejection = Rejection.INVALID
## What the path costs, INF if it is not legal.
var cost: float = INF
## What stopping at the end adds to it (included in cost).
var surcharge: float = 0.0
## Where the model ends, exactly on the floor.
var end_position: Vector3 = Vector3.ZERO
## How each segment is taken (empty if not legal). The last one ends at end_position.
var segments: Array[MoveSegment] = []


## `p_budget` negative means the model's full Movement characteristic.
func _init(
	state: GameState, p_model_id: int, p_waypoints: Array[Vector3], p_budget: float = -1.0,
	p_descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP, p_zones: EnemyZones = null
) -> void:
	model_id = p_model_id
	waypoints = p_waypoints
	budget = p_budget
	descent_mode = p_descent_mode
	zones = p_zones
	error = _check(state)


func is_legal() -> bool:
	return error == ""


## Whether carrying the path out makes any roll.
func has_rolls() -> bool:
	for segment: MoveSegment in segments:
		if segment.roll_count() > 0:
			return true
	return false


## The rolls along the path, in order (see MoveSegment.rolls()).
func rolls() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for segment: MoveSegment in segments:
		result.append_array(segment.rolls())
	return result


func _check(state: GameState) -> String:
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return "No model with id %d." % model_id
	if not model.on_table():
		return "Model %d is Out of Action." % model_id
	if budget < 0.0:
		budget = model.movement
	if waypoints.is_empty():
		return "A move needs at least one waypoint."
	# Every way of moving costs at least the distance on the table plane.
	var flat: float = plan_length(model.position, waypoints)
	if flat > budget + EPSILON:
		rejection = Rejection.TOO_FAR
		return _too_far(flat, budget)

	var legality: MoveLegality = MoveLegality.new(state, model, null, zones)
	legality.descent_mode = descent_mode
	if legality.start_surfaces.is_empty():
		return "The model is not standing on a floor."
	var found: Array[MoveSegment] = legality.segments_for(model.position, waypoints)
	if found.is_empty():
		return _reject(legality.last_result)
	var total: float = 0.0
	for segment: MoveSegment in found:
		total += segment.cost
	var last: Vector3 = waypoints[waypoints.size() - 1]
	var stop: float = legality.stop_surcharge(last)
	if stop == INF:
		return _reject(legality.last_result)
	total += stop
	if total > budget + EPSILON:
		rejection = Rejection.TOO_FAR
		return _too_far(total, budget)
	var end_surfaces: PackedInt32Array = legality.surfaces_at(last)
	var floor_height: float = legality.field.surface_height(end_surfaces[0], Vector2(last.x, last.z))
	end_position = Vector3(last.x, floor_height, last.z)
	cost = total
	surcharge = stop
	segments = found
	rejection = Rejection.NONE
	return ""


func _reject(result: MoveLegality.Result) -> String:
	match result:
		MoveLegality.Result.ENEMY:
			rejection = Rejection.TOO_CLOSE_TO_ENEMY
		MoveLegality.Result.NEEDS_ROLL:
			rejection = Rejection.NEEDS_ROLL
		MoveLegality.Result.TOO_WIDE:
			rejection = Rejection.TOO_WIDE
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
