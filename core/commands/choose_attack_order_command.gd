class_name ChooseAttackOrderCommand
extends Command
## Answers FREE_ATTACK_ORDER: `player` (the retreating model's opponent) gives
## the order of the free attacks, each attacker once (ruling 10 of brief 007).

var player: int
var order: Array[int] = []


func _init(p_player: int, p_order: Array[int]) -> void:
	player = p_player
	order = p_order.duplicate()


func validate(state: GameState) -> String:
	var error: String = PendingDecision.check(state, PendingDecision.Kind.FREE_ATTACK_ORDER, player)
	if error != "":
		return error
	return RetreatBehaviour.order_error(state, order)


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	RetreatBehaviour.set_order(state, order, events)
	return events
