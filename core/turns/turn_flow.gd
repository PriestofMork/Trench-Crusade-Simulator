class_name TurnFlow
extends RefCounted
## The turn sequence of docs/rules/turn-structure.md and the rulings of brief
## 005: who chooses the first player, alternating activations, standing up,
## handing over when a player runs out of models, and the end of the turn.
## Only commands (and rules they run) call these; each appends the events of
## what it did.


## Starts the next turn: clears activations and asks who chooses the first
## player (the player with fewer models standing; a roll-off on a tie).
static func start_turn(state: GameState, events: Array[GameEvent]) -> void:
	var t: TurnState = state.turn
	t.turn += 1
	t.activated.clear()
	t.first_player = -1
	t.player_to_act = -1
	_clear_activation(t)
	events.append(GameEvent.new(GameEvent.Kind.TURN_STARTED, -1, -1, {"turn": t.turn}))
	var standing: Array[int] = [count_standing(state, 0), count_standing(state, 1)]
	if standing[0] != standing[1]:
		var chooser: int = 0 if standing[0] < standing[1] else 1
		ask(state, PendingDecision.new(
			PendingDecision.Kind.CHOOSE_FIRST_PLAYER, chooser,
			"Fewer models standing (%d against %d): choose who activates first." % [standing[chooser], standing[1 - chooser]]
		), events)
	else:
		ask(state, PendingDecision.new(
			PendingDecision.Kind.ROLL_OFF, PendingDecision.EITHER_PLAYER,
			"Both sides have %d models standing: roll off. The winner chooses who activates first." % standing[0]
		), events)


## Records a decision core now waits for.
static func ask(state: GameState, decision: PendingDecision, events: Array[GameEvent]) -> void:
	state.pending = decision
	var event: GameEvent = GameEvent.new(GameEvent.Kind.DECISION_NEEDED, decision.player, decision.model_id)
	event.decision = decision
	events.append(event)


## Answers ROLL_OFF: rolls through the pipeline; the winner then chooses, a
## draw asks for another roll-off.
static func roll_off(state: GameState, events: Array[GameEvent]) -> void:
	state.pending = null
	var request: RollRequest = RollRequest.roll_off()
	request.on_resolved = _on_roll_off
	RollPipeline.start(state, request, events)


static func _on_roll_off(state: GameState, result: RollResult, events: Array[GameEvent]) -> void:
	if result.winner == -1:
		ask(state, PendingDecision.new(
			PendingDecision.Kind.ROLL_OFF, PendingDecision.EITHER_PLAYER, "The roll-off is drawn: roll again."
		), events)
		return
	ask(state, PendingDecision.new(
		PendingDecision.Kind.CHOOSE_FIRST_PLAYER, result.winner, "Won the roll-off: choose who activates first."
	), events)


## Answers CHOOSE_FIRST_PLAYER.
static func choose_first(state: GameState, first: int, events: Array[GameEvent]) -> void:
	state.pending = null
	state.turn.first_player = first
	events.append(GameEvent.new(GameEvent.Kind.FIRST_PLAYER_CHOSEN, first))
	_hand_over(state, first, events)


## Starts `model`'s activation; a Down model stands up first.
static func begin_activation(state: GameState, model: ModelState, events: Array[GameEvent]) -> void:
	var t: TurnState = state.turn
	_clear_activation(t)
	t.active_model_id = model.id
	t.activated[model.id] = true
	events.append(GameEvent.new(GameEvent.Kind.ACTIVATION_STARTED, model.player, model.id))
	if model.down:
		model.down = false
		t.stood_up = true
		events.append(GameEvent.new(GameEvent.Kind.MODEL_STOOD_UP, model.player, model.id))


## Ends the active model's activation (an unanswered move is dropped) and
## hands over: to the other player if they have a model left to activate,
## else to the same player, else the turn ends and the next one starts.
static func end_activation(state: GameState, events: Array[GameEvent], reason: String) -> void:
	var t: TurnState = state.turn
	var model: ModelState = state.get_model(t.active_model_id)
	if state.pending != null and state.pending.kind == PendingDecision.Kind.MOVE:
		state.pending = null
	_clear_activation(t)
	events.append(GameEvent.new(GameEvent.Kind.ACTIVATION_ENDED, model.player, model.id, {"reason": reason}))
	_hand_over(state, 1 - model.player, events)


## How far `model` may move with a move granted by an action: its Movement,
## halved if it stood up this activation (or will, being Down and not active).
static func movement_budget(state: GameState, model: ModelState) -> float:
	var t: TurnState = state.turn
	var halved: bool = t.stood_up if t.active_model_id == model.id else model.down
	return model.movement * (0.5 if halved else 1.0)


## Asks the owner of `model` for one path within its movement budget.
static func offer_move(state: GameState, model: ModelState, action_id: StringName, events: Array[GameEvent]) -> void:
	var budget: float = movement_budget(state, model)
	var decision: PendingDecision = PendingDecision.new(
		PendingDecision.Kind.MOVE, model.player, "Move up to %.1f\", or stay." % budget
	)
	decision.model_id = model.id
	decision.budget = budget
	decision.action_id = action_id
	ask(state, decision, events)


## Models of `player` on the table that are not Down.
static func count_standing(state: GameState, player: int) -> int:
	var count: int = 0
	for model: ModelState in state.models:
		if model.player == player and not model.down:
			count += 1
	return count


static func has_unactivated(state: GameState, player: int) -> bool:
	for model: ModelState in state.models:
		if model.player == player and not state.turn.has_activated(model.id):
			return true
	return false


## Why `player` may not act with `model` now (start its activation or carry
## it on), or "".
static func activation_error(state: GameState, player: int, model: ModelState) -> String:
	var t: TurnState = state.turn
	if t.turn == 0:
		return "The game has not started."
	if state.pending != null:
		return "Waiting for a decision first."
	if state.active_roll != null:
		return "A roll is under way."
	if player != t.player_to_act:
		return "It is player %d's turn to act, not player %d's." % [t.player_to_act + 1, player + 1]
	if model.player != player:
		return "Model %d belongs to the other player." % model.id
	if t.active_model_id != -1 and t.active_model_id != model.id:
		return "Model %d is activating; end its activation first." % t.active_model_id
	if t.active_model_id == -1 and t.has_activated(model.id):
		return "Model %d has already activated this turn." % model.id
	return ""


static func _hand_over(state: GameState, preferred: int, events: Array[GameEvent]) -> void:
	for player: int in [preferred, 1 - preferred]:
		if has_unactivated(state, player):
			state.turn.player_to_act = player
			events.append(GameEvent.new(GameEvent.Kind.PLAYER_TO_ACT, player))
			return
	events.append(GameEvent.new(GameEvent.Kind.TURN_ENDED, -1, -1, {"turn": state.turn.turn}))
	start_turn(state, events)


static func _clear_activation(t: TurnState) -> void:
	t.active_model_id = -1
	t.actions_used.clear()
	t.move_action_used = false
	t.stood_up = false
