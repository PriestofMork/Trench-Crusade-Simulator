class_name ActionBehaviour
extends RefCounted
## What an action does once it is taken. Subclasses override begin() (and,
## for actions with extra conditions, unavailable_reason(); for actions taken
## against a target, needs_target() and plan_for()).


## Why `model` cannot take `action` now beyond the general rules (each action
## once, one move action, melee), or "".
func unavailable_reason(_state: GameState, _model: ModelState, _action: ActionDef) -> String:
	return ""


## Whether the action is taken against a target model (a charge).
func needs_target() -> bool:
	return false


## For an action with a target: checks `target_id` and works out what taking
## the action against it means. The plan's error says why it may not be taken.
func plan_for(_state: GameState, _model: ModelState, _action: ActionDef, target_id: int) -> ActionPlan:
	var plan: ActionPlan = ActionPlan.new()
	plan.target_id = target_id
	plan.error = "This action takes no target."
	return plan


## Carries out the action's start: moves, rolls, or pending decisions. `plan`
## is what plan_for() worked out, for an action with a target, else null.
func begin(_state: GameState, _model: ModelState, _action: ActionDef, _events: Array[GameEvent], _plan: ActionPlan = null) -> void:
	pass


## If the action lets the model move, how far it could move if it took the
## action now (for the UI to preview), else -1.
func move_budget_preview(_state: GameState, _model: ModelState) -> float:
	return -1.0
