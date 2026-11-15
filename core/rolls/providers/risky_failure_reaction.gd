class_name RiskyFailureReaction
extends RollReaction
## docs/rules/rolls.md: if a risky success roll fails, the rolling model's
## activation ends immediately.


func _init() -> void:
	id = &"risky_failure_ends_activation"


func react(state: GameState, result: RollResult, events: Array[GameEvent]) -> void:
	var request: RollRequest = result.request
	if request.kind != RollRequest.Kind.SUCCESS or not result.risky or not result.is_failure():
		return
	if request.actor_id == -1 or request.actor_id != state.turn.active_model_id:
		return
	TurnFlow.end_activation(state, events, "failed risky roll")
