extends GutTest


func test_same_seed_gives_same_sequence() -> void:
	var a: Dice = Dice.new(12345)
	var b: Dice = Dice.new(12345)
	assert_eq(a.roll(50), b.roll(50))


func test_different_seeds_give_different_sequences() -> void:
	var a: Dice = Dice.new(1)
	var b: Dice = Dice.new(2)
	assert_ne(a.roll(50), b.roll(50))


func test_rolls_stay_within_one_to_six() -> void:
	var dice: Dice = Dice.new(7)
	var seen: Dictionary[int, bool] = {}
	for result: int in dice.roll(1000):
		assert_between(result, 1, 6)
		seen[result] = true
	assert_eq(seen.size(), 6, "all six faces should come up in 1000 rolls")


func test_roll_returns_requested_count() -> void:
	var dice: Dice = Dice.new(3)
	assert_eq(dice.roll(4).size(), 4)
	assert_eq(dice.roll(0).size(), 0)
