class_name Resolution
extends RefCounted
## Something under way across several commands for one model: a move with
## rolls in it now, a charge or an attack later. It lives on
## GameState.resolution while it waits for rolls and their pre-roll choices,
## and is carried on by the roll's on_resolved callback, which reads it back
## from the state (so undo, redo and replay restore it like any other state).
##
## Rules that would end the model's activation part-way through (a failed
## risky roll, going Down) do not cut the resolution short: they ask
## TurnFlow.end_activation_when_done(), which records the reason here, and
## the resolution ends the activation once it has finished what it must
## (a fall, its injury roll).

var model_id: int = -1
## Why the activation ends once this is done, or "" if it does not.
var end_reason: String = ""


## A copy for undo snapshots. Subclasses copy their own fields too.
func copy() -> Resolution:
	var result: Resolution = Resolution.new()
	copy_into(result)
	return result


func copy_into(target: Resolution) -> void:
	target.model_id = model_id
	target.end_reason = end_reason
