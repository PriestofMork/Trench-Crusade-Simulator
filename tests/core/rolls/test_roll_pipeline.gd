extends GutTest
## The roll pipeline through Dash: marker prompts in order, spending, risky
## rolls and their reaction, the warband flag, events and replays.

var state: GameState
## Player 0's dasher, a second player 0 model, and player 1's model.
var dasher: int
var other: int
var enemy: int


func before_each() -> void:
	state = _new_game(5)


func _new_game(seed_value: int) -> GameState:
	var s: GameState = GameState.new(seed_value)
	dasher = _place(s, 0, Vector3(10, 0, 10))
	other = _place(s, 0, Vector3(14, 0, 10))
	enemy = _place(s, 1, Vector3(30, 0, 30))
	# Player 1 has fewer models (no roll-off, so no dice used yet) and lets player 0 go first.
	assert_eq(s.execute(StartGameCommand.new()), "")
	assert_eq(s.execute(ChooseFirstPlayerCommand.new(1, 0)), "")
	return s


func _place(s: GameState, player: int, pos: Vector3) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, 32, 6.0)
	assert_eq(s.execute(command), "")
	return command.placed_model_id


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


## Gives the state a dice seed whose next `count` dice, keeping `kept`
## highest (or lowest), total at least 7 (or less).
func _rig(count: int, highest: bool, succeed: bool) -> void:
	for seed_value: int in 500:
		var probe: Dice = Dice.new(seed_value)
		var values: Array[int] = probe.roll(count)
		var kept: Array[bool] = RollResolver.keep(values, 2, highest)
		var total: int = 0
		for i: int in values.size():
			if kept[i]:
				total += values[i]
		if (total >= 7) == succeed:
			state.dice = Dice.new(seed_value)
			return
	fail_test("no seed found")


func _last(events: Array[GameEvent], kind: GameEvent.Kind) -> GameEvent:
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].kind == kind:
			return events[i]
	return null


func test_a_successful_dash_grants_a_move() -> void:
	_rig(2, true, true)
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, dasher, &"dash"))
	assert_eq(GameEvent.kinds(events), [
		GameEvent.Kind.ACTIVATION_STARTED, GameEvent.Kind.ACTION_STARTED, GameEvent.Kind.ROLL_REQUESTED,
		GameEvent.Kind.ROLL_RESOLVED, GameEvent.Kind.DECISION_NEEDED
	] as Array[GameEvent.Kind], "no markers: no prompts")
	var resolved: GameEvent = _last(events, GameEvent.Kind.ROLL_RESOLVED)
	assert_true(resolved.result.risky, "Dash is risky")
	assert_true(resolved.result.is_success())
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE)
	assert_eq(state.pending.budget, 6.0)
	assert_eq(state.pending.action_id, &"dash")
	_ok(MoveCommand.new(0, dasher, [Vector3(10, 0, 16)]))
	assert_eq(state.turn.active_model_id, dasher, "the activation goes on")
	# Move is still available after Dash, and the other way round.
	_ok(BeginActionCommand.new(0, dasher, &"move"))


func test_the_move_after_a_dash_may_be_declined() -> void:
	_rig(2, true, true)
	_ok(BeginActionCommand.new(0, dasher, &"dash"))
	var events: Array[GameEvent] = _ok(DeclineMoveCommand.new(0))
	assert_eq(events[0].kind, GameEvent.Kind.MOVE_FINISHED)
	assert_null(state.pending)
	assert_eq(state.turn.active_model_id, dasher)


func test_a_failed_dash_ends_the_activation() -> void:
	_rig(2, true, false)
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, dasher, &"dash"))
	var resolved: GameEvent = _last(events, GameEvent.Kind.ROLL_RESOLVED)
	assert_true(resolved.result.is_failure())
	var ended: GameEvent = _last(events, GameEvent.Kind.ACTIVATION_ENDED)
	assert_not_null(ended)
	assert_eq(ended.data["reason"], "failed risky roll")
	assert_eq(state.turn.active_model_id, -1)
	assert_eq(state.turn.player_to_act, 1)
	assert_null(state.pending, "no move offered")


func test_the_warband_flag_makes_a_safe_roll_risky() -> void:
	# A safe success roll, registered for the test like any later action would be.
	state.rules.add_action(ActionDef.new(&"test_steady", "Steady", false, false, RollThenMoveBehaviour.new()))
	_rig(2, true, false)
	var safe: Array[GameEvent] = _ok(BeginActionCommand.new(0, dasher, &"test_steady"))
	assert_false(_last(safe, GameEvent.Kind.ROLL_RESOLVED).result.risky)
	assert_eq(state.turn.active_model_id, dasher, "a failed safe roll does not end the activation")
	_ok(EndActivationCommand.new(0, dasher))
	_ok(EndActivationCommand.new(1, enemy))

	_ok(SetWarbandFlagOverride.new(0, WarbandState.ALL_SUCCESS_ROLLS_RISKY, true))
	_rig(2, true, false)
	var risky: Array[GameEvent] = _ok(BeginActionCommand.new(0, other, &"test_steady"))
	var requested: GameEvent = risky[2]
	assert_eq(requested.kind, GameEvent.Kind.ROLL_REQUESTED)
	assert_eq(requested.roll.modifiers.size(), 1, "the flag shows in the breakdown")
	assert_true(requested.roll.modifiers[0].makes_risky)
	assert_true(_last(risky, GameEvent.Kind.ROLL_RESOLVED).result.risky)
	assert_not_null(_last(risky, GameEvent.Kind.ACTIVATION_ENDED), "now a failure ends it")


func test_marker_prompts_come_in_order_blood_then_blessing() -> void:
	_ok(SetMarkersOverride.new(dasher, Markers.BLOOD, 2))
	_ok(SetMarkersOverride.new(dasher, Markers.BLESSING, 3))
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, dasher, &"dash"))
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE)
	assert_eq(state.pending.player, 1, "the opponent decides on blood")
	assert_eq(state.pending.choice.provider_id, &"blood")
	assert_eq(state.pending.choice.maximum, 2)
	assert_eq(state.pending.choice.dice_per_unit, -1)
	assert_ne(state.execute(RollChoiceCommand.new(0, 1)), "", "not player 0's decision")
	assert_ne(state.execute(RollChoiceCommand.new(1, 3)), "", "only 2 to spend")
	assert_ne(state.execute(EndActivationCommand.new(0, dasher)), "", "not during a roll")
	_ok(RollChoiceCommand.new(1, 1))
	assert_eq(state.get_model(dasher).marker_count(Markers.BLOOD), 1, "spending removes the markers")
	assert_eq(state.pending.player, 0, "then the rolling player decides on blessing")
	assert_eq(state.pending.choice.provider_id, &"blessing")
	assert_eq(state.pending.choice.maximum, 3)
	assert_eq(state.active_roll.modifiers.size(), 1, "the blessing prompt sees the blood spent")
	var last: Array[GameEvent] = _ok(RollChoiceCommand.new(0, 3))
	assert_eq(state.get_model(dasher).marker_count(Markers.BLESSING), 0)
	var resolved: GameEvent = _last(last, GameEvent.Kind.ROLL_RESOLVED)
	assert_eq(resolved.result.net_dice, 2, "-1 blood, +3 blessing")
	assert_eq(resolved.result.dice.size(), 4)
	assert_eq(resolved.result.modifiers.size(), 2)
	assert_eq(resolved.result.kept_dice().size(), 2)
	events.append_array(last)


func test_a_prompt_is_skipped_when_there_is_nothing_to_spend() -> void:
	_ok(SetMarkersOverride.new(dasher, Markers.BLESSING, 1))
	_ok(BeginActionCommand.new(0, dasher, &"dash"))
	assert_eq(state.pending.choice.provider_id, &"blessing", "no blood prompt")
	assert_eq(state.pending.player, 0)


func test_spending_nothing_keeps_the_markers() -> void:
	_ok(SetMarkersOverride.new(dasher, Markers.BLOOD, 2))
	_ok(BeginActionCommand.new(0, dasher, &"dash"))
	var events: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 0))
	assert_eq(state.get_model(dasher).marker_count(Markers.BLOOD), 2)
	var resolved: GameEvent = _last(events, GameEvent.Kind.ROLL_RESOLVED)
	assert_eq(resolved.result.dice.size(), 2)


func test_markers_change_the_dice_as_expected() -> void:
	# Two blood markers spent: four dice, the lowest two kept.
	_ok(SetMarkersOverride.new(dasher, Markers.BLOOD, 2))
	_ok(BeginActionCommand.new(0, dasher, &"dash"))
	var events: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 2))
	var result: RollResult = _last(events, GameEvent.Kind.ROLL_RESOLVED).result
	assert_eq(result.dice.size(), 4)
	var sorted: Array[int] = result.dice.duplicate()
	sorted.sort()
	assert_eq(result.total, sorted[0] + sorted[1])


func test_marker_cap() -> void:
	assert_ne(state.execute(SetMarkersOverride.new(dasher, Markers.BLOOD, 7)), "")
	_ok(SetMarkersOverride.new(dasher, Markers.INFECTION, 6))
	state.get_model(dasher).set_markers(Markers.BLOOD, 9)
	assert_eq(state.get_model(dasher).marker_count(Markers.BLOOD), Markers.CAP)


func test_injury_rolls_use_markers_the_other_way() -> void:
	# Not triggered by any rule yet: driven straight through the pipeline.
	_ok(SetMarkersOverride.new(enemy, Markers.BLOOD, 2))
	_ok(SetMarkersOverride.new(enemy, Markers.BLESSING, 1))
	var events: Array[GameEvent] = []
	RollPipeline.start(state, RollRequest.injury(0, dasher, enemy), events)
	assert_eq(state.pending.choice.provider_id, &"blood")
	assert_eq(state.pending.player, 0, "the attacker spends the target's blood")
	assert_eq(state.pending.choice.dice_per_unit, 1)
	_ok(RollChoiceCommand.new(0, 2))
	assert_eq(state.pending.choice.provider_id, &"blessing")
	assert_eq(state.pending.player, 1, "the target's owner spends its blessing")
	assert_eq(state.pending.choice.dice_per_unit, -1)
	var last: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 1))
	assert_eq(_last(last, GameEvent.Kind.ROLL_RESOLVED).result.net_dice, 1)


func test_a_full_dash_with_a_blood_prompt_gives_the_expected_events() -> void:
	_ok(SetMarkersOverride.new(dasher, Markers.BLOOD, 1))
	var all: Array[GameEvent] = _ok(BeginActionCommand.new(0, dasher, &"dash"))
	assert_eq(GameEvent.kinds(all), [
		GameEvent.Kind.ACTIVATION_STARTED, GameEvent.Kind.ACTION_STARTED,
		GameEvent.Kind.ROLL_REQUESTED, GameEvent.Kind.DECISION_NEEDED
	] as Array[GameEvent.Kind])
	assert_eq(all[3].decision.kind, PendingDecision.Kind.ROLL_CHOICE)
	assert_eq(all[3].player, 1)
	assert_not_null(all[3].roll, "the prompt knows its roll")
	var rest: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 1))
	var resolved: GameEvent = _last(rest, GameEvent.Kind.ROLL_RESOLVED)
	var expected: Array[GameEvent.Kind] = [GameEvent.Kind.ROLL_CHOICE_MADE, GameEvent.Kind.ROLL_RESOLVED]
	if resolved.result.is_success():
		expected.append(GameEvent.Kind.DECISION_NEEDED)
	else:
		expected.append_array([GameEvent.Kind.ACTIVATION_ENDED, GameEvent.Kind.PLAYER_TO_ACT])
	assert_eq(GameEvent.kinds(rest), expected)
	assert_eq(rest[0].data["amount"], 1)
	assert_eq(resolved.result.dice.size(), 3)


func test_the_resolver_and_pipeline_name_no_rule() -> void:
	for path: String in ["res://core/rolls/roll_resolver.gd", "res://core/rolls/roll_pipeline.gd"]:
		var source: String = FileAccess.get_file_as_string(path).to_lower()
		for word: String in ["dash", "blood", "blessing", "marker", "weapon"]:
			assert_false(source.contains(word), "%s mentions '%s'" % [path, word])


func test_same_seed_and_commands_give_the_same_game() -> void:
	var commands: Array = [
		func() -> Command: return SetMarkersOverride.new(1, Markers.BLOOD, 2),
		func() -> Command: return SetMarkersOverride.new(1, Markers.BLESSING, 1),
		func() -> Command: return BeginActionCommand.new(0, 1, &"dash"),
		func() -> Command: return RollChoiceCommand.new(1, 2),
		func() -> Command: return RollChoiceCommand.new(0, 1),
	]
	var a: GameState = _new_game(99)
	var b: GameState = _new_game(99)
	for make: Callable in commands:
		assert_eq(a.execute(make.call()), "")
		assert_eq(b.execute(make.call()), "")
	# Whatever happened, finish the activation the same way in both.
	for s: GameState in [a, b]:
		if s.pending != null and s.pending.kind == PendingDecision.Kind.MOVE:
			assert_eq(s.execute(MoveCommand.new(0, 1, [Vector3(10, 0, 14)])), "")
		if s.turn.active_model_id == 1:
			assert_eq(s.execute(EndActivationCommand.new(0, 1)), "")
		assert_eq(s.execute(BeginActionCommand.new(1, 3, &"dash")), "")
	assert_eq(_snapshot(a), _snapshot(b))
	assert_eq(a.dice.roll(5), b.dice.roll(5), "the dice are in step too")


func _snapshot(s: GameState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for model: ModelState in s.models:
		parts.append("%d %s %s %s" % [model.id, str(model.position), str(model.markers), str(model.down)])
	parts.append("turn %d to act %d active %d used %s" % [
		s.turn.turn, s.turn.player_to_act, s.turn.active_model_id, str(s.turn.actions_used)
	])
	parts.append("pending %s" % ("none" if s.pending == null else str(s.pending.kind)))
	parts.append("history %d" % s.history.size())
	return "\n".join(parts)
