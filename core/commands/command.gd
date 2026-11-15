class_name Command
extends RefCounted
## Base class for every change to the game state. Run it with
## GameState.execute(), which calls validate() and then apply().


## Returns "" if the command may be applied to `state`, else the reason it may not.
func validate(_state: GameState) -> String:
	return ""


## Changes `state`. Only called after validate() returned "".
func apply(_state: GameState) -> void:
	pass
