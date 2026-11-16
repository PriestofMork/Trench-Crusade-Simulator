class_name FreeAttackHook
extends RefCounted
## The seam for free melee attacks (Retreat, ruling 10 of brief 007): resolve
## a free melee attack by `attacker_id` against `target_id`. Reached through
## GameState.rules.free_attack, so brief 009 only replaces the implementation.
##
## The attack may finish at once or later, after rolls and their pending
## decisions (later commands): either way the implementation calls
## `done.call(state, events)` exactly once when it is over, with the state and
## event list of the command it finishes in. `done` keeps no state of its own
## (it reads what is under way from GameState.resolution), so it may be kept
## in a roll request across commands, undo and replay.


func resolve(_state: GameState, _attacker_id: int, _target_id: int, _events: Array[GameEvent], done: Callable) -> void:
	push_error("FreeAttackHook: no implementation")
	done.call(_state, _events)
