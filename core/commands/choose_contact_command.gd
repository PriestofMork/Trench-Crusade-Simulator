class_name ChooseContactCommand
extends Command
## Answers CHARGE_CONTACT: `player` has the charger end at position `index`
## of those offered around the target's base (ruling 8 of brief 007).

var player: int
var index: int


func _init(p_player: int, p_index: int) -> void:
	player = p_player
	index = p_index


func validate(state: GameState) -> String:
	var error: String = PendingDecision.check(state, PendingDecision.Kind.CHARGE_CONTACT, player)
	if error != "":
		return error
	if index < 0 or index >= state.pending.positions.size():
		return "No contact position %d (there are %d)." % [index, state.pending.positions.size()]
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	ChargeExecution.choose_contact(state, index, events)
	return events
