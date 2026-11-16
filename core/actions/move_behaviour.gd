class_name MoveBehaviour
extends ActionBehaviour
## Move (docs/rules/movement.md, ruling 1 of brief 005): one path of up to the
## model's Movement (halved after standing up); what is left over is lost.


func begin(state: GameState, model: ModelState, action: ActionDef, events: Array[GameEvent], _plan: ActionPlan = null) -> void:
	TurnFlow.offer_move(state, model, action.id, events)


func move_budget_preview(state: GameState, model: ModelState) -> float:
	return TurnFlow.movement_budget(state, model)
