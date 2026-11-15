class_name RollChoiceCommand
extends Command
## Answers ROLL_CHOICE: `player` spends some of what the current pre-roll
## choice offers, such as markers: one count per option (0 to decline). A
## choice with one option may be answered with `amount` alone.

var player: int
var amounts: Array[int] = []


func _init(p_player: int, p_amount: int = 0, p_amounts: Array[int] = []) -> void:
	player = p_player
	amounts = p_amounts.duplicate() if not p_amounts.is_empty() else ([p_amount] as Array[int])


func validate(state: GameState) -> String:
	return RollPipeline.choice_error(state, player, _amounts_for(state))


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	RollPipeline.answer_choice(state, _amounts_for(state), events)
	return events


## A single amount answering a choice of several options spends it on the
## first and nothing on the others.
func _amounts_for(state: GameState) -> Array[int]:
	var roll: ActiveRoll = state.active_roll
	if roll == null or roll.current_choice == null or amounts.size() != 1:
		return amounts
	var result: Array[int] = amounts.duplicate()
	result.resize(roll.current_choice.options.size())
	return result
