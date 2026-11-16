class_name GameSnapshot
extends RefCounted
## A copy of everything a command can change, taken before it runs, so it can
## be undone: the models, the turn and activation state, warband flags, the
## pending decision, the roll under way, the resolution under way (a move
## with rolls in it), the dice service's position and the length of the
## command log. Restoring the dice too means that repeating a
## command after undoing it rolls the same dice.
##
## Terrain is not included: it only changes during set-up, before undo starts.

var _models: Array[Dictionary] = []
var _next_model_id: int
var _turn: TurnState
var _flags: Array[Dictionary] = []
var _pending: PendingDecision
var _active_roll: ActiveRoll
var _resolution: Resolution
var _dice_state: int
var _history_size: int


static func take(state: GameState) -> GameSnapshot:
	var snapshot: GameSnapshot = GameSnapshot.new()
	for model: ModelState in state.models:
		snapshot._models.append({
			"id": model.id, "player": model.player, "position": model.position, "base_mm": model.base_mm,
			"movement": model.movement, "down": model.down, "out_of_action": model.out_of_action, "markers": model.markers.duplicate(),
		})
	snapshot._next_model_id = state._next_model_id
	snapshot._turn = _copy_turn(state.turn)
	for warband: WarbandState in state.warbands:
		snapshot._flags.append(warband.flags.duplicate())
	# Pending decisions are never changed once made, so sharing one is safe.
	snapshot._pending = state.pending
	snapshot._active_roll = _copy_roll(state.active_roll)
	snapshot._resolution = state.resolution.copy() if state.resolution != null else null
	snapshot._dice_state = state.dice.get_state()
	snapshot._history_size = state.history.size()
	return snapshot


## Puts `state` back as it was. Models keep their objects where they still exist.
func restore(state: GameState) -> void:
	var models: Array[ModelState] = []
	for data: Dictionary in _models:
		var model: ModelState = state.get_model(data["id"])
		if model == null:
			model = ModelState.new(data["id"], data["player"], data["position"], data["base_mm"], data["movement"])
		model.position = data["position"]
		model.down = data["down"]
		model.out_of_action = data["out_of_action"]
		var markers: Dictionary = data["markers"]
		model.markers.clear()
		for kind: StringName in markers:
			model.markers[kind] = markers[kind]
		models.append(model)
	state.models = models
	state._next_model_id = _next_model_id
	state.turn = _copy_turn(_turn)
	for i: int in state.warbands.size():
		var flags: Dictionary = _flags[i]
		state.warbands[i].flags.clear()
		for flag: StringName in flags:
			state.warbands[i].flags[flag] = flags[flag]
	state.pending = _pending
	state.active_roll = _copy_roll(_active_roll)
	state.resolution = _resolution.copy() if _resolution != null else null
	state.dice.set_state(_dice_state)
	state.history.resize(_history_size)


static func _copy_turn(source: TurnState) -> TurnState:
	var copy: TurnState = TurnState.new()
	copy.turn = source.turn
	copy.first_player = source.first_player
	copy.player_to_act = source.player_to_act
	copy.active_model_id = source.active_model_id
	copy.activated = source.activated.duplicate()
	copy.actions_used = source.actions_used.duplicate()
	copy.move_action_used = source.move_action_used
	copy.stood_up = source.stood_up
	copy.charged = source.charged.duplicate()
	return copy


static func _copy_roll(source: ActiveRoll) -> ActiveRoll:
	if source == null:
		return null
	var copy: ActiveRoll = ActiveRoll.new(source.request)
	copy.modifiers = source.modifiers.duplicate()
	copy.next_choice = source.next_choice
	copy.current_choice = source.current_choice
	return copy
