class_name MoveCommand
extends Command
## One step of an open move: `model_id` moves along a path (see MovePath)
## within what is left of the move's budget. Ruling 1 of brief 005: the move
## stays open with the rest until the model does anything else.
##
## A path with rolls in it (a sheer climb, a gap jump, a drop) is carried out
## in stages by MoveExecution: up to each roll point, then on or stopped by
## the roll's result. Validation covers such a path in full beforehand: every
## roll point, the movement to clear a sheer surface, the jump limits and a
## place to stop at the end.

var player: int
var model_id: int
var waypoints: Array[Vector3]
## Per waypoint, a kind its segment must be taken as, or NONE (see MovePath).
var segment_kinds: Array = []
## Why the last validate() failed, as a category the UI can react to.
var rejection: MovePath.Rejection = MovePath.Rejection.NONE
## What the move costs, set by validate().
var cost: float = INF

var _path: MovePath = null


func _init(p_player: int, p_model_id: int, p_waypoints: Array[Vector3], p_segment_kinds: Array = []) -> void:
	player = p_player
	model_id = p_model_id
	waypoints = p_waypoints
	segment_kinds = p_segment_kinds


## The path as the last validate() checked it, or null.
func path() -> MovePath:
	return _path


func validate(state: GameState) -> String:
	rejection = MovePath.Rejection.INVALID
	cost = INF
	_path = null
	var error: String = PendingDecision.check(state, PendingDecision.Kind.MOVE, player)
	if error != "":
		return error
	if state.pending.model_id != model_id:
		return "The move waiting is model %d's, not model %d's." % [state.pending.model_id, model_id]
	var path: MovePath = MovePath.new(state, model_id, waypoints, state.pending.budget, segment_kinds)
	rejection = path.rejection
	if not path.is_legal():
		return path.error
	cost = path.cost
	_path = path
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	if _path == null:
		validate(state)
	var path: MovePath = _path
	_path = null
	var decision: PendingDecision = state.pending
	var events: Array[GameEvent] = []
	if path.has_rolls():
		MoveExecution.start(state, path, decision, events)
		return events
	var model: ModelState = state.get_model(model_id)
	var shown: Array[Vector3] = [model.position]
	shown.append_array(waypoints)
	shown[shown.size() - 1] = path.end_position
	var kinds: Array[Transitions.Kind] = []
	for segment: MoveSegment in path.segments:
		kinds.append(segment.kind)
	# Exactly on the floor, so small errors never build up.
	model.position = path.end_position
	var left: float = maxf(decision.budget - cost, 0.0)
	state.pending = null
	events.append(GameEvent.new(GameEvent.Kind.MODEL_MOVED, player, model_id, {
		"path": shown, "kinds": kinds, "cost": cost, "left": left
	}))
	TurnFlow.continue_move(state, model, decision.action_id, left, events)
	return events
