class_name DiceRig
extends RefCounted
## Test helper: finds a dice seed whose next rolls come out a certain way.


## A seed whose next `count` dice, keeping `kept` of the highest (or lowest),
## total between `low` and `high`; -1 if none of the first 5000 seeds does.
static func seed_for_total(count: int, kept: int, highest: bool, low: int, high: int) -> int:
	for seed_value: int in 5000:
		var probe: Dice = Dice.new(seed_value)
		var values: Array[int] = probe.roll(count)
		var keep: Array[bool] = RollResolver.keep(values, kept, highest)
		var total: int = 0
		for i: int in values.size():
			if keep[i]:
				total += values[i]
		if total >= low and total <= high:
			return seed_value
	return -1


## A seed whose next rolls total within each range in turn: `rolls` is a list
## of [count, kept, highest, low, high]. -1 if none of the first 20000 seeds does.
static func seed_for_sequence(rolls: Array) -> int:
	for seed_value: int in 20000:
		var probe: Dice = Dice.new(seed_value)
		var ok: bool = true
		for spec: Array in rolls:
			var values: Array[int] = probe.roll(int(spec[0]))
			var keep: Array[bool] = RollResolver.keep(values, int(spec[1]), bool(spec[2]))
			var total: int = 0
			for i: int in values.size():
				if keep[i]:
					total += values[i]
			if total < int(spec[3]) or total > int(spec[4]):
				ok = false
				break
		if ok:
			return seed_value
	return -1


## Sets `state`'s dice so the next rolls are as seed_for_total() describes.
static func rig(state: GameState, count: int, kept: int, highest: bool, low: int, high: int) -> bool:
	var found: int = seed_for_total(count, kept, highest, low, high)
	if found < 0:
		return false
	state.dice = Dice.new(found)
	return true


static func rig_sequence(state: GameState, rolls: Array) -> bool:
	var found: int = seed_for_sequence(rolls)
	if found < 0:
		return false
	state.dice = Dice.new(found)
	return true
