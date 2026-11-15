class_name RollModifier
extends RefCounted
## One entry of a roll's breakdown: plus or minus dice, or a flag change. Made
## by modifier providers and roll choices, never inside the resolver.

## What the breakdown shows ("2 blood markers").
var label: String
## Plus (positive) or minus (negative) dice.
var dice: int = 0
## Whether this makes the roll risky.
var makes_risky: bool = false
## Id of the rule that made it, for tests and logs.
var source: StringName = &""


func _init(p_label: String, p_dice: int = 0, p_makes_risky: bool = false, p_source: StringName = &"") -> void:
	label = p_label
	dice = p_dice
	makes_risky = p_makes_risky
	source = p_source
