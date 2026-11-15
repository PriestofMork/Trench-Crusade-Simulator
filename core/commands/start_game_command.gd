class_name StartGameCommand
extends Command
## Ends set-up and starts turn 1 (which begins with the first-player choice).


func validate(state: GameState) -> String:
	if state.turn.turn != 0:
		return "The game has already started."
	if state.models.is_empty():
		return "There are no models on the table."
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	TurnFlow.start_turn(state, events)
	return events
