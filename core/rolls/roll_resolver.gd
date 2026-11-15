class_name RollResolver
extends RefCounted
## Turns a request and its collected modifiers into a result, rolling through
## the dice service (docs/rules/rolls.md). Knows only dice: plus and minus dice
## cancel one for one; each remaining one adds a die, keeping the highest
## (plus) or lowest (minus) `dice_kept`; success rolls succeed on 7+ and are
## critical on 12+ when the request allows it. It never looks at what the
## modifiers are for.


static func resolve(request: RollRequest, modifiers: Array[RollModifier], dice: Dice) -> RollResult:
	var result: RollResult = RollResult.new()
	result.request = request
	result.modifiers = modifiers.duplicate()
	result.risky = request.risky
	for modifier: RollModifier in modifiers:
		if modifier.dice > 0:
			result.plus_dice += modifier.dice
		elif modifier.dice < 0:
			result.minus_dice -= modifier.dice
		if modifier.makes_risky:
			result.risky = true
	result.net_dice = result.plus_dice - result.minus_dice

	if request.kind == RollRequest.Kind.ROLL_OFF:
		# One die each; dice modifiers do not apply to roll-offs.
		result.dice = dice.roll(2)
		result.kept = [true, true]
		if result.dice[0] != result.dice[1]:
			result.winner = 0 if result.dice[0] > result.dice[1] else 1
		return result

	result.dice = dice.roll(request.dice_kept + absi(result.net_dice))
	result.kept = keep(result.dice, request.dice_kept, result.net_dice >= 0)
	for value: int in result.kept_dice():
		result.total += value
	if request.kind == RollRequest.Kind.SUCCESS:
		if request.allows_critical and result.total >= RollRequest.CRITICAL_TARGET:
			result.outcome = RollResult.Outcome.CRITICAL
		elif result.total >= RollRequest.SUCCESS_TARGET:
			result.outcome = RollResult.Outcome.SUCCESS
		else:
			result.outcome = RollResult.Outcome.FAILURE
	return result


## Which of `values` are kept: the `count` highest (or lowest), the earlier
## die first among equal values.
static func keep(values: Array[int], count: int, highest: bool) -> Array[bool]:
	var order: Array[int] = []
	for i: int in values.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if values[a] != values[b]:
			return values[a] > values[b] if highest else values[a] < values[b]
		return a < b
	)
	var kept: Array[bool] = []
	kept.resize(values.size())
	kept.fill(false)
	for k: int in mini(count, order.size()):
		kept[order[k]] = true
	return kept
