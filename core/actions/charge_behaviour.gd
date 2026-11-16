class_name ChargeBehaviour
extends ActionBehaviour
## Charge (docs/rules/movement.md; brief 007): a move action against a target
## model. The target and the path are worked out when it is declared
## (ChargePlanner), then ChargeExecution rolls the D6 and carries it out.


func needs_target() -> bool:
	return true


func plan_for(state: GameState, model: ModelState, _action: ActionDef, target_id: int) -> ActionPlan:
	return ChargePlanner.new(state, model.id).plan(target_id)


func begin(state: GameState, model: ModelState, action: ActionDef, events: Array[GameEvent], plan: ActionPlan = null) -> void:
	ChargeExecution.start(state, model, action, plan as ChargePlan, events)


func move_budget_preview(state: GameState, model: ModelState) -> float:
	return TurnFlow.movement_budget(state, model, model.movement + ChargePlanner.DIE_SIDES)
