class_name RollOffCommand
extends Command
## Answers ROLL_OFF: the players roll off. Either player may send it.

var player: int


func _init(p_player: int) -> void:
	player = p_player


func validate(state: GameState) -> String:
	return PendingDecision.check(state, PendingDecision.Kind.ROLL_OFF, player)


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	TurnFlow.roll_off(state, events)
	return events
