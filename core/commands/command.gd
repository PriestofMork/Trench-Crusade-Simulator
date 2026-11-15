class_name Command
extends RefCounted
## Base class for every change to the game state. Run it with
## GameState.execute() or submit(), which call validate() and then apply().
## Rule commands carry the player sending them and are rejected unless the
## decision or the activation is that player's; override commands (see
## OverrideCommand) are the manual escape hatch and are not.


## Returns "" if the command may be applied to `state`, else the reason it may not.
func validate(_state: GameState) -> String:
	return ""


## Changes `state` and returns the events of what happened, in order. Only
## called after validate() returned "".
func apply(_state: GameState) -> Array[GameEvent]:
	return []
