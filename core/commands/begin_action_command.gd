class_name BeginActionCommand
extends Command
## `player` has `model_id` take `action_id`. The first action starts the
## model's activation (ruling 2 of brief 005); a Down model stands up then.
## Each action at most once per activation, and only one move action.

var player: int
var model_id: int
var action_id: StringName


func _init(p_player: int, p_model_id: int, p_action_id: StringName) -> void:
	player = p_player
	model_id = p_model_id
	action_id = p_action_id


func validate(state: GameState) -> String:
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return "No model with id %d." % model_id
	var error: String = TurnFlow.activation_error(state, player, model)
	if error != "":
		return error
	return unavailable_reason(state, model, action_id)


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	var model: ModelState = state.get_model(model_id)
	var action: ActionDef = state.rules.action(action_id)
	var t: TurnState = state.turn
	# Doing anything else finishes an open move (ruling 1 of brief 005).
	TurnFlow.finish_open_move(state, events, "another action")
	if t.active_model_id != model_id:
		TurnFlow.begin_activation(state, model, events)
	t.actions_used.append(action_id)
	if action.move_action:
		t.move_action_used = true
	events.append(GameEvent.new(GameEvent.Kind.ACTION_STARTED, player, model_id, {"action_id": action_id}))
	action.behaviour.begin(state, model, action, events)
	return events


## Why `model` cannot take `p_action_id` in its current or next activation
## (the action rules only, not whose turn it is), or "".
static func unavailable_reason(state: GameState, model: ModelState, p_action_id: StringName) -> String:
	var action: ActionDef = state.rules.action(p_action_id)
	if action == null:
		return "No action '%s'." % p_action_id
	var t: TurnState = state.turn
	if t.active_model_id == model.id:
		if t.action_used(p_action_id):
			return "%s has already been used this activation." % action.label
		if action.move_action and t.move_action_used:
			return "Only one move action per activation."
	elif t.has_activated(model.id):
		return "Model %d has already activated this turn." % model.id
	return action.behaviour.unavailable_reason(state, model, action)
