class_name WarbandFlagModifier
extends RollModifierProvider
## While the rolling player's warband has `flag`, rolls of the listed kinds get
## a modifier (for example "all success rolls are risky"). Configured by data
## (data/rules/core_rules.json, "warband_flags").

var flag: StringName
var label: String
var kinds: Array[RollRequest.Kind] = []
var dice: int = 0
var makes_risky: bool = false


func _init(
	p_flag: StringName, p_label: String, p_kinds: Array[RollRequest.Kind], p_dice: int, p_makes_risky: bool
) -> void:
	id = p_flag
	flag = p_flag
	label = p_label
	kinds = p_kinds
	dice = p_dice
	makes_risky = p_makes_risky


func modifiers(state: GameState, request: RollRequest) -> Array[RollModifier]:
	if request.roller < 0 or request.roller >= state.warbands.size():
		return []
	if not kinds.has(request.kind) or not state.warbands[request.roller].has_flag(flag):
		return []
	return [RollModifier.new(label, dice, makes_risky, id)]
