class_name RollModifierProvider
extends RefCounted
## Something that adds modifiers to rolls automatically (a profile, a weapon
## keyword, a situation, a warband flag, an ability). Register it in the
## Ruleset; the pipeline asks every provider for every roll.

var id: StringName = &""


## Modifiers this rule adds to `request` (empty if it does not apply).
func modifiers(_state: GameState, _request: RollRequest) -> Array[RollModifier]:
	return []
