class_name RollChoiceProvider
extends RefCounted
## Something a player may spend on a roll before the dice are rolled, such as
## markers. Providers are asked in Ruleset order; each that offers something
## becomes a pending decision.

var id: StringName = &""


## What may be spent on `request`, or null when there is nothing to spend.
func offer(_state: GameState, _request: RollRequest) -> RollChoice:
	return null


## Why spending `amounts` (one count per option of the choice) is not allowed
## now, or "".
func spend_error(_state: GameState, choice: RollChoice, amounts: Array[int]) -> String:
	return choice.amounts_error(amounts)


## Spends `amounts` (removing what is spent) and returns the modifiers it gives.
func spend(_state: GameState, _request: RollRequest, _choice: RollChoice, _amounts: Array[int]) -> Array[RollModifier]:
	return []
