class_name ActionBehaviour
extends RefCounted
## What an action does once it is taken. Subclasses override begin() (and,
## for actions with extra conditions, unavailable_reason()).


## Why `model` cannot take `action` now beyond the general rules (each action
## once, one move action), or "".
func unavailable_reason(_state: GameState, _model: ModelState, _action: ActionDef) -> String:
	return ""


## Carries out the action's start: moves, rolls, or pending decisions.
func begin(_state: GameState, _model: ModelState, _action: ActionDef, _events: Array[GameEvent]) -> void:
	pass


## If the action lets the model move, how far it could move if it took the
## action now (for the UI to preview), else -1.
func move_budget_preview(_state: GameState, _model: ModelState) -> float:
	return -1.0
