extends GutTest
## The resolver alone: plus and minus dice, keeping, success and criticals.


## A dice service that replays fixed values, so results can be checked by hand.
class FixedDice:
	extends Dice
	var values: Array[int] = []
	var next: int = 0

	func _init(p_values: Array[int]) -> void:
		values = p_values

	func roll_d6() -> int:
		next += 1
		return values[(next - 1) % values.size()]


func _success(allows_critical: bool = false) -> RollRequest:
	var request: RollRequest = RollRequest.success(0, 1, &"test", false, "Test")
	request.allows_critical = allows_critical
	return request


func _mods(deltas: Array[int]) -> Array[RollModifier]:
	var result: Array[RollModifier] = []
	for delta: int in deltas:
		result.append(RollModifier.new("%+d" % delta, delta))
	return result


func test_plain_success_roll_keeps_two() -> void:
	var result: RollResult = RollResolver.resolve(_success(), [], FixedDice.new([3, 4]))
	assert_eq(result.dice, [3, 4] as Array[int])
	assert_eq(result.kept, [true, true] as Array[bool])
	assert_eq(result.total, 7)
	assert_eq(result.outcome, RollResult.Outcome.SUCCESS, "7+ succeeds")
	var fail: RollResult = RollResolver.resolve(_success(), [], FixedDice.new([2, 4]))
	assert_eq(fail.outcome, RollResult.Outcome.FAILURE, "6 fails")


func test_plus_dice_keep_the_highest() -> void:
	var result: RollResult = RollResolver.resolve(_success(), _mods([1, 1]), FixedDice.new([1, 6, 2, 5]))
	assert_eq(result.dice.size(), 4)
	assert_eq(result.kept, [false, true, false, true] as Array[bool])
	assert_eq(result.total, 11)


func test_minus_dice_keep_the_lowest() -> void:
	var result: RollResult = RollResolver.resolve(_success(), _mods([-1]), FixedDice.new([6, 2, 5]))
	assert_eq(result.kept, [false, true, true] as Array[bool])
	assert_eq(result.total, 7)


func test_plus_and_minus_cancel_one_for_one() -> void:
	var result: RollResult = RollResolver.resolve(_success(), _mods([2, -1, -1, 1]), FixedDice.new([4, 4, 1]))
	assert_eq(result.plus_dice, 3)
	assert_eq(result.minus_dice, 2)
	assert_eq(result.cancelled_pairs(), 2)
	assert_eq(result.net_dice, 1)
	assert_eq(result.dice.size(), 3, "one plus die left")
	var even: RollResult = RollResolver.resolve(_success(), _mods([1, -1]), FixedDice.new([4, 4]))
	assert_eq(even.dice.size(), 2, "fully cancelled")


func test_equal_values_keep_the_earlier_die() -> void:
	assert_eq(RollResolver.keep([3, 5, 3] as Array[int], 2, true), [true, true, false] as Array[bool])
	assert_eq(RollResolver.keep([3, 5, 3] as Array[int], 2, false), [true, false, true] as Array[bool])


func test_three_dice_kept_at_plus_one_rolls_four() -> void:
	var request: RollRequest = RollRequest.injury(0, 1, 2, 3)
	var result: RollResult = RollResolver.resolve(request, _mods([1]), FixedDice.new([2, 6, 1, 5]))
	assert_eq(result.dice.size(), 4)
	assert_eq(result.kept, [true, true, false, true] as Array[bool])
	assert_eq(result.total, 13)
	assert_eq(result.outcome, RollResult.Outcome.NONE, "injury effects are not in this brief")


func test_injury_roll_with_minus_dice() -> void:
	var request: RollRequest = RollRequest.injury(0, 1, 2)
	var result: RollResult = RollResolver.resolve(request, _mods([1, -3]), FixedDice.new([6, 1, 2, 5]))
	assert_eq(result.dice.size(), 4, "net -2: two extra dice")
	assert_eq(result.kept_dice(), [1, 2] as Array[int])


func test_critical_only_when_allowed() -> void:
	var plain: RollResult = RollResolver.resolve(_success(false), [], FixedDice.new([6, 6]))
	assert_eq(plain.outcome, RollResult.Outcome.SUCCESS)
	var attack: RollResult = RollResolver.resolve(_success(true), [], FixedDice.new([6, 6]))
	assert_eq(attack.outcome, RollResult.Outcome.CRITICAL)
	assert_true(attack.is_success())
	var eleven: RollResult = RollResolver.resolve(_success(true), [], FixedDice.new([5, 6]))
	assert_eq(eleven.outcome, RollResult.Outcome.SUCCESS)


func test_risky_from_request_or_modifier() -> void:
	var request: RollRequest = _success()
	assert_false(RollResolver.resolve(request, [], FixedDice.new([1, 1])).risky)
	var flag: Array[RollModifier] = [RollModifier.new("risky", 0, true)]
	assert_true(RollResolver.resolve(request, flag, FixedDice.new([1, 1])).risky)
	request.risky = true
	assert_true(RollResolver.resolve(request, [], FixedDice.new([1, 1])).risky)


func test_d6_keeps_one() -> void:
	var request: RollRequest = RollRequest.new(RollRequest.Kind.D6, 0, 1)
	var result: RollResult = RollResolver.resolve(request, _mods([1]), FixedDice.new([2, 5]))
	assert_eq(result.total, 5)


func test_roll_off() -> void:
	var win: RollResult = RollResolver.resolve(RollRequest.roll_off(), [], FixedDice.new([2, 5]))
	assert_eq(win.winner, 1)
	var draw: RollResult = RollResolver.resolve(RollRequest.roll_off(), [], FixedDice.new([4, 4]))
	assert_eq(draw.winner, -1)


func test_a_fixed_seed_gives_a_fixed_result() -> void:
	var first: RollResult = RollResolver.resolve(_success(), _mods([1]), Dice.new(42))
	var second: RollResult = RollResolver.resolve(_success(), _mods([1]), Dice.new(42))
	assert_eq(first.dice, second.dice)
	assert_eq(first.total, second.total)
	assert_eq(first.dice.size(), 3)
