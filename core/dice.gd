class_name Dice
extends RefCounted
## The single seeded source of randomness for the rules engine.
## Nothing else may generate random numbers. Same seed, same sequence.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


func roll_d6() -> int:
	return _rng.randi_range(1, 6)


## Rolls `count` D6 and returns the results in roll order.
func roll(count: int) -> Array[int]:
	var results: Array[int] = []
	for i: int in count:
		results.append(roll_d6())
	return results


## The generator's position in its sequence, for undo snapshots.
func get_state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value
