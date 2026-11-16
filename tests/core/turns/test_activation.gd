extends GutTest
## Activations: start on the first action, block other models, each action
## once, one move action, ending early, wrong-player commands, standing up.

var state: GameState
var a1: int
var a2: int
var b1: int


func before_each() -> void:
	state = GameState.new(3)
	a1 = _place(0, Vector3(10, 0, 10), 8.0)
	a2 = _place(0, Vector3(14, 0, 10))
	b1 = _place(1, Vector3(30, 0, 30))
	_ok(StartGameCommand.new())
	# Player 1 has fewer models and lets player 0 go first.
	_ok(ChooseFirstPlayerCommand.new(1, 0))


func _place(player: int, pos: Vector3, movement: float = 6.0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, 32, movement)
	assert_eq(state.execute(command), "")
	return command.placed_model_id


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


func test_actions_are_registered_as_data() -> void:
	var move: ActionDef = state.rules.action(&"move")
	var dash: ActionDef = state.rules.action(&"dash")
	assert_true(move.move_action)
	assert_false(move.risky)
	assert_false(dash.move_action)
	assert_true(dash.risky)
	var charge: ActionDef = state.rules.action(&"charge")
	var retreat: ActionDef = state.rules.action(&"retreat")
	assert_true(charge.move_action, "Charge is a move action (brief 007)")
	assert_true(retreat.move_action, "Retreat is a move action (brief 007)")
	assert_eq(move.melee, ActionDef.Melee.FORBIDDEN)
	assert_eq(dash.melee, ActionDef.Melee.FORBIDDEN)
	assert_eq(charge.melee, ActionDef.Melee.FORBIDDEN)
	assert_eq(retreat.melee, ActionDef.Melee.REQUIRED)


func test_selecting_is_not_activating_the_first_action_is() -> void:
	assert_eq(state.turn.active_model_id, -1)
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, a1, &"move"))
	assert_eq(GameEvent.kinds(events), [
		GameEvent.Kind.ACTIVATION_STARTED, GameEvent.Kind.ACTION_STARTED, GameEvent.Kind.DECISION_NEEDED
	] as Array[GameEvent.Kind])
	assert_eq(state.turn.active_model_id, a1)
	assert_true(state.turn.has_activated(a1))
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE)
	assert_eq(state.pending.budget, 8.0)


func test_an_active_model_blocks_the_others() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	_ok(MoveCommand.new(0, a1, [Vector3(12, 0, 14)]))
	assert_ne(state.execute(BeginActionCommand.new(0, a2, &"move")), "", "a1's move is open")
	_ok(DeclineMoveCommand.new(0))
	assert_ne(state.execute(BeginActionCommand.new(0, a2, &"move")), "")
	assert_ne(state.execute(EndActivationCommand.new(0, a2)), "")
	_ok(EndActivationCommand.new(0, a1))
	assert_eq(state.turn.player_to_act, 1)


func test_each_action_once_and_one_move_action() -> void:
	# A second move action, registered for the test, is refused after Move.
	state.rules.add_action(ActionDef.new(&"test_retreat", "Retreat", true, false, MoveBehaviour.new()))
	_ok(BeginActionCommand.new(0, a1, &"move"))
	_ok(DeclineMoveCommand.new(0))
	assert_ne(state.execute(BeginActionCommand.new(0, a1, &"move")), "", "Move once")
	var reason: String = BeginActionCommand.unavailable_reason(state, state.get_model(a1), &"test_retreat")
	assert_string_contains(reason, "one move action")
	assert_eq(BeginActionCommand.unavailable_reason(state, state.get_model(a1), &"dash"), "", "Dash is not a move action")


func test_unknown_action_is_rejected() -> void:
	assert_ne(state.execute(BeginActionCommand.new(0, a1, &"fly")), "")


func test_a_move_may_be_made_in_steps_within_the_budget() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	assert_ne(state.execute(MoveCommand.new(0, a1, [Vector3(18.5, 0, 10)])), "", "8.5\" is too far")
	var events: Array[GameEvent] = _ok(MoveCommand.new(0, a1, [Vector3(10, 0, 13)]))
	assert_eq(GameEvent.kinds(events), [GameEvent.Kind.MODEL_MOVED, GameEvent.Kind.DECISION_NEEDED] as Array[GameEvent.Kind])
	var path: Array = events[0].data["path"]
	assert_eq(path[0], Vector3(10, 0, 10), "the path starts where the model was")
	assert_eq(path[path.size() - 1], Vector3(10, 0, 13))
	assert_almost_eq(float(events[0].data["left"]), 5.0, 0.0001)
	assert_almost_eq(state.pending.budget, 5.0, 0.0001, "the move stays open with what is left")
	_ok(MoveCommand.new(0, a1, [Vector3(10, 0, 17)]))
	assert_almost_eq(state.pending.budget, 1.0, 0.0001)
	assert_ne(state.execute(MoveCommand.new(0, a1, [Vector3(10, 0, 19)])), "", "a third step beyond the budget")
	_ok(MoveCommand.new(0, a1, [Vector3(10, 0, 18)]))
	assert_null(state.pending, "nothing left: the move is finished")


func test_starting_dash_finishes_the_move_and_loses_the_rest() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	_ok(MoveCommand.new(0, a1, [Vector3(10, 0, 12)]))
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, a1, &"dash"))
	assert_eq(events[0].kind, GameEvent.Kind.MOVE_FINISHED)
	assert_almost_eq(float(events[0].data["left"]), 6.0, 0.0001, "6\" lost")
	assert_eq(events[1].kind, GameEvent.Kind.ACTION_STARTED, "no second activation start")
	if state.pending != null and state.pending.kind == PendingDecision.Kind.MOVE:
		assert_eq(state.pending.action_id, &"dash", "only the Dash's own move is open")
		assert_almost_eq(state.pending.budget, 8.0, 0.0001)
	assert_ne(state.execute(MoveCommand.new(0, a1, [Vector3(10, 0, 30)])), "")


func test_ending_the_activation_finishes_an_open_move() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	_ok(MoveCommand.new(0, a1, [Vector3(10, 0, 12)]))
	var events: Array[GameEvent] = _ok(EndActivationCommand.new(0, a1))
	assert_eq(events[0].kind, GameEvent.Kind.MOVE_FINISHED)
	assert_eq(events[1].kind, GameEvent.Kind.ACTIVATION_ENDED)
	assert_null(state.pending)


func test_ending_early_and_without_acting() -> void:
	var events: Array[GameEvent] = _ok(EndActivationCommand.new(0, a2))
	assert_eq(GameEvent.kinds(events), [
		GameEvent.Kind.ACTIVATION_STARTED, GameEvent.Kind.ACTIVATION_ENDED, GameEvent.Kind.PLAYER_TO_ACT
	] as Array[GameEvent.Kind])
	assert_true(state.turn.has_activated(a2))
	assert_ne(state.execute(BeginActionCommand.new(0, a2, &"move")), "")


func test_ending_instead_of_choosing_the_move() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	_ok(EndActivationCommand.new(0, a1))
	assert_null(state.pending)
	assert_eq(state.get_model(a1).position, Vector3(10, 0, 10))


func test_commands_from_the_wrong_player_are_rejected() -> void:
	assert_ne(state.execute(BeginActionCommand.new(1, b1, &"move")), "", "player 0 is to act")
	assert_ne(state.execute(BeginActionCommand.new(1, a1, &"move")), "", "not player 1's model or turn")
	assert_ne(state.execute(BeginActionCommand.new(0, b1, &"move")), "", "not player 0's model")
	_ok(BeginActionCommand.new(0, a1, &"move"))
	assert_ne(state.execute(MoveCommand.new(1, a1, [Vector3(12, 0, 10)])), "")
	assert_ne(state.execute(DeclineMoveCommand.new(1)), "")
	assert_ne(state.execute(EndActivationCommand.new(1, a1)), "")
	assert_ne(state.execute(ChooseFirstPlayerCommand.new(0, 0)), "", "nothing to choose")


func test_a_down_model_stands_up_and_moves_half() -> void:
	_ok(SetDownOverride.new(a1, true))
	assert_eq(MoveBehaviour.new().move_budget_preview(state, state.get_model(a1)), 4.0, "the preview knows")
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, a1, &"move"))
	assert_eq(GameEvent.kinds(events), [
		GameEvent.Kind.ACTIVATION_STARTED, GameEvent.Kind.MODEL_STOOD_UP,
		GameEvent.Kind.ACTION_STARTED, GameEvent.Kind.DECISION_NEEDED
	] as Array[GameEvent.Kind])
	assert_false(state.get_model(a1).down)
	assert_true(state.turn.stood_up)
	assert_eq(state.pending.budget, 4.0)
	assert_eq(TurnFlow.movement_budget(state, state.get_model(a1), 3.0), 1.5, "any extra movement is halved too")
	assert_ne(state.execute(MoveCommand.new(0, a1, [Vector3(14.5, 0, 14)])), "", "more than 4\"")
	_ok(MoveCommand.new(0, a1, [Vector3(10, 0, 14)]))


func test_standing_up_does_not_carry_over_to_the_next_model() -> void:
	_ok(SetDownOverride.new(a1, true))
	_ok(EndActivationCommand.new(0, a1))
	assert_false(state.get_model(a1).down, "ending without acting still stands it up")
	_ok(BeginActionCommand.new(1, b1, &"move"))
	assert_eq(state.pending.budget, 6.0)
