class_name ContextStepModifier
extends RollModifierProvider
## Plus or minus dice for every full `step` of a number in the roll's context,
## on rolls of the listed kinds. The fall rule is this (movement.md, Falling:
## +1 die on the injury roll per full 3" fallen): context id &"fall_inches",
## step 3, +1 die. Configured by data (core_rules.json, "context_dice").

var context_key: StringName
var label_format: String
var kinds: Array[RollRequest.Kind] = []
var step: float
var dice_per_step: int


func _init(
	p_id: StringName, p_context_key: StringName, p_label_format: String, p_kinds: Array[RollRequest.Kind],
	p_step: float, p_dice_per_step: int
) -> void:
	id = p_id
	context_key = p_context_key
	label_format = p_label_format
	kinds = p_kinds
	step = p_step
	dice_per_step = p_dice_per_step


func modifiers(_state: GameState, request: RollRequest) -> Array[RollModifier]:
	if not kinds.has(request.kind) or not request.context.has(context_key):
		return []
	var value: float = float(request.context[context_key])
	var steps: int = steps_for(value)
	if steps <= 0:
		return []
	return [RollModifier.new(label_format % value, steps * dice_per_step, false, id)]


## Full steps in `value`, with a little slack so 3.0 computed as 2.9999 counts as 3.
func steps_for(value: float) -> int:
	return floori((value + Transitions.HEIGHT_SLACK) / step)
