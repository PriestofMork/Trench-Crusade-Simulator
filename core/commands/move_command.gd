class_name MoveCommand
extends Command
## One step of an open move: `model_id` moves along a path (see MovePath)
## within what is left of the move's budget. Ruling 1 of brief 005: the move
## stays open with the rest until the model does anything else.
##
## The path is carried out by MoveExecution, in stages where it makes rolls
## (a sheer climb, a gap jump, a drop): up to each roll point, then on or
## stopped by the roll's result. Validation covers such a path in full beforehand: every
## roll point, the movement to clear a sheer surface, the jump limits and a
## place to stop at the end.

var player: int
var model_id: int
var waypoints: Array[Vector3]
## How drops of 3" or more are taken: the descent mode the move was chosen in,
## so validation, the staged execution, undo and replay all agree with what
## the reach field showed.
var descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
## Why the last validate() failed, as a category the UI can react to.
var rejection: MovePath.Rejection = MovePath.Rejection.NONE
## What the move costs, set by validate().
var cost: float = INF

var _path: MovePath = null


func _init(
	p_player: int, p_model_id: int, p_waypoints: Array[Vector3],
	p_descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
) -> void:
	player = p_player
	model_id = p_model_id
	waypoints = p_waypoints
	descent_mode = p_descent_mode


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
	var path: MovePath = MovePath.new(state, model_id, waypoints, state.pending.budget, descent_mode, state.pending.zones)
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
	var events: Array[GameEvent] = []
	# Every step, with rolls or without, is carried out by the one movement
	# process (brief 008b).
	MoveExecution.start(state, path, state.pending, events)
	return events
