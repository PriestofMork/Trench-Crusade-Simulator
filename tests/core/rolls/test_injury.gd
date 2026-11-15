extends GutTest
## Injury rolls and their results (rulings 1 to 4 and 9 of brief 006), Out of
## Action, marker spending on injury rolls, infection markers and the fall
## modifier.

var state: GameState
## Player 0's two models and player 1's two.
var a1: int
var a2: int
var b1: int
var b2: int


func before_each() -> void:
	state = GameState.new(3)
	a1 = _place(0, Vector3(10, 0, 10))
	a2 = _place(0, Vector3(14, 0, 10))
	b1 = _place(1, Vector3(30, 0, 30))
	b2 = _place(1, Vector3(34, 0, 30))
	assert_eq(state.execute(StartGameCommand.new()), "")
	TurnHelper.settle(state, 0)


func _place(player: int, pos: Vector3) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, 32, 6.0)
	assert_eq(state.execute(command), "")
	return command.placed_model_id


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


func _reaction() -> InjuryResultReaction:
	return state.rules.reaction(&"injury_result") as InjuryResultReaction


## Applies an injury result of `total` to `target` as the reaction would.
func _apply_total(target: int, total: int) -> Array[GameEvent]:
	var request: RollRequest = RollRequest.injury(1 - state.get_model(target).player, -1, target)
	var result: RollResult = RollResult.new()
	result.request = request
	result.total = total
	var events: Array[GameEvent] = []
	_reaction().react(state, result, events)
	return events


## Starts an injury roll against `target` the way a rule would.
func _start_injury(target: int, context: Dictionary = {}) -> Array[GameEvent]:
	var request: RollRequest = RollRequest.injury(1 - state.get_model(target).player, -1, target)
	request.context = context
	var events: Array[GameEvent] = []
	RollPipeline.start(state, request, events)
	return events


func _last(events: Array[GameEvent], kind: GameEvent.Kind) -> GameEvent:
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].kind == kind:
			return events[i]
	return null


func test_each_band_of_the_table() -> void:
	var model: ModelState = state.get_model(b1)
	for total: int in [2, 6]:
		model.markers.clear()
		_apply_total(b1, total)
		assert_eq(model.marker_count(Markers.BLOOD), 1, "total %d: one blood marker" % total)
		assert_false(model.down)
	for total: int in [7, 8]:
		model.markers.clear()
		model.down = false
		var events: Array[GameEvent] = _apply_total(b1, total)
		assert_eq(model.marker_count(Markers.BLOOD), 1, "total %d: one blood marker" % total)
		assert_true(model.down, "total %d: Down" % total)
		assert_not_null(_last(events, GameEvent.Kind.MODEL_WENT_DOWN))
	model.down = false
	var out: Array[GameEvent] = _apply_total(b1, 9)
	assert_true(model.out_of_action, "9: Out of Action")
	assert_not_null(_last(out, GameEvent.Kind.MODEL_OUT_OF_ACTION))
	var applied: GameEvent = _last(out, GameEvent.Kind.INJURY_APPLIED)
	assert_true(bool(applied.data["out_of_action"]))
	assert_string_contains(String(applied.data["text"]), "Out of Action")


func test_the_bands_are_data() -> void:
	var reaction: InjuryResultReaction = _reaction()
	assert_eq(reaction.bands.size(), 3)
	assert_eq(reaction.band_for(6).blood, 1)
	assert_true(reaction.band_for(8).down)
	assert_true(reaction.band_for(12).out_of_action)
	assert_true(reaction.band_for(15).out_of_action, "9+ has no upper end")


func test_down_on_a_down_model_places_an_extra_blood_marker() -> void:
	var model: ModelState = state.get_model(b1)
	model.down = true
	var events: Array[GameEvent] = _apply_total(b1, 7)
	assert_eq(model.marker_count(Markers.BLOOD), 2, "two in total for that roll")
	assert_true(model.down)
	assert_null(_last(events, GameEvent.Kind.MODEL_WENT_DOWN), "it does not go Down again")


func test_markers_stop_at_the_cap() -> void:
	var model: ModelState = state.get_model(b1)
	model.set_markers(Markers.BLOOD, 6)
	_apply_total(b1, 3)
	assert_eq(model.marker_count(Markers.BLOOD), Markers.CAP)
	model.set_markers(Markers.BLOOD, 5)
	model.down = true
	_apply_total(b1, 8)
	assert_eq(model.marker_count(Markers.BLOOD), Markers.CAP, "5 + 2 stops at 6")


func test_out_of_action_leaves_the_turn_order_and_the_count() -> void:
	# Player 1 loses b2 before activating it: player 1 then has one model left.
	_apply_total(b2, 10)
	var gone: ModelState = state.get_model(b2)
	assert_true(gone.out_of_action)
	assert_not_null(state.get_model(b2), "its record stays in the game state")
	assert_false(state.models_on_table().has(gone))
	assert_eq(TurnFlow.count_standing(state, 1), 1)
	_ok(EndActivationCommand.new(0, a1))
	assert_eq(state.turn.player_to_act, 1)
	assert_ne(state.execute(BeginActionCommand.new(1, b2, &"move")), "", "an Out of Action model does not activate")
	assert_ne(state.execute(EndActivationCommand.new(1, b2)), "")
	_ok(EndActivationCommand.new(1, b1))
	assert_eq(state.turn.player_to_act, 0, "player 1 has nothing left: player 0 carries on")
	var events: Array[GameEvent] = _ok(EndActivationCommand.new(0, a2))
	assert_not_null(_last(events, GameEvent.Kind.TURN_ENDED), "b2 does not hold the turn open")
	# Next turn: player 1 has fewer models (1 against 2) and chooses.
	assert_eq(state.pending.kind, PendingDecision.Kind.CHOOSE_FIRST_PLAYER)
	assert_eq(state.pending.player, 1)


func test_out_of_action_models_do_not_block() -> void:
	_apply_total(b1, 11)
	# Moving next to where b1 stood, and placing a model there, is fine now.
	var legality: MoveLegality = MoveLegality.new(state, state.get_model(a1))
	assert_eq(legality.point_result(Vector2(29, 30), HeightField.TABLE), MoveLegality.Result.OK, "no 1\" zone")
	var at: PlaceModelCommand = PlaceModelCommand.new(0, Vector3(30, 0, 30), 32, 6.0)
	assert_eq(state.execute(at), "", "the spot is free")


func test_going_down_during_its_own_activation_ends_it() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	var events: Array[GameEvent] = _apply_total(a1, 7)
	assert_true(state.get_model(a1).down)
	var ended: GameEvent = _last(events, GameEvent.Kind.ACTIVATION_ENDED)
	assert_not_null(ended)
	assert_eq(String(ended.data["reason"]), "went Down")
	assert_eq(state.turn.active_model_id, -1)
	assert_eq(state.turn.player_to_act, 1)
	assert_null(state.pending, "the open move is gone")


func test_out_of_action_during_its_own_activation_ends_it() -> void:
	_ok(BeginActionCommand.new(0, a1, &"move"))
	var events: Array[GameEvent] = _apply_total(a1, 9)
	assert_eq(String(_last(events, GameEvent.Kind.ACTIVATION_ENDED).data["reason"]), "taken Out of Action")


func test_a_down_model_stands_up_at_half_movement_next_activation() -> void:
	_apply_total(a2, 8)
	assert_true(state.get_model(a2).down)
	assert_almost_eq(TurnFlow.movement_budget(state, state.get_model(a2)), 3.0, 0.0001)
	_ok(EndActivationCommand.new(0, a1))
	_ok(EndActivationCommand.new(1, b1))
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, a2, &"move"))
	assert_not_null(_last(events, GameEvent.Kind.MODEL_STOOD_UP))
	assert_almost_eq(state.pending.budget, 3.0, 0.0001)


func test_blood_and_infection_add_dice_blessing_removes_them_in_order() -> void:
	var target: ModelState = state.get_model(b1)
	target.set_markers(Markers.BLOOD, 2)
	target.set_markers(Markers.INFECTION, 3)
	target.set_markers(Markers.BLESSING, 2)
	_start_injury(b1)
	# The opponent of the injured model first: blood and infection in one prompt.
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE)
	assert_eq(state.pending.player, 0)
	var choice: RollChoice = state.pending.choice
	assert_eq(choice.provider_id, &"blood")
	assert_eq(choice.options.size(), 2)
	assert_eq(choice.options[0].key, Markers.BLOOD)
	assert_eq(choice.options[0].maximum, 2)
	assert_eq(choice.options[1].key, Markers.INFECTION)
	assert_eq(choice.options[1].maximum, 3)
	assert_eq(choice.options[1].dice_per_unit, 1)
	assert_ne(state.execute(RollChoiceCommand.new(0, 0, [3, 0] as Array[int])), "", "only 2 blood")
	assert_ne(state.execute(RollChoiceCommand.new(1, 0, [1, 1] as Array[int])), "", "not player 1's decision")
	_ok(RollChoiceCommand.new(0, 0, [1, 2] as Array[int]))
	assert_eq(target.marker_count(Markers.BLOOD), 1, "spent markers are removed")
	assert_eq(target.marker_count(Markers.INFECTION), 1)
	# Then the injured model's player: blessing, -1 die each.
	assert_eq(state.pending.player, 1)
	assert_eq(state.pending.choice.provider_id, &"blessing")
	assert_eq(state.pending.choice.dice_per_unit, -1)
	var events: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 1))
	assert_eq(target.marker_count(Markers.BLESSING), 1)
	var resolved: GameEvent = _last(events, GameEvent.Kind.ROLL_RESOLVED)
	assert_eq(resolved.result.plus_dice, 3)
	assert_eq(resolved.result.minus_dice, 1)
	assert_eq(resolved.result.dice.size(), 4, "2 kept + net 2")
	assert_not_null(_last(events, GameEvent.Kind.INJURY_APPLIED))


func test_infection_alone_is_offered_without_blood() -> void:
	state.get_model(b1).set_markers(Markers.INFECTION, 1)
	_start_injury(b1)
	assert_eq(state.pending.choice.options.size(), 1)
	assert_eq(state.pending.choice.options[0].key, Markers.INFECTION)
	assert_string_contains(state.pending.choice.label, "infection")


func test_infection_is_spent_like_blood_on_success_rolls() -> void:
	var dasher: ModelState = state.get_model(a1)
	dasher.set_markers(Markers.INFECTION, 2)
	_ok(BeginActionCommand.new(0, a1, &"dash"))
	assert_eq(state.pending.player, 1, "the opponent decides")
	assert_eq(state.pending.choice.options[0].key, Markers.INFECTION)
	assert_eq(state.pending.choice.options[0].maximum, 3, "it grew at the start of the activation")
	assert_eq(state.pending.choice.options[0].dice_per_unit, -1)
	var events: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 2))
	assert_eq(_last(events, GameEvent.Kind.ROLL_RESOLVED).result.minus_dice, 2)
	assert_eq(dasher.marker_count(Markers.INFECTION), 1)


func test_infection_grows_at_activation_start_only_when_present() -> void:
	var with: ModelState = state.get_model(a1)
	var without: ModelState = state.get_model(a2)
	with.set_markers(Markers.INFECTION, 1)
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, a1, &"move"))
	assert_eq(with.marker_count(Markers.INFECTION), 2)
	var gained: GameEvent = _last(events, GameEvent.Kind.MARKERS_GAINED)
	assert_not_null(gained)
	assert_eq(gained.data["marker"], Markers.INFECTION)
	_ok(EndActivationCommand.new(0, a1))
	assert_eq(with.marker_count(Markers.INFECTION), 2, "not at the end, nor for other models")
	_ok(EndActivationCommand.new(1, b1))
	var other: Array[GameEvent] = _ok(EndActivationCommand.new(0, a2))
	assert_eq(without.marker_count(Markers.INFECTION), 0, "none to begin with: none gained")
	assert_null(_last(other, GameEvent.Kind.MARKERS_GAINED))


func test_infection_growth_is_capped() -> void:
	state.get_model(a1).set_markers(Markers.INFECTION, 6)
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, a1, &"move"))
	assert_eq(state.get_model(a1).marker_count(Markers.INFECTION), Markers.CAP)
	assert_null(_last(events, GameEvent.Kind.MARKERS_GAINED), "nothing gained at the cap")


func test_fall_dice_per_full_three_inches() -> void:
	var fall: ContextStepModifier = state.rules.modifier_provider(&"fall") as ContextStepModifier
	assert_not_null(fall)
	var expected: Dictionary = {2.9: 0, 3.0: 1, 5.0: 1, 5.99: 1, 6.0: 2, 8.0: 2, 9.0: 3, 11.5: 3}
	for height: float in expected:
		var request: RollRequest = RollRequest.injury(1, -1, a1)
		request.context = {&"fall_inches": height}
		var mods: Array[RollModifier] = fall.modifiers(state, request)
		var dice: int = 0 if mods.is_empty() else mods[0].dice
		assert_eq(dice, expected[height], "fall of %s\"" % height)
	var success: RollRequest = RollRequest.success(0, a1, &"dash", true, "Dash")
	success.context = {&"fall_inches": 6.0}
	assert_true(fall.modifiers(state, success).is_empty(), "injury rolls only")


func test_a_fall_injury_roll_rolls_the_extra_die() -> void:
	var events: Array[GameEvent] = _start_injury(b1, {&"fall_inches": 4.0})
	var resolved: GameEvent = _last(events, GameEvent.Kind.ROLL_RESOLVED)
	assert_not_null(resolved, "no markers: rolled at once")
	assert_eq(resolved.result.dice.size(), 3)
	assert_eq(resolved.result.modifiers[0].source, &"fall")


func test_armour_could_be_added_as_an_ordinary_provider() -> void:
	# Ruling 9: no armour yet, but a provider registered for injury rolls applies.
	var kinds: Array[RollRequest.Kind] = [RollRequest.Kind.INJURY]
	state.rules.add_modifier_provider(ContextStepModifier.new(&"test_armour", &"armour", "Armour %.0f", kinds, 1.0, -1))
	var events: Array[GameEvent] = _start_injury(b1, {&"armour": 1})
	var resolved: GameEvent = _last(events, GameEvent.Kind.ROLL_RESOLVED)
	assert_eq(resolved.result.minus_dice, 1)
