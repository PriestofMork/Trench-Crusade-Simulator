class_name RollResult
extends RefCounted
## Everything about a resolved roll: each die rolled, which were kept, the
## modifiers applied, the total and the outcome.

enum Outcome { NONE, SUCCESS, FAILURE, CRITICAL }

var request: RollRequest
## Every die rolled, in roll order. For a roll-off: [player 0's, player 1's].
var dice: Array[int] = []
## Parallel to `dice`: whether that die counts.
var kept: Array[bool] = []
var modifiers: Array[RollModifier] = []
## Sums of the plus and minus dice before cancelling (minus as a positive count).
var plus_dice: int = 0
var minus_dice: int = 0
## Plus dice minus minus dice: extra dice rolled, keeping the highest (> 0) or lowest (< 0).
var net_dice: int = 0
var total: int = 0
var outcome: Outcome = Outcome.NONE
## Whether the roll was risky after modifiers.
var risky: bool = false
## Roll-off only: the winning player, or -1 on a draw.
var winner: int = -1


func cancelled_pairs() -> int:
	return mini(plus_dice, minus_dice)


func is_success() -> bool:
	return outcome == Outcome.SUCCESS or outcome == Outcome.CRITICAL


func is_failure() -> bool:
	return outcome == Outcome.FAILURE


func kept_dice() -> Array[int]:
	var values: Array[int] = []
	for i: int in dice.size():
		if kept[i]:
			values.append(dice[i])
	return values


func outcome_name() -> String:
	return Outcome.keys()[outcome]


func describe() -> String:
	if request != null and request.kind == RollRequest.Kind.ROLL_OFF:
		return "roll-off %s winner %d" % [str(dice), winner]
	return "%s kept %s total %d %s%s" % [
		str(dice), str(kept_dice()), total, outcome_name(), " risky" if risky else ""
	]
