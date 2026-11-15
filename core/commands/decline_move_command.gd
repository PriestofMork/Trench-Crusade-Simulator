class_name DeclineMoveCommand
extends Command
## Answers a pending MOVE by staying put; the granted move is lost.

var player: int


func _init(p_player: int) -> void:
	player = p_player


func validate(state: GameState) -> String:
	return PendingDecision.check(state, PendingDecision.Kind.MOVE, player)


func apply(state: GameState) -> Array[GameEvent]:
	var model_id: int = state.pending.model_id
	state.pending = null
	return [GameEvent.new(GameEvent.Kind.MOVE_DECLINED, player, model_id)]
