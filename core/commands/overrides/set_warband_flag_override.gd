class_name SetWarbandFlagOverride
extends OverrideCommand
## Sets or clears a warband flag for a player, such as
## WarbandState.ALL_SUCCESS_ROLLS_RISKY.

var player: int
var flag: StringName
var value: bool


func _init(p_player: int, p_flag: StringName, p_value: bool) -> void:
	player = p_player
	flag = p_flag
	value = p_value


func validate(state: GameState) -> String:
	if player < 0 or player >= state.warbands.size():
		return "Player must be 0 or 1, got %d." % player
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	state.warbands[player].flags[flag] = value
	return _override_event(-1, "Player %d: %s %s" % [player + 1, flag, "on" if value else "off"])
