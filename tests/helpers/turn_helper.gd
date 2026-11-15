class_name TurnHelper
extends RefCounted
## Test helpers that drive the turn sequence through ordinary commands.


## Brings `state` to a pending Move for `model_id` (starting the game, rolling
## off, choosing first player and ending other activations as needed), so
## tests about movement geometry can send a MoveCommand.
static func grant_move(state: GameState, model_id: int) -> void:
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return
	if state.turn.turn == 0:
		_run(state, StartGameCommand.new())
	for guard: int in 200:
		var pending: PendingDecision = state.pending
		if pending != null:
			match pending.kind:
				PendingDecision.Kind.MOVE:
					if pending.model_id == model_id:
						return
					_run(state, EndActivationCommand.new(pending.player, pending.model_id))
				PendingDecision.Kind.ROLL_OFF:
					_run(state, RollOffCommand.new(0))
				PendingDecision.Kind.CHOOSE_FIRST_PLAYER:
					_run(state, ChooseFirstPlayerCommand.new(pending.player, model.player))
				PendingDecision.Kind.ROLL_CHOICE:
					_run(state, RollChoiceCommand.new(pending.player, 0))
			continue
		var t: TurnState = state.turn
		if t.active_model_id != -1 and t.active_model_id != model_id:
			_run(state, EndActivationCommand.new(t.player_to_act, t.active_model_id))
			continue
		var usable: bool = (
			t.player_to_act == model.player
			and BeginActionCommand.unavailable_reason(state, model, &"move") == ""
		)
		if usable:
			_run(state, BeginActionCommand.new(model.player, model_id, &"move"))
			continue
		if t.active_model_id == model_id:
			_run(state, EndActivationCommand.new(model.player, model_id))
			continue
		# Pass the other player's (or this player's other) models until it is this one's go.
		_run(state, EndActivationCommand.new(t.player_to_act, _other_unactivated(state, t.player_to_act, model_id)))
	push_error("TurnHelper: could not grant a move to model %d" % model_id)


## A MoveCommand for `model_id` along `waypoints`, after granting it a move.
static func move(state: GameState, model_id: int, waypoints: Array[Vector3]) -> MoveCommand:
	grant_move(state, model_id)
	var model: ModelState = state.get_model(model_id)
	return MoveCommand.new(model.player if model != null else 0, model_id, waypoints)


## Answers every pending decision the simplest way (roll off, the chooser goes
## first, spend nothing) until the game waits on an activation.
static func settle(state: GameState, first: int = 0) -> void:
	for guard: int in 50:
		var pending: PendingDecision = state.pending
		if pending == null:
			return
		match pending.kind:
			PendingDecision.Kind.ROLL_OFF:
				_run(state, RollOffCommand.new(0))
			PendingDecision.Kind.CHOOSE_FIRST_PLAYER:
				_run(state, ChooseFirstPlayerCommand.new(pending.player, first))
			PendingDecision.Kind.ROLL_CHOICE:
				_run(state, RollChoiceCommand.new(pending.player, 0))
			_:
				return


static func _other_unactivated(state: GameState, player: int, not_this: int) -> int:
	var fallback: int = -1
	for other: ModelState in state.models:
		if other.player == player and not state.turn.has_activated(other.id):
			if other.id != not_this:
				return other.id
			fallback = other.id
	return fallback


static func _run(state: GameState, command: Command) -> void:
	var error: String = state.execute(command)
	if error != "":
		push_error("TurnHelper: %s rejected: %s" % [command.get_script().get_global_name(), error])
