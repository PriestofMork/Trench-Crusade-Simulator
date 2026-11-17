class_name BeginActionCommand
extends Command
## `player` has `model_id` take `action_id`, against `target_id` for an action
## with a target (a charge). The first action starts the model's activation
## (ruling 2 of brief 005); a Down model stands up then. Each action at most
## once per activation, only one move action, and none that melee forbids
## (ruling 9 of brief 007).

var player: int
var model_id: int
var action_id: StringName
var target_id: int = -1
## For a charge, the route choice declared with it (ruling 2 of brief 008b):
## whether routes with climbs and jumps are allowed, and how drops of 3" or
## more are taken. Part of the command, so undo, redo and replay agree.
var allow_rolls: bool = false
var descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP

## What the action's behaviour worked out for the target, set by validate().
var _plan: ActionPlan = null


func _init(
	p_player: int, p_model_id: int, p_action_id: StringName, p_target_id: int = -1, p_allow_rolls: bool = false,
	p_descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
) -> void:
	player = p_player
	model_id = p_model_id
	action_id = p_action_id
	target_id = p_target_id
	allow_rolls = p_allow_rolls
	descent_mode = p_descent_mode


## The plan validate() worked out (a charge's path and needed roll), or null.
func plan() -> ActionPlan:
	return _plan


func validate(state: GameState) -> String:
	_plan = null
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return "No model with id %d." % model_id
	var error: String = TurnFlow.activation_error(state, player, model)
	if error != "":
		return error
	error = unavailable_reason(state, model, action_id)
	if error != "":
		return error
	var action: ActionDef = state.rules.action(action_id)
	if not action.behaviour.needs_target():
		return "" if target_id == -1 else "%s takes no target." % action.label
	_plan = action.behaviour.plan_for(state, model, action, target_id, allow_rolls, descent_mode)
	return _plan.error


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	var model: ModelState = state.get_model(model_id)
	var action: ActionDef = state.rules.action(action_id)
	if action.behaviour.needs_target() and _plan == null:
		validate(state)
	var plan_used: ActionPlan = _plan
	_plan = null
	var t: TurnState = state.turn
	# Doing anything else finishes an open move (ruling 1 of brief 005).
	TurnFlow.finish_open_move(state, events, "another action")
	if t.active_model_id != model_id:
		TurnFlow.begin_activation(state, model, events)
	t.actions_used.append(action_id)
	if action.move_action:
		t.move_action_used = true
	var data: Dictionary = {"action_id": action_id}
	if target_id != -1:
		data["target_id"] = target_id
		data["allow_rolls"] = allow_rolls
	events.append(GameEvent.new(GameEvent.Kind.ACTION_STARTED, player, model_id, data))
	action.behaviour.begin(state, model, action, events, plan_used)
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
	match action.melee:
		ActionDef.Melee.FORBIDDEN:
			if MeleeZone.in_melee(state, model):
				return "In melee: the model can only leave by Retreating."
		ActionDef.Melee.REQUIRED:
			if not MeleeZone.in_melee(state, model):
				return "%s is only for a model in melee." % action.label
	return action.behaviour.unavailable_reason(state, model, action)
