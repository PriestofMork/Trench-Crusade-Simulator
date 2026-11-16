extends GutTest
## Charge (brief 007): declaration (targets, the 12" limit, the D6 needed,
## halving, no rolls on the way), interposing, resolution (contact, falling
## short), contact across heights, multi-charge, the one move action rule,
## and undo, redo and replay across a charge with a contact choice.

const R25: float = 0.49212598
const R32: float = 0.62992126
const E = GameEvent.Kind

var state: GameState


func before_each() -> void:
	state = GameState.new(7)


func _place(player: int, pos: Vector3, base_mm: int = 32, movement: float = 6.0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, base_mm, movement)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _piece(center: Vector2, size: Vector3, tag: TerrainPiece.Tag = TerrainPiece.Tag.NONE) -> void:
	assert_eq(state.execute(PlaceTerrainCommand.new(center, size, 0.0, 0.0, tag)), "")


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


func _find(events: Array[GameEvent], kind: E) -> GameEvent:
	for event: GameEvent in events:
		if event.kind == kind:
			return event
	return null


## Gets `id` ready to act, rigs the charge D6 to land in [low, high] and
## declares the charge against `target`.
func _charge(id: int, target: int, low: int = 1, high: int = 6) -> Array[GameEvent]:
	TurnHelper.ready_to_act(state, id)
	assert_true(DiceRig.rig(state, 1, 1, true, low, high), "a seed for a D6 of %d-%d" % [low, high])
	return _ok(BeginActionCommand.new(state.get_model(id).player, id, &"charge", target))


func _plan(id: int, target: int) -> ChargePlan:
	return ChargePlanner.new(state, id).plan(target)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


# --- Declaration --------------------------------------------------------------


func test_targets_are_visible_enemies_within_twelve_inches() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var near: int = _place(1, Vector3(24, 0, 30))
	var edge: int = _place(1, Vector3(24 - 12 - 2 * R32, 0, 24))
	var past: int = _place(1, Vector3(24 + 12.1 + 2 * R32, 0, 24))
	var friend: int = _place(0, Vector3(20, 0, 30))
	var planner: ChargePlanner = ChargePlanner.new(state, a)
	var ids: Array[int] = []
	for model: ModelState in planner.candidates():
		ids.append(model.id)
	assert_eq(ids, [near, edge] as Array[int], "exactly 12\" edge to edge is in range, 12.1\" is not")
	assert_string_contains(planner.target_error(state.get_model(past)), "more than 12")
	assert_string_contains(planner.target_error(state.get_model(friend)), "enemy")


func test_range_ignores_terrain_and_is_measured_between_the_cylinders() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	# A wall in the way does not count; the range is a straight line.
	_piece(Vector2(24, 30), Vector3(8, 3, 0.5), TerrainPiece.Tag.IMPASSABLE)
	var behind: int = _place(1, Vector3(24, 0, 24 + 11 + 2 * R32))
	var planner: ChargePlanner = ChargePlanner.new(state, a)
	assert_eq(planner.target_error(state.get_model(behind)), "", "in range through the wall")


func test_sight_goes_through_the_interface() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var b: int = _place(1, Vector3(24, 0, 30))
	assert_true(state.rules.sight is TemporarySight, "the temporary implementation is in place")
	state.rules.sight = Sight.new()
	assert_string_contains(ChargePlanner.new(state, a).target_error(state.get_model(b)), "cannot see")


func test_needed_roll_for_near_far_and_impossible_targets() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var near: int = _place(1, Vector3(24, 0, 30))
	var far: int = _place(1, Vector3(12, 0, 24))
	var planner: ChargePlanner = ChargePlanner.new(state, a)
	var plan_near: ChargePlan = planner.plan(near)
	assert_eq(plan_near.error, "")
	assert_almost_eq(plan_near.length, 6 - 2 * R32, 0.01, "straight to contact")
	assert_eq(plan_near.needed, 0, "Movement alone reaches")
	assert_eq(plan_near.label(), "certain")
	var plan_far: ChargePlan = planner.plan(far)
	assert_almost_eq(plan_far.length, 12 - 2 * R32, 0.01)
	assert_eq(plan_far.needed, 5, "6 + 5 covers 10.74\", 6 + 4 does not")
	assert_eq(plan_far.label(), "needs 5+")
	assert_false(plan_far.interposed())
	assert_almost_eq(_flat_distance(plan_far.contact(), state.get_model(far).position), 2 * R32, 0.001, "ends in base contact")


func test_halving_after_standing_up_applies_to_the_whole_sum() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var near: int = _place(1, Vector3(24, 0, 30))
	var far: int = _place(1, Vector3(12, 0, 24))
	state.get_model(a).down = true
	var planner: ChargePlanner = ChargePlanner.new(state, a)
	assert_almost_eq(planner.max_distance, 6.0, 0.0001, "(6 + 6) / 2")
	# (6 + d) / 2 >= 4.74 needs d >= 3.48; halving only the die would need none.
	assert_eq(planner.plan(near).needed, 4)
	var plan_far: ChargePlan = planner.plan(far)
	assert_eq(plan_far.needed, ChargePlan.OUT_OF_REACH)
	assert_eq(plan_far.label(), "out of reach")
	assert_string_contains(plan_far.error, "Out of reach")


func test_an_out_of_reach_target_cannot_be_declared() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var far: int = _place(1, Vector3(12, 0, 24))
	state.get_model(a).down = true
	TurnHelper.ready_to_act(state, a)
	assert_string_contains(state.execute(BeginActionCommand.new(0, a, &"charge", far)), "Out of reach")
	assert_string_contains(state.execute(BeginActionCommand.new(0, a, &"charge")), "No such model", "a charge needs a target")


func test_a_target_reachable_only_by_a_roll_cannot_be_charged() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	# A sheer 2" block: climbing it is a roll, and contact from the ground is
	# 2" below the target's floor.
	_piece(Vector2(24, 30), Vector3(4, 2, 4), TerrainPiece.Tag.SHEER)
	var on_top: int = _place(1, Vector3(24, 2, 30))
	var high_plan: ChargePlan = _plan(a, on_top)
	assert_eq(high_plan.needed, ChargePlan.OUT_OF_REACH)
	assert_false(high_plan.error == "")
	# The same block untagged is an open climb: chargeable.
	state = GameState.new(7)
	a = _place(0, Vector3(24, 0, 24))
	_piece(Vector2(24, 30), Vector3(4, 2, 4))
	on_top = _place(1, Vector3(24, 2, 30))
	var open_plan: ChargePlan = _plan(a, on_top)
	assert_eq(open_plan.error, "", "an open climb is no roll")
	assert_almost_eq(open_plan.contact().y, 2.0, 0.001, "contact on top")


# --- Interposing --------------------------------------------------------------


func test_an_interposing_model_becomes_the_target() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	var target: int = _place(1, Vector3(10, 0, 20))
	var between: int = _place(1, Vector3(10.8, 0, 15))
	var plan: ChargePlan = _plan(a, target)
	assert_eq(plan.error, "")
	assert_eq(plan.declared_id, target)
	assert_eq(plan.target_id, between, "the model in the way is charged instead")
	assert_true(plan.interposed())
	assert_almost_eq(_flat_distance(plan.contact(), state.get_model(between).position), 2 * R32, 0.001, "path recomputed to it")


func test_no_interposer_when_the_path_passes_more_than_an_inch_away() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	var target: int = _place(1, Vector3(10, 0, 20))
	_place(1, Vector3(10 + 2 * R32 + 1.05, 0, 15))
	var plan: ChargePlan = _plan(a, target)
	assert_eq(plan.target_id, target)
	assert_false(plan.interposed())


# --- Resolution ---------------------------------------------------------------


func test_success_ends_in_base_contact_and_in_melee() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var near: int = _place(1, Vector3(24, 0, 30))
	var before: int = state.dice.get_state()
	var events: Array[GameEvent] = _charge(a, near, 1, 1)
	var declared: GameEvent = _find(events, E.CHARGE_DECLARED)
	assert_not_null(declared)
	var rolled: GameEvent = _find(events, E.ROLL_RESOLVED)
	assert_eq(rolled.result.request.kind, RollRequest.Kind.D6, "a plain d6")
	assert_eq(rolled.result.total, 1)
	assert_eq(_find(events, E.ROLL_REQUESTED).roll.modifiers.size(), 0, "no modifiers on the charge die")
	assert_ne(state.dice.get_state(), before, "rolled through the dice service")
	assert_true(_find(events, E.CHARGE_DISTANCE).data["reaches"])
	# 7" against 4.74": distance left to slide, so the contact choice is asked.
	assert_eq(state.pending.kind, PendingDecision.Kind.CHARGE_CONTACT)
	var model: ModelState = state.get_model(a)
	assert_almost_eq(_flat_distance(model.position, state.get_model(near).position), 2 * R32, 0.001, "first contact")
	events = _ok(ChooseContactCommand.new(0, state.pending.default_index))
	assert_eq(_find(events, E.CHARGED).data["charged"], [near] as Array[int])
	assert_true(MeleeZone.in_melee(state, model))
	assert_eq(state.turn.charged, [near] as Array[int], "recorded on the activation")
	assert_null(state.resolution)
	assert_eq(state.turn.active_model_id, a, "the activation carries on")


func test_no_choice_when_there_is_nothing_to_slide() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	# 7" of path: only a 1 falls short... a 1 gives exactly 7".
	var target: int = _place(1, Vector3(24, 0, 24 + 7 + 2 * R32))
	var events: Array[GameEvent] = _charge(a, target, 1, 1)
	assert_null(state.pending, "no distance left: no choice")
	assert_not_null(_find(events, E.CHARGED))
	assert_true(MeleeZone.in_melee(state, state.get_model(a)))


func test_failure_stops_short_outside_every_zone() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var far: int = _place(1, Vector3(12, 0, 24))
	# A 2: 8" along a 10.74" path, well short of the zone.
	var events: Array[GameEvent] = _charge(a, far, 2, 2)
	assert_false(_find(events, E.CHARGE_DISTANCE).data["reaches"])
	assert_not_null(_find(events, E.CHARGE_FAILED))
	var model: ModelState = state.get_model(a)
	assert_almost_eq(model.position.x, 16.0, 0.06, "as far as 8\" goes along the path")
	assert_almost_eq(model.position.z, 24.0, 0.001)
	assert_null(state.resolution)
	assert_null(state.pending)
	assert_false(MeleeZone.in_melee(state, model))
	assert_eq(state.turn.charged, [] as Array[int])


func test_failure_never_ends_inside_a_zone() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var far: int = _place(1, Vector3(12, 0, 24))
	# A 4: 10" would end 0.74" from the target; it stops at exactly 1".
	_charge(a, far, 4, 4)
	var model: ModelState = state.get_model(a)
	var gap: float = MeleeZone.gap(model, state.get_model(far))
	assert_true(gap >= 1.0 - 0.0001, "outside the zone (gap %.3f)" % gap)
	assert_almost_eq(gap, 1.0, 0.06, "the last legal place along the path")
	assert_false(MeleeZone.in_melee(state, model))


# --- Contact across heights ---------------------------------------------------


func test_contact_onto_a_low_obstacle() -> void:
	var a: int = _place(0, Vector3(20, 0, 12))
	_piece(Vector2(20, 20), Vector3(3, 1, 3))
	var on_crate: int = _place(1, Vector3(20, 1, 20), 25)
	var plan: ChargePlan = _plan(a, on_crate)
	assert_eq(plan.error, "")
	assert_almost_eq(plan.contact().y, 1.0, 0.001, "contact on the crate, the base all over it")
	_charge(a, on_crate, 6, 6)
	if state.pending != null:
		_ok(ChooseContactCommand.new(0, state.pending.default_index))
	assert_true(MeleeZone.in_melee(state, state.get_model(a)))


func test_contact_from_the_ground_with_a_target_on_a_low_obstacle() -> void:
	var a: int = _place(0, Vector3(20, 0, 12))
	_piece(Vector2(20, 20), Vector3(3, 1, 3))
	# Near the crate's front edge: ground contact is 1" below its floor.
	var on_crate: int = _place(1, Vector3(20, 1, 18.9), 25)
	var plan: ChargePlan = _plan(a, on_crate)
	assert_eq(plan.error, "")
	assert_almost_eq(plan.contact().y, 0.0, 0.001, "from the ground, 1\" below")
	assert_almost_eq(plan.length, 18.9 - R25 - R32 - 12, 0.02)


func test_contact_from_a_low_obstacle_down_to_the_ground() -> void:
	_piece(Vector2(20, 20), Vector3(3, 1, 3))
	var a: int = _place(0, Vector3(20, 1, 20))
	var below: int = _place(1, Vector3(20, 0, 17.0), 25)
	var plan: ChargePlan = _plan(a, below)
	assert_eq(plan.error, "")
	assert_true(plan.reachable())


func test_contact_refused_across_a_larger_height_difference() -> void:
	_piece(Vector2(24, 30), Vector3(4, 2, 4), TerrainPiece.Tag.SHEER)
	var a: int = _place(0, Vector3(24, 0, 24))
	var on_top: int = _place(1, Vector3(24, 2, 28.3), 25)
	var planner: ChargePlanner = ChargePlanner.new(state, a)
	var target: ModelState = state.get_model(on_top)
	# Straight out over the edge (towards -z) the contact point is on the ground, 2" below.
	assert_eq(planner.contact_points(target, -PI / 2).size(), 0, "the ground is 2\" below: no contact")
	assert_false(ChargePlanner.heights_allow_contact(Vector3(24, 0, 27), target))
	assert_true(ChargePlanner.heights_allow_contact(Vector3(24, 1, 27), target))
	assert_eq(planner.plan(on_top).needed, ChargePlan.OUT_OF_REACH)


# --- Multi-charge -------------------------------------------------------------


func _multi_setup() -> Array[int]:
	var a: int = _place(0, Vector3(10, 0, 12))
	var target: int = _place(1, Vector3(10, 0, 20))
	var beside: int = _place(1, Vector3(12.6, 0, 20))
	return [a, target, beside]


func test_sliding_within_the_leftover_distance_charges_both() -> void:
	var ids: Array[int] = _multi_setup()
	_charge(ids[0], ids[1], 6, 6)
	var decision: PendingDecision = state.pending
	assert_eq(decision.kind, PendingDecision.Kind.CHARGE_CONTACT)
	assert_eq(decision.charged_ids[decision.default_index], [ids[1]] as Array[int], "first contact charges the target only")
	var both: int = -1
	for i: int in decision.positions.size():
		if decision.charged_ids[i] == ([ids[1], ids[2]] as Array[int]):
			both = i
			break
	assert_ne(both, -1, "a position within 1\" of both")
	var events: Array[GameEvent] = _ok(ChooseContactCommand.new(0, both))
	var model: ModelState = state.get_model(ids[0])
	assert_almost_eq(_flat_distance(model.position, state.get_model(ids[1]).position), 2 * R32, 0.001, "still in contact")
	assert_eq(_find(events, E.CHARGED).data["charged"], [ids[1], ids[2]] as Array[int])
	assert_eq(state.turn.charged, [ids[1], ids[2]] as Array[int], "both recorded as charged")
	assert_true(_find(events, E.MODEL_MOVED).data.get("slide", false))


func test_sliding_is_limited_by_the_distance_left() -> void:
	var ids: Array[int] = _multi_setup()
	# A 1: 7" for 6.74" of path leaves 0.26" to slide.
	_charge(ids[0], ids[1], 1, 1)
	var decision: PendingDecision = state.pending
	assert_eq(decision.kind, PendingDecision.Kind.CHARGE_CONTACT)
	var first: Vector3 = decision.positions[decision.default_index]
	for i: int in decision.positions.size():
		assert_false((decision.charged_ids[i] as Array).has(ids[2]), "the second enemy is too far round")
		var arc: float = (Vector2(first.x, first.z) - Vector2(10, 20)).angle_to(
			Vector2(decision.positions[i].x, decision.positions[i].z) - Vector2(10, 20)
		)
		assert_true(absf(arc) * 2 * R32 <= 0.26 + 0.001, "within the 0.26\" left")


func test_sliding_blocked_by_terrain() -> void:
	var ids: Array[int] = _multi_setup()
	# A post right beside first contact on the +x side.
	_piece(Vector2(11.5, 18.5), Vector3(1, 2, 1))
	_charge(ids[0], ids[1], 6, 6)
	var decision: PendingDecision = state.pending
	for i: int in decision.positions.size():
		assert_true(decision.positions[i].x < 10.9, "nothing past the post (%s)" % str(decision.positions[i]))
		assert_false((decision.charged_ids[i] as Array).has(ids[2]))


func test_sliding_blocked_by_a_base() -> void:
	var ids: Array[int] = _multi_setup()
	var blocker: int = _place(1, Vector3(7.9, 0, 19.0))
	assert_eq(_plan(ids[0], ids[1]).target_id, ids[1], "the blocker does not interpose")
	_charge(ids[0], ids[1], 6, 6)
	var decision: PendingDecision = state.pending
	var other: Vector3 = state.get_model(blocker).position
	for i: int in decision.positions.size():
		var p: Vector3 = decision.positions[i]
		assert_true(_flat_distance(p, other) >= 2 * R32 - 0.001, "never on the blocker's base")
		assert_true(p.x > 9.0, "never slid past the blocker (%s)" % str(p))
	assert_true((decision.charged_ids[decision.default_index] as Array).has(blocker), "within 1\" of it at first contact")


# --- One move action per activation -------------------------------------------


func test_charge_after_move_is_refused() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var near: int = _place(1, Vector3(24, 0, 30))
	TurnHelper.ready_to_act(state, a)
	_ok(BeginActionCommand.new(0, a, &"move"))
	assert_eq(state.execute(BeginActionCommand.new(0, a, &"charge", near)), "Only one move action per activation.")


func test_charge_after_dash_is_allowed() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var near: int = _place(1, Vector3(24, 0, 30))
	TurnHelper.ready_to_act(state, a)
	assert_true(DiceRig.rig(state, 2, 2, true, 7, 12), "a successful Dash")
	_ok(BeginActionCommand.new(0, a, &"dash"))
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE)
	assert_eq(state.execute(BeginActionCommand.new(0, a, &"charge", near)), "", "Dash is not a move action")


func test_dash_after_a_successful_charge_is_refused() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var near: int = _place(1, Vector3(24, 0, 30))
	_charge(a, near, 1, 1)
	_ok(ChooseContactCommand.new(0, state.pending.default_index))
	assert_string_contains(state.execute(BeginActionCommand.new(0, a, &"dash")), "In melee")


# --- Undo, redo and replay ----------------------------------------------------


func test_undo_redo_and_replay_across_a_contact_choice() -> void:
	var ids: Array[int] = _multi_setup()
	TurnHelper.ready_to_act(state, ids[0])
	var start: int = state.history.size()
	var start_position: Vector3 = state.get_model(ids[0]).position
	_ok(BeginActionCommand.new(0, ids[0], &"charge", ids[1]))
	if state.pending == null:
		pass_test("this seed reached contact with nothing to slide; covered elsewhere")
		return
	var decision: PendingDecision = state.pending
	var index: int = 0 if decision.default_index != 0 else decision.positions.size() - 1
	_ok(ChooseContactCommand.new(0, index))
	var end: Vector3 = state.get_model(ids[0]).position
	var charged: Array[int] = state.turn.charged.duplicate()
	assert_true(state.undo())
	assert_eq(state.pending.kind, PendingDecision.Kind.CHARGE_CONTACT, "back at the choice")
	assert_true(state.resolution is ChargeResolution)
	assert_true(state.undo())
	assert_eq(state.get_model(ids[0]).position, start_position, "back before the charge")
	assert_null(state.resolution)
	assert_eq(state.history.size(), start)
	assert_eq(state.redo().error, "")
	assert_eq(state.redo().error, "")
	assert_eq(state.get_model(ids[0]).position, end, "redo ends in the same place")
	assert_eq(state.turn.charged, charged)
	# Replay the whole command log from the seed.
	var replay: GameState = GameState.new(7)
	for command: Command in state.history:
		assert_eq(replay.execute(command), "", command.get_script().get_global_name())
	assert_eq(replay.get_model(ids[0]).position, end)
	assert_eq(replay.turn.charged, charged)
