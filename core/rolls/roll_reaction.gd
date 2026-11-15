class_name RollReaction
extends RefCounted
## A rule that acts on a roll's result (for example "a failed risky roll ends
## the activation", or later "on a critical, +1 die on the injury roll").
## Register it in the Ruleset; it runs for every resolved roll, before the
## requester's on_resolved.

var id: StringName = &""


func react(_state: GameState, _result: RollResult, _events: Array[GameEvent]) -> void:
	pass
