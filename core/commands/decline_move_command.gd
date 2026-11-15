class_name DeclineMoveCommand
extends Command
## Finishes an open move (the Finish move button); what is left is lost.

var player: int


func _init(p_player: int) -> void:
	player = p_player


func validate(state: GameState) -> String:
	return PendingDecision.check(state, PendingDecision.Kind.MOVE, player)


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	TurnFlow.finish_open_move(state, events, "finished by the player")
	return events
