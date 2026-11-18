extends GutTest
## Charge planning on demand (brief 008c): the declaration check computes no
## route; one target's route is one goal-directed search, with no distance
## limit; interposing re-routes; routes are cached per state, and a change
## of state (another model moved, undo) searches again.

const R32: float = 0.62992126
const E = GameEvent.Kind

var state: GameState


func before_each() -> void:
	state = GameState.new(7)


func _place(player: int, pos: Vector3, base_mm: int = 32, movement: float = 6.0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, base_mm, movement)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


func _find(events: Array[GameEvent], kind: E) -> GameEvent:
	for event: GameEvent in events:
		if event.kind == kind:
			return event
	return null


func _searches() -> int:
	return state.charge_routes().searches


# --- Declaring (ruling 1) -------------------------------------------------------


func test_declaring_is_sight_and_range_and_computes_no_route() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var near: int = _place(1, Vector3(24, 0, 30))
	var past: int = _place(1, Vector3(24 + 12 + 2 * R32 + 0.1, 0, 24))
	# A wall between the charger and `hidden`, which is within 12".
	assert_eq(state.execute(PlaceTerrainCommand.new(Vector2(24, 20), Vector3(6, 4, 0.5))), "")
	var hidden: int = _place(1, Vector3(24, 0, 17))
	var fields_before: int = ReachField.built
	var planner: ChargePlanner = ChargePlanner.new(state, a)
	var declarations: Dictionary[int, String] = planner.declarations()
	assert_eq(declarations.get(near, "missing"), "", "visible and within 12\": can be declared")
	assert_false(declarations.has(past), "beyond 12\": not even in range")
	assert_string_contains(planner.target_error(state.get_model(past)), "more than 12")
	assert_string_contains(declarations.get(hidden, ""), "cannot see", "in range but not visible")
	assert_eq(planner.candidates().size(), 1)
	assert_eq(ReachField.built, fields_before, "no reach field was built to declare")
	assert_eq(_searches(), 0, "no route was searched to declare")


func test_a_target_that_cannot_be_declared_is_not_searched() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var past: int = _place(1, Vector3(40, 0, 24))
	var plan: ChargePlan = ChargePlanner.new(state, a).plan(past)
	assert_string_contains(plan.error, "more than 12")
	assert_eq(_searches(), 0)


# --- The route (rulings 3 to 5) --------------------------------------------------


func test_one_target_one_search_straight_to_contact() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var b: int = _place(1, Vector3(24, 0, 32))
	var planner: ChargePlanner = ChargePlanner.new(state, a)
	var plan: ChargePlan = planner.plan(b)
	assert_eq(_searches(), 1)
	assert_true(plan.contact)
	assert_almost_eq(plan.length, 8 - 2 * R32, 0.01)
	assert_eq(plan.needed, 1, "6 + 1 covers 6.74\"")
	assert_lt(planner.last_field.expanded, 200, "goal-directed: it stops when it gets there (%d states)" % planner.last_field.expanded)


func test_a_target_far_beyond_any_d6_gets_its_route_past_the_old_cap() -> void:
	# A see-through wall that cannot be climbed between the two: the way
	# round its end is about 30", far past 008b's 18" cap.
	assert_eq(state.execute(PlaceTerrainCommand.new(
		Vector2(15, 22), Vector3(0.5, 6, 32), 0.0, 0.0, TerrainPiece.Tag.IMPASSABLE, TerrainPiece.Shape.BOX, false
	)), "")
	var a: int = _place(0, Vector3(10, 0, 24))
	var far: int = _place(1, Vector3(20, 0, 24))
	var plan: ChargePlan = ChargePlanner.new(state, a).plan(far)
	assert_eq(plan.error, "", "seen through the wall, within 12\"")
	assert_true(plan.contact, "the route goes all the way round to base contact")
	assert_gt(plan.length, 25.0, "round the end of the wall (%.1f\")" % plan.length)
	assert_eq(plan.label(), "cannot reach")
	TurnHelper.ready_to_act(state, a)
	assert_true(DiceRig.rig(state, 1, 1, true, 6, 6), "a 6")
	var events: Array[GameEvent] = _ok(BeginActionCommand.new(0, a, &"charge", far))
	assert_not_null(_find(events, E.CHARGE_FAILED))
	var model: ModelState = state.get_model(a)
	assert_false(MeleeZone.in_melee(state, model), "stops outside every zone")
	assert_gt(model.position.z, 24.0 + 6.0, "it went along the route, towards the end of the wall (%s)" % model.position)
	assert_eq(_searches(), 1, "the declared charge used the route it was shown (ruling 7)")


func test_interposing_replaces_the_target_and_reroutes() -> void:
	var a: int = _place(0, Vector3(30, 0, 24))
	var target: int = _place(1, Vector3(20.5, 0, 24))
	var interposer: int = _place(1, Vector3(25, 0, 24.7))
	var plan: ChargePlan = ChargePlanner.new(state, a).plan(target)
	assert_eq(plan.declared_id, target)
	assert_eq(plan.target_id, interposer, "the model in the way is charged instead")
	assert_eq(plan.interposers, [interposer] as Array[int])
	assert_eq(_searches(), 2, "the route to the target, then the route to the interposer")
	assert_true(plan.contact)
	assert_true(MeleeZone.in_base_contact(plan.end(), R32, 1.9, state.get_model(interposer)), "the route ends on the interposer")


# --- The cache (ruling 2) ---------------------------------------------------------


func test_the_same_target_twice_searches_once_per_route_choice() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var b: int = _place(1, Vector3(24, 0, 30))
	var first: ChargePlan = ChargePlanner.new(state, a).plan(b)
	var again: ChargePlan = ChargePlanner.new(state, a).plan(b)
	assert_eq(_searches(), 1)
	assert_same(again, first, "the cached plan")
	assert_true(ChargePlanner.new(state, a).is_planned(b))
	assert_false(ChargePlanner.new(state, a).is_planned(b, true), "the other route choice is not worked out yet")
	ChargePlanner.new(state, a).plan(b, true)
	ChargePlanner.new(state, a).plan(b, true)
	assert_eq(_searches(), 2, "the other route choice once")
	ChargePlanner.new(state, a, Transitions.DescentMode.CLIMB_DOWN).plan(b)
	assert_eq(_searches(), 3, "another descent mode is another route")


func test_a_change_of_state_searches_again() -> void:
	var a: int = _place(0, Vector3(24, 0, 20))
	var other: int = _place(0, Vector3(10, 0, 10))
	var b: int = _place(1, Vector3(24, 0, 28))
	TurnHelper.ready_to_act(state, other)
	ChargePlanner.new(state, a).plan(b)
	assert_eq(_searches(), 1)
	# Another model moves.
	_ok(TurnHelper.move(state, other, [Vector3(12, 0, 10)] as Array[Vector3]))
	ChargePlanner.new(state, a).plan(b)
	assert_eq(_searches(), 2, "another model moved")
	ChargePlanner.new(state, a).plan(b)
	assert_eq(_searches(), 2, "the same state again: cached")
	assert_true(state.undo())
	ChargePlanner.new(state, a).plan(b)
	assert_eq(_searches(), 3, "after an undo")


func test_the_declared_charge_finds_the_route_in_the_cache() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var b: int = _place(1, Vector3(24, 0, 30))
	TurnHelper.ready_to_act(state, a)
	var shown: ChargePlan = ChargePlanner.new(state, a).plan(b)
	assert_eq(_searches(), 1)
	assert_true(DiceRig.rig(state, 1, 1, true, 6, 6), "a 6")
	_ok(BeginActionCommand.new(0, a, &"charge", b))
	assert_eq(_searches(), 1, "declaring searched nothing")
	assert_almost_eq(state.get_model(a).position.distance_to(shown.end()), 0.0, 0.02, "it moved along the route shown")
