class_name RollChoiceProvider
extends RefCounted
## Something a player may spend on a roll before the dice are rolled, such as
## markers. Providers are asked in Ruleset order; each that offers something
## becomes a pending decision.

var id: StringName = &""


## What may be spent on `request`, or null when there is nothing to spend.
func offer(_state: GameState, _request: RollRequest) -> RollChoice:
	return null


## Why spending `amount` is not allowed now, or "".
func spend_error(_state: GameState, choice: RollChoice, amount: int) -> String:
	if amount < 0 or amount > choice.maximum:
		return "Choose between 0 and %d." % choice.maximum
	return ""


## Spends `amount` (removing what is spent) and returns the modifiers it gives.
func spend(_state: GameState, _request: RollRequest, _choice: RollChoice, _amount: int) -> Array[RollModifier]:
	return []
