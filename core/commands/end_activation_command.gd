class_name EndActivationCommand
extends Command
## `player` ends `model_id`'s activation (ruling 3 of brief 005: at any time,
## even before it has acted, which starts and ends it at once). A move still
## waiting to be chosen is lost. Not allowed while a roll is under way.

var player: int
var model_id: int


func _init(p_player: int, p_model_id: int) -> void:
	player = p_player
	model_id = p_model_id


func validate(state: GameState) -> String:
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return "No model with id %d." % model_id
	var pending: PendingDecision = state.pending
	if pending != null and pending.kind == PendingDecision.Kind.MOVE and pending.model_id == model_id:
		# An open move does not hold the activation up; what is left is lost.
		if not pending.is_for(player):
			return "That decision is player %d's." % (pending.player + 1)
	return TurnFlow.activation_error(state, player, model)


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	if state.turn.active_model_id != model_id:
		TurnFlow.begin_activation(state, state.get_model(model_id), events)
	TurnFlow.end_activation(state, events, "ended by the player")
	return events
