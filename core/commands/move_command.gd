class_name MoveCommand
extends Command
## Answers a pending MOVE decision: `model_id` moves along one path (see
## MovePath) within the decision's budget. Ruling 1 of brief 005: one path per
## granted move; whatever is left over is lost.

var player: int
var model_id: int
var waypoints: Array[Vector3]
## Why the last validate() failed, as a category the UI can react to.
var rejection: MovePath.Rejection = MovePath.Rejection.NONE
## What the move costs, set by validate().
var cost: float = INF

var _path: MovePath = null


func _init(p_player: int, p_model_id: int, p_waypoints: Array[Vector3]) -> void:
	player = p_player
	model_id = p_model_id
	waypoints = p_waypoints


func validate(state: GameState) -> String:
	rejection = MovePath.Rejection.INVALID
	cost = INF
	_path = null
	var error: String = PendingDecision.check(state, PendingDecision.Kind.MOVE, player)
	if error != "":
		return error
	if state.pending.model_id != model_id:
		return "The move waiting is model %d's, not model %d's." % [state.pending.model_id, model_id]
	var path: MovePath = MovePath.new(state, model_id, waypoints, state.pending.budget)
	rejection = path.rejection
	if not path.is_legal():
		return path.error
	cost = path.cost
	_path = path
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	if _path == null:
		validate(state)
	var model: ModelState = state.get_model(model_id)
	var shown: Array[Vector3] = [model.position]
	shown.append_array(waypoints)
	shown[shown.size() - 1] = _path.end_position
	# Exactly on the floor, so small errors never build up.
	model.position = _path.end_position
	state.pending = null
	_path = null
	return [GameEvent.new(GameEvent.Kind.MODEL_MOVED, player, model_id, {"path": shown, "cost": cost})]
