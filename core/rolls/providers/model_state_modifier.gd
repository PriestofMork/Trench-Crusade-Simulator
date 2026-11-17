class_name ModelStateModifier
extends RollModifierProvider
## Plus or minus dice on rolls of the listed kinds made by a model while it is
## in a state (a ModelState flag such as `down`). The Down rule is this
## (docs/rules/markers.md, "Down"; ruling 11 of brief 008b): every success roll
## made by a Down model gets -1 die. Configured by data (core_rules.json,
## "model_states"). The model is the roll's actor.

## The ModelState property that must be true.
var state_flag: StringName
var label: String
var kinds: Array[RollRequest.Kind] = []
var dice: int = 0


func _init(p_id: StringName, p_state_flag: StringName, p_label: String, p_kinds: Array[RollRequest.Kind], p_dice: int) -> void:
	id = p_id
	state_flag = p_state_flag
	label = p_label
	kinds = p_kinds
	dice = p_dice


func modifiers(state: GameState, request: RollRequest) -> Array[RollModifier]:
	if not kinds.has(request.kind):
		return []
	var model: ModelState = state.get_model(request.actor_id)
	if model == null or not bool(model.get(state_flag)):
		return []
	return [RollModifier.new(label, dice, false, id)]
