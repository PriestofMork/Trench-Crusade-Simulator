class_name ChooseFirstPlayerCommand
extends Command
## Answers CHOOSE_FIRST_PLAYER: `player` decides that `first` activates first.

var player: int
var first: int


func _init(p_player: int, p_first: int) -> void:
	player = p_player
	first = p_first


func validate(state: GameState) -> String:
	if first != 0 and first != 1:
		return "First player must be 0 or 1, got %d." % first
	return PendingDecision.check(state, PendingDecision.Kind.CHOOSE_FIRST_PLAYER, player)


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	TurnFlow.choose_first(state, first, events)
	return events
