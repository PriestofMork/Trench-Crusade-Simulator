extends GutTest
## Turn order: who chooses the first player, roll-offs, alternation, running
## out of models, and the end of the turn.

var state: GameState


func before_each() -> void:
	state = GameState.new(7)


func _place(player: int, x: float, z: float = 10.0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, Vector3(x, 0, z), 32, 6.0)
	assert_eq(state.execute(command), "")
	return command.placed_model_id


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


func test_start_needs_models_and_only_once() -> void:
	assert_ne(state.execute(StartGameCommand.new()), "")
	_place(0, 10)
	assert_eq(state.execute(StartGameCommand.new()), "")
	assert_eq(state.turn.turn, 1)
	assert_ne(state.execute(StartGameCommand.new()), "")


func test_fewer_standing_models_chooses() -> void:
	_place(0, 10)
	_place(0, 14)
	_place(1, 30)
	var events: Array[GameEvent] = _ok(StartGameCommand.new())
	assert_eq(GameEvent.kinds(events), [GameEvent.Kind.TURN_STARTED, GameEvent.Kind.DECISION_NEEDED] as Array[GameEvent.Kind])
	assert_eq(state.pending.kind, PendingDecision.Kind.CHOOSE_FIRST_PLAYER)
	assert_eq(state.pending.player, 1, "player 1 has fewer models")
	assert_ne(state.execute(ChooseFirstPlayerCommand.new(0, 0)), "", "not player 0's choice")
	assert_ne(state.execute(RollOffCommand.new(0)), "", "no roll-off pending")
	_ok(ChooseFirstPlayerCommand.new(1, 0))
	assert_eq(state.turn.player_to_act, 0)
	assert_eq(state.turn.first_player, 0)


func test_down_models_do_not_count_as_standing() -> void:
	# Player 0: three models, two Down. Player 1: two standing.
	var a: int = _place(0, 10)
	_place(0, 14)
	var c: int = _place(0, 18)
	_place(1, 30)
	_place(1, 34)
	_ok(SetDownOverride.new(a, true))
	_ok(SetDownOverride.new(c, true))
	_ok(StartGameCommand.new())
	assert_eq(state.pending.kind, PendingDecision.Kind.CHOOSE_FIRST_PLAYER)
	assert_eq(state.pending.player, 0, "1 standing against 2, though 3 models against 2")


func test_tie_leads_to_a_roll_off_and_the_winner_chooses() -> void:
	_place(0, 10)
	_place(1, 30)
	_ok(StartGameCommand.new())
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_OFF)
	assert_eq(state.pending.player, PendingDecision.EITHER_PLAYER)
	var events: Array[GameEvent] = _ok(RollOffCommand.new(1))
	var resolved: GameEvent = null
	for event: GameEvent in events:
		if event.kind == GameEvent.Kind.ROLL_RESOLVED:
			resolved = event
	assert_not_null(resolved)
	assert_eq(resolved.result.dice.size(), 2)
	if resolved.result.winner == -1:
		assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_OFF, "drawn: roll again")
	else:
		assert_eq(state.pending.kind, PendingDecision.Kind.CHOOSE_FIRST_PLAYER)
		assert_eq(state.pending.player, resolved.result.winner)
		var higher: int = 0 if resolved.result.dice[0] > resolved.result.dice[1] else 1
		assert_eq(resolved.result.winner, higher)


func test_a_drawn_roll_off_is_rolled_again() -> void:
	_place(0, 10)
	_place(1, 30)
	# Find a seed whose first roll-off is drawn.
	for seed_value: int in 200:
		var probe: Dice = Dice.new(seed_value)
		var first: Array[int] = probe.roll(2)
		if first[0] == first[1]:
			state.dice = Dice.new(seed_value)
			break
	_ok(StartGameCommand.new())
	var events: Array[GameEvent] = _ok(RollOffCommand.new(0))
	assert_eq(events[events.size() - 1].kind, GameEvent.Kind.DECISION_NEEDED)
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_OFF, "a draw is rolled again")
	for guard: int in 20:
		if state.pending.kind != PendingDecision.Kind.ROLL_OFF:
			break
		_ok(RollOffCommand.new(0))
	assert_eq(state.pending.kind, PendingDecision.Kind.CHOOSE_FIRST_PLAYER)


func test_players_alternate_and_the_other_continues_when_one_runs_out() -> void:
	var a1: int = _place(0, 10)
	var a2: int = _place(0, 14)
	var a3: int = _place(0, 18)
	var b1: int = _place(1, 30)
	_ok(StartGameCommand.new())
	_ok(ChooseFirstPlayerCommand.new(1, 0))
	assert_ne(state.execute(EndActivationCommand.new(1, b1)), "", "player 0 acts first")
	_ok(EndActivationCommand.new(0, a1))
	assert_eq(state.turn.player_to_act, 1)
	assert_ne(state.execute(EndActivationCommand.new(0, a2)), "", "now it is player 1's go")
	_ok(EndActivationCommand.new(1, b1))
	assert_eq(state.turn.player_to_act, 0, "player 1 is out of models")
	_ok(EndActivationCommand.new(0, a2))
	assert_eq(state.turn.player_to_act, 0, "player 0 keeps activating")
	assert_ne(state.execute(EndActivationCommand.new(0, a1)), "", "a1 has activated")
	var events: Array[GameEvent] = _ok(EndActivationCommand.new(0, a3))
	var kinds: Array[GameEvent.Kind] = GameEvent.kinds(events)
	assert_true(kinds.has(GameEvent.Kind.TURN_ENDED))
	assert_true(kinds.has(GameEvent.Kind.TURN_STARTED))
	assert_eq(state.turn.turn, 2)
	assert_true(state.turn.activated.is_empty())
	assert_eq(state.pending.kind, PendingDecision.Kind.CHOOSE_FIRST_PLAYER, "chosen again every turn")
	assert_eq(state.pending.player, 1)


func test_first_choice_may_be_a_player_with_nothing_left() -> void:
	var a1: int = _place(0, 10)
	_place(0, 14)
	_place(1, 30)
	_ok(StartGameCommand.new())
	_ok(ChooseFirstPlayerCommand.new(1, 1))
	assert_eq(state.turn.player_to_act, 1)
	assert_ne(state.execute(EndActivationCommand.new(0, a1)), "")
