class_name RollThenMoveBehaviour
extends ActionBehaviour
## A success roll (risky if the action is); on a success the model may make
## one more move of up to its Movement (halved after standing up), or decline.
## Dash is this. What a failure does is up to the roll reactions.


func begin(state: GameState, model: ModelState, action: ActionDef, events: Array[GameEvent]) -> void:
	var request: RollRequest = RollRequest.success(model.player, model.id, action.id, action.risky, action.label)
	var model_id: int = model.id
	var action_id: StringName = action.id
	request.on_resolved = func(s: GameState, result: RollResult, e: Array[GameEvent]) -> void:
		if result.is_success() and s.turn.active_model_id == model_id:
			TurnFlow.offer_move(s, s.get_model(model_id), action_id, e)
	RollPipeline.start(state, request, events)
