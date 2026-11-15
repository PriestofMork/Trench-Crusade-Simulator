class_name RollChoiceCommand
extends Command
## Answers ROLL_CHOICE: `player` spends `amount` (0 to decline) of what the
## current pre-roll choice offers, such as markers.

var player: int
var amount: int


func _init(p_player: int, p_amount: int) -> void:
	player = p_player
	amount = p_amount


func validate(state: GameState) -> String:
	return RollPipeline.choice_error(state, player, amount)


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	RollPipeline.answer_choice(state, amount, events)
	return events
