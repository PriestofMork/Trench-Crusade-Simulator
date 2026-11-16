class_name TurnState
extends RefCounted
## Where the game is in the turn sequence (docs/rules/turn-structure.md).
## Plain data; changed only through TurnFlow by commands.

## 0 until the game starts.
var turn: int = 0
## The player who chose (or was chosen) to activate first this turn, or -1.
var first_player: int = -1
## The player whose turn it is to activate a model, or -1 while that is not
## decided yet.
var player_to_act: int = -1
## The model whose activation is under way, or -1 between activations.
var active_model_id: int = -1
## Ids of the models that have activated (or are activating) this turn.
var activated: Dictionary[int, bool] = {}
## Ids of the actions the active model has taken this activation.
var actions_used: Array[StringName] = []
## Whether the active model has taken a move action this activation.
var move_action_used: bool = false
## Whether the active model stood up at the start of this activation.
var stood_up: bool = false
## Ids of the models the active model charged this activation (ruling 8 of
## brief 007: every enemy within 1" where the charge ended), for later rules.
var charged: Array[int] = []


func has_activated(model_id: int) -> bool:
	return activated.has(model_id)


func action_used(action_id: StringName) -> bool:
	return actions_used.has(action_id)
