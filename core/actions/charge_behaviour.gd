class_name ChargeBehaviour
extends ActionBehaviour
## Charge (docs/rules/movement.md; briefs 007 and 008b): a move action against
## a target model. The target, the route choice and the route are worked out
## when it is declared (ChargePlanner), then ChargeExecution rolls the D6 and
## hands the route to the movement process.


func needs_target() -> bool:
	return true


func plan_for(
	state: GameState, model: ModelState, _action: ActionDef, target_id: int, allow_rolls: bool = false,
	descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
) -> ActionPlan:
	return ChargePlanner.new(state, model.id, descent_mode).plan(target_id, allow_rolls)


func begin(state: GameState, model: ModelState, action: ActionDef, events: Array[GameEvent], plan: ActionPlan = null) -> void:
	ChargeExecution.start(state, model, action, plan as ChargePlan, events)


func move_budget_preview(state: GameState, model: ModelState) -> float:
	return TurnFlow.movement_budget(state, model, model.movement + ChargePlanner.DIE_SIDES)
