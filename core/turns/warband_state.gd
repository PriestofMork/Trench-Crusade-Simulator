class_name WarbandState
extends RefCounted
## Warband-wide state for one player: flags that rules read, such as "all
## success rolls are risky" after a failed morale test. Flags are plain ids so
## new rules add them as data.

const ALL_SUCCESS_ROLLS_RISKY: StringName = &"all_success_rolls_risky"

var player: int
var flags: Dictionary[StringName, bool] = {}


func _init(p_player: int) -> void:
	player = p_player


func has_flag(flag: StringName) -> bool:
	return flags.get(flag, false)
