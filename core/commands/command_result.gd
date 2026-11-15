class_name CommandResult
extends RefCounted
## What GameState.submit() returns: why the command was rejected, or the
## events of what it did.

var error: String = ""
var events: Array[GameEvent] = []


func ok() -> bool:
	return error == ""
