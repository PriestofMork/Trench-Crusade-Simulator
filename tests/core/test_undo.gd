extends GutTest
## Undo and redo: snapshots of the full state, dice included.

var state: GameState
var a1: int
var a2: int
var b1: int


func before_each() -> void:
	state = GameState.new(11)
	a1 = _place(0, Vector3(10, 0, 10))
	a2 = _place(0, Vector3(14, 0, 10))
	b1 = _place(1, Vector3(30, 0, 30))
	_ok(StartGameCommand.new())
	_ok(ChooseFirstPlayerCommand.new(1, 0))


func _place(player: int, pos: Vector3) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, 32, 6.0)
	assert_eq(state.execute(command), "")
	return command.placed_model_id


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


func _resolved(events: Array[GameEvent]) -> RollResult:
	for event: GameEvent in events:
		if event.kind == GameEvent.Kind.ROLL_RESOLVED:
			return event.result
	return null


func test_undo_goes_back_to_the_start_of_turn_1_and_no_further() -> void:
	assert_true(state.can_undo(), "the first-player choice can be taken back")
	assert_true(state.undo())
	assert_eq(state.pending.kind, PendingDecision.Kind.CHOOSE_FIRST_PLAYER, "the decision is pending again")
	assert_false(state.can_undo(), "set-up and the start of the game stay")
	assert_false(state.undo())


func test_undoing_a_step_gives_the_distance_back() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	_ok(MoveCommand.new(0, a1, [Vector3(10, 0, 13)]))
	_ok(MoveCommand.new(0, a1, [Vector3(10, 0, 15)]))
	assert_almost_eq(state.pending.budget, 1.0, 0.0001)
	assert_true(state.undo())
	assert_eq(state.get_model(a1).position, Vector3(10, 0, 13))
	assert_almost_eq(state.pending.budget, 3.0, 0.0001, "the step's 2\" are back")
	assert_true(state.undo())
	assert_eq(state.get_model(a1).position, Vector3(10, 0, 10))
	assert_almost_eq(state.pending.budget, 6.0, 0.0001)
	assert_true(state.undo())
	assert_null(state.pending)
	assert_eq(state.turn.active_model_id, -1, "the activation had not started")
	assert_false(state.turn.has_activated(a1))
	assert_eq(state.history.size(), 5, "3 placements, start, choice, and nothing after")


func test_undoing_a_resolved_roll_restores_markers_activation_and_dice() -> void:
	_ok(SetMarkersOverride.new(a1, Markers.BLOOD, 2))
	_ok(BeginActionCommand.new(0, a1, &"dash"))
	var first: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 2))
	var result: RollResult = _resolved(first)
	assert_eq(state.get_model(a1).marker_count(Markers.BLOOD), 0)
	assert_true(state.undo())
	assert_eq(state.get_model(a1).marker_count(Markers.BLOOD), 2, "markers back")
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE, "back at the blood prompt")
	assert_eq(state.pending.player, 1)
	assert_eq(state.turn.active_model_id, a1)
	assert_not_null(state.active_roll)
	# The same answer rolls the same dice: undo cannot fish for a better roll.
	var again: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 2))
	assert_eq(_resolved(again).dice, result.dice)
	assert_eq(_resolved(again).outcome, result.outcome)


func test_undo_back_through_a_pending_decision() -> void:
	_ok(SetMarkersOverride.new(a1, Markers.BLOOD, 1))
	_ok(SetMarkersOverride.new(a1, Markers.BLESSING, 1))
	_ok(BeginActionCommand.new(0, a1, &"dash"))
	_ok(RollChoiceCommand.new(1, 1))
	assert_eq(state.pending.choice.provider_id, &"blessing")
	assert_true(state.undo())
	assert_eq(state.pending.choice.provider_id, &"blood")
	assert_eq(state.active_roll.modifiers.size(), 0)
	assert_true(state.undo())
	assert_null(state.pending)
	assert_null(state.active_roll)
	assert_eq(state.turn.active_model_id, -1)
	# A different answer after undoing is just a new command.
	_ok(BeginActionCommand.new(0, a1, &"dash"))
	_ok(RollChoiceCommand.new(1, 0))
	assert_eq(state.pending.choice.provider_id, &"blessing")


func test_redo_applies_the_undone_command_again() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	_ok(MoveCommand.new(0, a1, [Vector3(10, 0, 13)]))
	assert_false(state.can_redo())
	assert_true(state.undo())
	assert_true(state.undo())
	assert_true(state.can_redo())
	var redone: CommandResult = state.redo()
	assert_eq(redone.error, "")
	assert_eq(GameEvent.kinds(redone.events)[0], GameEvent.Kind.ACTIVATION_STARTED, "redo plays its events")
	assert_eq(state.redo().error, "")
	assert_eq(state.get_model(a1).position, Vector3(10, 0, 13))
	assert_ne(state.redo().error, "", "nothing more to redo")
	assert_true(state.undo())
	_ok(DeclineMoveCommand.new(0))
	assert_false(state.can_redo(), "a new command drops the redo list")


func test_redo_of_a_roll_rolls_the_same() -> void:
	var first: Array[GameEvent] = _ok(BeginActionCommand.new(0, a1, &"dash"))
	var dice: Array[int] = _resolved(first).dice
	assert_true(state.undo())
	var redone: CommandResult = state.redo()
	assert_eq(_resolved(redone.events).dice, dice)


func test_undo_restores_overrides_and_flags() -> void:
	_ok(SetDownOverride.new(b1, true))
	_ok(SetWarbandFlagOverride.new(1, WarbandState.ALL_SUCCESS_ROLLS_RISKY, true))
	assert_true(state.undo())
	assert_false(state.warbands[1].has_flag(WarbandState.ALL_SUCCESS_ROLLS_RISKY))
	assert_true(state.get_model(b1).down)
	assert_true(state.undo())
	assert_false(state.get_model(b1).down)
