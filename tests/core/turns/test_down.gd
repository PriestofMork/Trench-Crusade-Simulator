extends GutTest
## Down (docs/rules/markers.md; rulings 10 to 13 of brief 008b): a Down model
## cannot move, its success rolls get -1 die, going Down in its own
## activation ends it (in a Retreat too), and the ledge roll.

const R32: float = 0.62992126
const E = GameEvent.Kind

const SUCCESS: Array = [2, 2, true, 7, 12]
const FAILURE: Array = [2, 2, true, 2, 6]
const INJURY_DOWN: Array = [2, 2, true, 7, 8]
const INJURY_PLUS1_BLOOD: Array = [3, 2, true, 2, 6]
const INJURY_PLUS1_DOWN: Array = [3, 2, true, 7, 8]


## A free attack that only puts its target Down, through the one Down step
## (free attacks do no damage until brief 009).
class DownHook:
	extends FreeAttackHook

	func resolve(state: GameState, _attacker_id: int, target_id: int, events: Array[GameEvent], done: Callable) -> void:
		GoingDown.result(state, state.get_model(target_id), events, done)


var state: GameState


func before_each() -> void:
	state = GameState.new(5)


func _place(player: int, pos: Vector3, base_mm: int = 32) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, base_mm, 6.0)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _piece(center: Vector2, size: Vector3) -> void:
	assert_eq(state.execute(PlaceTerrainCommand.new(center, size, 0.0, 0.0)), "")


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


func _rig(rolls: Array) -> void:
	assert_true(DiceRig.rig_sequence(state, rolls), "a seed for %s" % str(rolls))


func _find(events: Array[GameEvent], kind: E) -> GameEvent:
	for event: GameEvent in events:
		if event.kind == kind:
			return event
	return null


func _count(events: Array[GameEvent], kind: E) -> int:
	var n: int = 0
	for event: GameEvent in events:
		if event.kind == kind:
			n += 1
	return n


## Answers every marker prompt by spending nothing, adding the events.
func _answer_prompts(events: Array[GameEvent]) -> void:
	while state.pending != null and state.pending.kind == PendingDecision.Kind.ROLL_CHOICE:
		events.append_array(_ok(RollChoiceCommand.new(state.pending.player, 0)))


func _sources(roll: ActiveRoll) -> Array[StringName]:
	var result: Array[StringName] = []
	for modifier: RollModifier in roll.modifiers:
		result.append(modifier.source)
	return result


# --- Ruling 10: no moves ------------------------------------------------------


func test_a_down_model_cannot_be_given_a_move() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	_place(1, Vector3(40, 0, 40))
	TurnHelper.grant_move(state, a)
	_ok(SetDownOverride.new(a, true))
	var error: String = state.execute(MoveCommand.new(0, a, [Vector3(12, 0, 10)] as Array[Vector3]))
	assert_eq(error, MovePath.DOWN_ERROR % a)
	assert_eq(state.get_model(a).position, Vector3(10, 0, 10))
	var path: MovePath = MovePath.new(state, a, [Vector3(11, 0, 10)] as Array[Vector3], 6.0, Transitions.DescentMode.DROP, EnemyZones.retreat([]))
	assert_false(path.is_legal(), "no kind of move (a retreat's either)")


# --- Ruling 11: -1 die on success rolls ---------------------------------------


func test_a_down_models_success_rolls_get_minus_one_die_until_it_stands() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	_place(1, Vector3(40, 0, 40))
	_ok(StartGameCommand.new())
	TurnHelper.settle(state)
	state.get_model(a).down = true
	_rig([[3, 2, false, 2, 12], [2, 2, true, 2, 6]])
	var events: Array[GameEvent] = []
	RollPipeline.start(state, RollRequest.success(0, a, &"", false, "Test roll"), events)
	var requested: GameEvent = _find(events, E.ROLL_REQUESTED)
	assert_true(_sources(requested.roll).has(&"down"), "the Down modifier")
	var resolved: GameEvent = _find(events, E.ROLL_RESOLVED)
	assert_eq(resolved.result.dice.size(), 3, "2 kept of 3, the lowest")
	assert_eq(resolved.result.minus_dice, 1)
	# Injury rolls against it are not success rolls: no Down modifier.
	var injury: Array[GameEvent] = []
	RollPipeline.start(state, RollRequest.injury(1, -1, a), injury)
	assert_false(_sources(_find(injury, E.ROLL_REQUESTED).roll).has(&"down"))
	# It stands up at the start of its activation: its Dash has no penalty.
	TurnHelper.ready_to_act(state, a)
	var dash: Array[GameEvent] = _ok(BeginActionCommand.new(0, a, &"dash"))
	assert_not_null(_find(dash, E.MODEL_STOOD_UP))
	assert_false(_sources(_find(dash, E.ROLL_REQUESTED).roll).has(&"down"))


# --- Ruling 12: going Down ends the activation --------------------------------


func test_going_down_in_its_own_activation_ends_it() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	_place(1, Vector3(40, 0, 40))
	TurnHelper.grant_move(state, a)
	var events: Array[GameEvent] = []
	GoingDown.result(state, state.get_model(a), events)
	assert_true(state.get_model(a).down)
	assert_eq(String(_find(events, E.ACTIVATION_ENDED).data["reason"]), "went Down")
	assert_eq(state.turn.active_model_id, -1)
	assert_null(state.pending, "the open move is gone")


func test_a_retreating_model_put_down_by_a_free_attack_stays_in_melee_and_ends() -> void:
	state.rules.free_attack = DownHook.new()
	var a: int = _place(0, Vector3(10, 0, 10))
	var b: int = _place(1, Vector3(10 + 2 * R32 + 0.5, 0, 10))
	TurnHelper.ready_to_act(state, a)
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, a, &"retreat"))
	var model: ModelState = state.get_model(a)
	assert_true(model.down)
	assert_eq(model.position, Vector3(10, 0, 10), "it stays where it is")
	assert_true(MeleeZone.in_melee(state, model), "still in melee")
	assert_eq(_count(events, E.ACTIVATION_ENDED), 1)
	assert_null(state.pending, "no retreat move")
	assert_ne(state.turn.active_model_id, a)
	assert_eq(MeleeZone.enemy_ids_within(state, model), [b] as Array[int])


# --- Ruling 13: the ledge roll ------------------------------------------------


## A 3" (or `height`) block x 17..23, z 17..23 and a model on it whose base
## edge is `from_edge` from the east edge.
func _on_block(from_edge: float, height: float = 3.0) -> int:
	_piece(Vector2(20, 20), Vector3(6, height, 6))
	_place(1, Vector3(45, 0, 45))
	return _place(0, Vector3(23 - R32 - from_edge, height, 20))


func test_a_ledge_is_found_within_an_inch_of_the_base_edge() -> void:
	var a: int = _on_block(0.5)
	var ledge: Dictionary = GoingDown.ledge_for(state, state.get_model(a))
	assert_false(ledge.is_empty())
	assert_almost_eq(float(ledge["distance"]), 0.5, 0.01)
	assert_almost_eq(float(ledge["drop"]), 3.0, 0.001)
	assert_almost_eq((ledge["point"] as Vector3).x, 23.0, 0.001)
	assert_eq(ledge["normal"], Vector2(1, 0))


func test_no_ledge_just_over_an_inch_away() -> void:
	var a: int = _on_block(1.02)
	assert_true(GoingDown.ledge_for(state, state.get_model(a)).is_empty())


func test_a_one_inch_step_is_no_ledge() -> void:
	var a: int = _on_block(0.2, 1.0)
	assert_true(GoingDown.ledge_for(state, state.get_model(a)).is_empty())


func test_a_seam_or_a_wall_up_is_no_ledge() -> void:
	# A second 3" block east of the first (a seam) and a taller one north (a wall up).
	_piece(Vector2(26, 20), Vector3(6, 3, 6))
	_piece(Vector2(23, 26), Vector3(12, 5, 6))
	var a: int = _on_block(0.2)
	state.get_model(a).position = Vector3(23 - R32 - 0.2, 3, 23 - R32 - 0.2)
	assert_true(GoingDown.ledge_for(state, state.get_model(a)).is_empty())


func test_a_down_result_next_to_a_ledge_makes_the_ledge_roll_first_success() -> void:
	var a: int = _on_block(0.5)
	TurnHelper.settle(state)
	_rig([SUCCESS])
	var events: Array[GameEvent] = []
	GoingDown.result(state, state.get_model(a), events)
	var ledge: GameEvent = _find(events, E.LEDGE_ROLL)
	assert_not_null(ledge)
	assert_string_contains(String(ledge.data["reason"]), "ledge roll")
	var roll: GameEvent = _find(events, E.ROLL_RESOLVED)
	assert_eq(roll.result.request.kind, RollRequest.Kind.SUCCESS)
	assert_false(roll.result.risky, "not risky")
	assert_eq(roll.result.modifiers.size(), 0, "made before the model is Down: no Down penalty")
	assert_true(GameEvent.kinds(events).find(E.ROLL_RESOLVED) < GameEvent.kinds(events).find(E.MODEL_WENT_DOWN))
	assert_true(state.get_model(a).down)
	assert_eq(state.get_model(a).position, Vector3(23 - R32 - 0.5, 3, 20), "Down where it is")
	assert_eq(state.interrupts.size(), 0)


func test_a_failed_ledge_roll_falls_with_the_injury_roll_and_is_down_below() -> void:
	var a: int = _on_block(0.5)
	TurnHelper.settle(state)
	_rig([FAILURE, INJURY_PLUS1_BLOOD])
	var events: Array[GameEvent] = []
	GoingDown.result(state, state.get_model(a), events)
	var fell: GameEvent = _find(events, E.MODEL_FELL)
	assert_not_null(fell)
	assert_almost_eq(float(fell.data["height"]), 3.0, 0.001)
	var model: ModelState = state.get_model(a)
	assert_almost_eq(model.position.y, 0.0, 0.001, "over the nearest ledge, onto the ground")
	assert_true(model.position.x > 23.0, "east of the block")
	assert_eq(_count(events, E.ROLL_RESOLVED), 2, "the ledge roll, then the fall's injury roll")
	assert_eq(model.marker_count(Markers.BLOOD), 1)
	assert_true(model.down, "Down where it lands")
	assert_eq(_count(events, E.LEDGE_ROLL), 1)


func test_the_falls_own_down_result_makes_no_second_ledge_roll() -> void:
	# A 6" block, and a narrow 3" ledge east of it (z 19..21): landing there,
	# the model is within 1" of its edges, but the fall's Down makes no roll.
	_piece(Vector2(20, 20), Vector3(6, 6, 6))
	_piece(Vector2(25, 20), Vector3(4, 3, 2))
	_place(1, Vector3(45, 0, 45))
	var a: int = _place(0, Vector3(23 - R32 - 0.5, 6, 20))
	TurnHelper.settle(state)
	_rig([FAILURE, INJURY_PLUS1_DOWN])
	var events: Array[GameEvent] = []
	GoingDown.result(state, state.get_model(a), events)
	var model: ModelState = state.get_model(a)
	assert_almost_eq(model.position.y, 3.0, 0.001, "on the narrow ledge")
	assert_false(GoingDown.ledge_for(state, model).is_empty(), "which has a ledge of its own")
	assert_eq(_count(events, E.LEDGE_ROLL), 1, "but only the one ledge roll")
	assert_true(model.down)
	assert_eq(_count(events, E.MODEL_WENT_DOWN), 1)


func test_a_model_already_down_makes_no_ledge_roll() -> void:
	var a: int = _on_block(0.5)
	TurnHelper.settle(state)
	state.get_model(a).down = true
	var events: Array[GameEvent] = []
	GoingDown.result(state, state.get_model(a), events)
	assert_eq(_count(events, E.LEDGE_ROLL), 0)
	assert_eq(state.get_model(a).position, Vector3(23 - R32 - 0.5, 3, 20))


func test_an_injury_down_holds_its_roll_until_the_ledge_roll_is_over() -> void:
	var a: int = _on_block(0.5)
	TurnHelper.settle(state)
	_rig([INJURY_DOWN, FAILURE, INJURY_PLUS1_BLOOD])
	var events: Array[GameEvent] = []
	var request: RollRequest = RollRequest.injury(1, -1, a)
	request.on_resolved = func(_s: GameState, _r: RollResult, evs: Array[GameEvent]) -> void:
		evs.append(GameEvent.new(GameEvent.Kind.OVERRIDE_APPLIED, -1, -1, {"text": "requester"}))
	RollPipeline.start(state, request, events)
	# The injury placed a blood marker: the ledge roll asks about it first.
	assert_eq(state.interrupts.size(), 1, "the ledge roll waits for its prompt")
	assert_false(GameEvent.kinds(events).has(E.OVERRIDE_APPLIED), "the injury roll's requester is still waiting")
	_answer_prompts(events)
	var kinds: Array[E] = GameEvent.kinds(events)
	assert_true(kinds.has(E.LEDGE_ROLL), "an injury roll's Down goes through the ledge roll")
	assert_true(kinds.find(E.MODEL_FELL) < kinds.find(E.OVERRIDE_APPLIED), "the requester hears of it after")
	assert_true(kinds.find(E.MODEL_WENT_DOWN) < kinds.find(E.OVERRIDE_APPLIED))
	assert_true(state.get_model(a).down)


func test_ledge_rolls_take_marker_spending_and_undo_across_them() -> void:
	var a: int = _on_block(0.5)
	_ok(StartGameCommand.new())
	TurnHelper.settle(state)
	state.get_model(a).set_markers(Markers.BLESSING, 2)
	# An injury roll against it, waiting for its marker prompt; the commands
	# answering the prompts carry the rest, so undo can step through them.
	var size: int = state.history.size()
	_rig([INJURY_DOWN])
	var events: Array[GameEvent] = []
	RollPipeline.start(state, RollRequest.injury(1, -1, a), events)
	# First the injury roll's own prompt (blessing markers against it).
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE)
	_ok(RollChoiceCommand.new(0, 0))
	# The ledge roll: the blood marker the injury placed (the opponent's
	# prompt), then the blessing markers (the owner's).
	assert_eq(state.interrupts.size(), 1)
	assert_eq(state.active_roll.request.label, "Ledge roll")
	assert_eq(state.pending.player, 1)
	_ok(RollChoiceCommand.new(1, 0))
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE, "the ledge roll offers the blessing markers")
	assert_eq(state.pending.player, 0)
	var before: Vector3 = state.get_model(a).position
	_rig([FAILURE, INJURY_PLUS1_BLOOD])
	size = state.history.size()
	_ok(RollChoiceCommand.new(0, 0))
	_answer_prompts([] as Array[GameEvent])
	assert_eq(state.interrupts.size(), 0)
	assert_true(state.get_model(a).down)
	while state.history.size() > size:
		if not state.undo():
			fail_test("undo refused")
			return
	assert_eq(state.interrupts.size(), 1, "undo brings the ledge roll back")
	assert_eq(state.active_roll.request.label, "Ledge roll")
	assert_eq(state.get_model(a).position, before)
	assert_false(state.get_model(a).down)
