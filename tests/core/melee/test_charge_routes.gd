extends GutTest
## Charges on the shared movement process (brief 008b): routes with sheer
## climbs, gap jumps and drops and their rolls, the route toggle, hopeless
## charges, the pillar case, base contact and sliding across heights, and
## undo, redo and replay across a charge with a roll on its route.

const R25: float = 0.49212598
const R32: float = 0.62992126
const R40: float = 0.78740157
const E = GameEvent.Kind
const K = Transitions.Kind

const SUCCESS: Array = [2, 2, true, 7, 12]
const FAILURE: Array = [2, 2, true, 2, 6]
## An injury roll at +1 die (a fall of 3" to 5"): 3 dice, keep the highest 2.
const INJURY_PLUS1_BLOOD: Array = [3, 2, true, 2, 6]
const INJURY_PLUS1_DOWN: Array = [3, 2, true, 7, 8]

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


func _count(events: Array[GameEvent], kind: E) -> int:
	var n: int = 0
	for event: GameEvent in events:
		if event.kind == kind:
			n += 1
	return n


## The D6 of a charge coming up `roll`.
func _d6(roll: int) -> Array:
	return [1, 1, true, roll, roll]


## Gets `id` ready, rigs the next rolls and declares the charge.
func _charge(id: int, target: int, rolls: Array, allow_rolls: bool = true) -> Array[GameEvent]:
	TurnHelper.ready_to_act(state, id)
	assert_true(DiceRig.rig_sequence(state, rolls), "a seed for %s" % str(rolls))
	return _ok(BeginActionCommand.new(state.get_model(id).player, id, &"charge", target, allow_rolls))


## Answers a contact choice with first contact, if one is asked.
func _first_contact() -> Array[GameEvent]:
	if state.pending != null and state.pending.kind == PendingDecision.Kind.CHARGE_CONTACT:
		return _ok(ChooseContactCommand.new(state.pending.player, state.pending.default_index))
	return []


# --- A sheer climb on the route -----------------------------------------------


## A sheer 3" block x 22..26, z 24..28; the target on top, the charger south.
func _sheer_block() -> Array[int]:
	_piece(Vector2(24, 26), Vector3(4, 3, 4), TerrainPiece.Tag.SHEER)
	var a: int = _place(0, Vector3(24, 0, 20))
	var target: int = _place(1, Vector3(24, 3, 26), 25)
	return [a, target]


func test_a_route_with_a_sheer_climb_lists_its_roll() -> void:
	var ids: Array[int] = _sheer_block()
	var both: Array[ChargePlan] = ChargePlanner.new(state, ids[0]).plans(ids[1])
	assert_false(both[0].contact, "off: no roll-free way to contact")
	assert_true(both[1].contact, "on: up the sheer face")
	assert_eq(both[1].risky_rolls(), 1)
	assert_eq(both[1].rolls[0]["kind"], &"climb")
	assert_almost_eq(both[1].end().y, 3.0, 0.001)
	# 3.37 to the wall, 0.63 + 3 up, 0.88 on top.
	assert_almost_eq(both[1].length, 4.0 - R32 + R32 + 3.0 + (2.0 - R25 - R32 + 0.0), 0.15)
	assert_eq(both[1].needed, 2)
	assert_eq(both[1].label(), "needs 2+, 1 risky roll")


func test_a_successful_climb_on_a_charge_goes_on_to_contact() -> void:
	var ids: Array[int] = _sheer_block()
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(6), SUCCESS])
	assert_not_null(_find(events, E.MOVE_ROLL_POINT), "the climb is rolled when the model gets there")
	var climb: GameEvent = null
	for event: GameEvent in events:
		if event.kind == E.ROLL_RESOLVED and event.result.request.kind == RollRequest.Kind.SUCCESS:
			climb = event
	assert_not_null(climb)
	assert_true(climb.result.risky, "a risky success roll, as in a Move")
	events.append_array(_first_contact())
	var model: ModelState = state.get_model(ids[0])
	assert_almost_eq(model.position.y, 3.0, 0.001, "on top")
	assert_true(MeleeZone.in_base_contact(model.position, R32, model.height_inches(), state.get_model(ids[1])))
	assert_not_null(_find(events, E.CHARGED))
	assert_eq(state.turn.charged, [ids[1]] as Array[int])
	assert_eq(state.turn.active_model_id, ids[0], "the activation carries on")


func test_a_failed_climb_on_a_charge_is_the_move_result_and_the_charge_fails() -> void:
	var ids: Array[int] = _sheer_block()
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(6), FAILURE])
	var model: ModelState = state.get_model(ids[0])
	assert_almost_eq(model.position.y, 0.0, 0.001, "stays at the foot")
	assert_almost_eq(model.position.z, 24.0 - R32, 0.01)
	assert_not_null(_find(events, E.MOVE_STOPPED))
	assert_not_null(_find(events, E.CHARGE_FAILED))
	assert_null(_find(events, E.CHARGED))
	assert_eq(String(_find(events, E.ACTIVATION_ENDED).data["reason"]), "failed risky roll")
	assert_true(GameEvent.kinds(events).find(E.CHARGE_FAILED) < GameEvent.kinds(events).find(E.ACTIVATION_ENDED))
	assert_null(state.resolution)
	assert_eq(state.turn.charged, [] as Array[int])


# --- A gap jump on the route --------------------------------------------------


## Two 3" platforms x 8..12 and 13.5..17.5 (z 8..12), a 1.5" gap; the charger
## on the first, the target on the second.
func _gap() -> Array[int]:
	_piece(Vector2(10, 10), Vector3(4, 3, 4))
	_piece(Vector2(15.5, 10), Vector3(4, 3, 4))
	var a: int = _place(0, Vector3(10, 3, 10))
	var target: int = _place(1, Vector3(16.5, 3, 10))
	return [a, target]


func test_a_successful_jump_on_a_charge_goes_on_to_contact() -> void:
	var ids: Array[int] = _gap()
	var plan: ChargePlan = ChargePlanner.new(state, ids[0]).plan(ids[1], true)
	assert_eq(plan.rolls.size(), 1)
	assert_eq(plan.rolls[0]["kind"], &"jump")
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(3), SUCCESS])
	events.append_array(_first_contact())
	var model: ModelState = state.get_model(ids[0])
	assert_almost_eq(model.position.y, 3.0, 0.001, "on the far platform")
	assert_true(model.position.x > 13.5, "across the gap")
	assert_not_null(_find(events, E.CHARGED))


func test_a_failed_jump_on_a_charge_falls_and_the_charge_fails() -> void:
	var ids: Array[int] = _gap()
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(3), FAILURE, INJURY_PLUS1_BLOOD])
	var fell: GameEvent = _find(events, E.MODEL_FELL)
	assert_not_null(fell, "into the gap, as in a Move")
	assert_almost_eq(state.get_model(ids[0]).position.y, 0.0, 0.001)
	assert_eq(state.get_model(ids[0]).marker_count(Markers.BLOOD), 1, "the fall's injury roll")
	assert_not_null(_find(events, E.CHARGE_FAILED))
	assert_eq(String(_find(events, E.ACTIVATION_ENDED).data["reason"]), "failed risky roll")


# --- A drop of 3" on the route ------------------------------------------------


## A 3" platform x 8..12; the charger on it, the target on the ground east.
func _drop() -> Array[int]:
	_piece(Vector2(10, 10), Vector3(4, 3, 4))
	var a: int = _place(0, Vector3(10, 3, 10))
	var target: int = _place(1, Vector3(15, 0, 10))
	return [a, target]


func test_a_drop_on_a_charge_takes_its_injury_roll_and_goes_on_standing() -> void:
	var ids: Array[int] = _drop()
	var plan: ChargePlan = ChargePlanner.new(state, ids[0]).plan(ids[1], true)
	assert_eq(plan.injury_rolls(), 1, "the drop's injury roll")
	assert_string_contains(plan.label(), "1 injury roll")
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(1), INJURY_PLUS1_BLOOD])
	events.append_array(_first_contact())
	var model: ModelState = state.get_model(ids[0])
	assert_false(model.down)
	assert_eq(model.marker_count(Markers.BLOOD), 1)
	assert_almost_eq(model.position.y, 0.0, 0.001)
	assert_not_null(_find(events, E.CHARGED))
	assert_true(MeleeZone.in_melee(state, model))


func test_a_drop_that_puts_the_charger_down_fails_the_charge() -> void:
	var ids: Array[int] = _drop()
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(1), INJURY_PLUS1_DOWN])
	var model: ModelState = state.get_model(ids[0])
	assert_true(model.down)
	assert_almost_eq(model.position.x, 12.0 + R32, 0.01, "Down where it landed")
	assert_not_null(_find(events, E.CHARGE_FAILED))
	assert_eq(String(_find(events, E.ACTIVATION_ENDED).data["reason"]), "went Down")


# --- The route toggle ---------------------------------------------------------


## The sheer block of _sheer_block() with an untagged 3" block east of it
## (x 26..30): the long way round is an open climb.
func test_the_toggle_picks_the_roll_free_or_the_shorter_risky_route() -> void:
	var ids: Array[int] = _sheer_block()
	_piece(Vector2(28, 26), Vector3(4, 3, 4))
	var both: Array[ChargePlan] = ChargePlanner.new(state, ids[0]).plans(ids[1])
	var safe: ChargePlan = both[0]
	var risky: ChargePlan = both[1]
	assert_true(safe.contact and risky.contact)
	assert_eq(safe.rolls.size(), 0, "off: the roll-free route")
	assert_eq(risky.risky_rolls(), 1, "on: the sheer climb")
	assert_true(safe.length > risky.length + 1.0, "the way round is longer (%.2f against %.2f)" % [safe.length, risky.length])
	assert_true(safe.needed > risky.needed, "and needs more on the D6 (%d against %d)" % [safe.needed, risky.needed])
	assert_eq(safe.label(), "needs %d+" % safe.needed)
	# Declared with the toggle off, the charge takes the long way and rolls nothing but the D6.
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(6)], false)
	assert_eq(_count(events, E.ROLL_RESOLVED), 1, "only the D6")
	assert_true(bool(_find(events, E.CHARGE_DECLARED).data["allow_rolls"]) == false)
	_first_contact()
	assert_true(MeleeZone.in_melee(state, state.get_model(ids[0])))


# --- Hopeless charges ---------------------------------------------------------


func test_a_hopeless_charge_moves_along_its_route_and_stops_outside_every_zone() -> void:
	var a: int = _place(0, Vector3(24, 0, 24))
	var far: int = _place(1, Vector3(12, 0, 24))
	state.get_model(a).down = true
	var plan: ChargePlan = ChargePlanner.new(state, a).plan(far)
	assert_eq(plan.label(), "cannot reach")
	assert_true(plan.contact, "the route still runs to base contact")
	assert_almost_eq(plan.length, 12 - 2 * R32, 0.02)
	var events: Array[GameEvent] = _charge(a, far, [_d6(1)])
	var model: ModelState = state.get_model(a)
	assert_almost_eq(model.position.x, 24.0 - 3.5, 0.06, "(6 + 1) / 2 along the route")
	assert_not_null(_find(events, E.CHARGE_FAILED))
	assert_false(MeleeZone.in_melee(state, model))
	assert_eq(state.turn.active_model_id, a, "falling short does not end the activation")


func test_a_charge_short_of_distance_does_not_start_a_climb_it_cannot_finish() -> void:
	_piece(Vector2(24, 26), Vector3(4, 3, 4), TerrainPiece.Tag.SHEER)
	var a: int = _place(0, Vector3(24, 0, 19))
	var target: int = _place(1, Vector3(24, 3, 26), 25)
	# A 1: 7". 4.37" to the wall, and the climb would end at 8".
	var events: Array[GameEvent] = _charge(a, target, [_d6(1), SUCCESS])
	assert_eq(_count(events, E.MOVE_ROLL_POINT), 0, "the climb is not started")
	var model: ModelState = state.get_model(a)
	assert_almost_eq(model.position.y, 0.0, 0.001)
	assert_almost_eq(model.position.z, 24.0 - R32, 0.06, "at the foot of the wall")
	assert_not_null(_find(events, E.CHARGE_FAILED))
	assert_eq(state.turn.active_model_id, a)


# --- The pillar case ----------------------------------------------------------


## A 1" square pillar of `height` at (20, 20) with a 25 mm target on it.
func _pillar(height: float) -> Array[int]:
	_piece(Vector2(20, 20), Vector3(1, height, 1))
	var a: int = _place(0, Vector3(20, 0, 14))
	var target: int = _place(1, Vector3(20, height, 20), 25)
	return [a, target]


func test_the_pillar_case_ends_at_the_closest_place_and_is_in_melee_within_an_inch() -> void:
	var ids: Array[int] = _pillar(2.5)
	var plan: ChargePlan = ChargePlanner.new(state, ids[0]).plan(ids[1])
	assert_eq(plan.error, "")
	assert_false(plan.contact, "no position in base contact exists")
	assert_true(plan.ends_in_melee, "0.6\" below the target's feet")
	var end_gap: float = MeleeZone.cylinder_gap(plan.end(), R32, 1.9, Vector3(20, 2.5, 20), R25, 1.7)
	assert_almost_eq(end_gap, 0.6, 0.05, "the closest place: touching the pillar")
	assert_string_contains(plan.label(), "no base contact (in melee)")
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(6)])
	var charged: GameEvent = _find(events, E.CHARGED)
	assert_not_null(charged)
	assert_eq(charged.data["charged"], [ids[1]] as Array[int], "the target counts as charged")
	assert_true(MeleeZone.in_melee(state, state.get_model(ids[0])))


func test_the_pillar_case_too_high_for_melee_fails() -> void:
	var ids: Array[int] = _pillar(4.0)
	var plan: ChargePlan = ChargePlanner.new(state, ids[0]).plan(ids[1])
	assert_false(plan.contact)
	assert_false(plan.ends_in_melee)
	var events: Array[GameEvent] = _charge(ids[0], ids[1], [_d6(6)])
	assert_not_null(_find(events, E.CHARGE_FAILED))
	assert_null(_find(events, E.CHARGED))
	assert_almost_eq(MeleeZone.gap(state.get_model(ids[0]), state.get_model(ids[1])), 2.1, 0.05, "as close as it gets")


# --- Contact across heights ---------------------------------------------------


## An untagged 2" step x 20..24, z 20..24.
func _step() -> void:
	_piece(Vector2(22, 22), Vector3(4, 2, 4))


func test_contact_from_a_two_inch_step_with_a_taller_target() -> void:
	_step()
	var a: int = _place(0, Vector3(21, 2, 22), 40)
	var target: int = _place(1, Vector3(24 + R40 + 0.1, 0, 22), 40)
	var plan: ChargePlan = ChargePlanner.new(state, a).plan(target)
	assert_true(plan.contact)
	assert_almost_eq(plan.end().y, 2.0, 0.001, "from the step: 2\" up, the 2.2\" target overlaps")
	assert_true(MeleeZone.in_base_contact(plan.end(), R40, 2.2, state.get_model(target)))
	_charge(a, target, [_d6(1)])
	_first_contact()
	assert_almost_eq(state.get_model(a).position.y, 2.0, 0.001)
	assert_true(MeleeZone.in_melee(state, state.get_model(a)))


func test_contact_refused_when_the_cylinders_do_not_overlap_in_height() -> void:
	_step()
	var a: int = _place(0, Vector3(21, 2, 22), 40)
	var target: int = _place(1, Vector3(24 + R32 + 0.1, 0, 22))
	var model: ModelState = state.get_model(target)
	var from_step: Vector3 = Vector3(24 + 0.1 - R40, 2, 22)
	assert_false(MeleeZone.in_base_contact(from_step, R40, 2.2, model), "feet at 2\", the 1.9\" target's top below")
	assert_true(MeleeZone.in_base_contact(Vector3(from_step.x, 0.5, from_step.z), R40, 2.2, model))
	var plan: ChargePlan = ChargePlanner.new(state, a).plan(target)
	assert_true(plan.contact)
	assert_almost_eq(plan.end().y, 0.0, 0.001, "down to the ground for contact")


func test_sliding_may_change_level_while_keeping_contact() -> void:
	_step()
	# A tall target on the ground at the step's east face; the charger east of it.
	var target: int = _place(1, Vector3(24 + R40 + 0.1, 0, 22), 40)
	var a: int = _place(0, Vector3(29, 0, 22), 40)
	_charge(a, target, [_d6(6)])
	var decision: PendingDecision = state.pending
	assert_eq(decision.kind, PendingDecision.Kind.CHARGE_CONTACT)
	var on_step: int = -1
	for i: int in decision.positions.size():
		var p: Vector3 = decision.positions[i]
		assert_true(MeleeZone.in_base_contact(p, R40, 2.2, state.get_model(target)), "every offer is in contact (%s)" % str(p))
		if p.y > 1.9 and on_step == -1:
			on_step = i
	assert_ne(on_step, -1, "it can slide up onto the step")
	var events: Array[GameEvent] = _ok(ChooseContactCommand.new(0, on_step))
	var model: ModelState = state.get_model(a)
	assert_almost_eq(model.position.y, 2.0, 0.001)
	var moved: GameEvent = _find(events, E.MODEL_MOVED)
	assert_true(moved.data.get("slide", false))
	assert_true((moved.data["kinds"] as Array).has(K.OPEN_CLIMB), "up the step on the way, no roll")
	assert_eq(_count(events, E.ROLL_RESOLVED), 0)
	assert_not_null(_find(events, E.CHARGED))


# --- Undo, redo and replay ----------------------------------------------------


func test_undo_redo_and_replay_across_a_roll_on_the_route() -> void:
	var ids: Array[int] = _sheer_block()
	# A blessing marker: the climb waits for the owner's prompt.
	_ok(SetMarkersOverride.new(ids[0], Markers.BLESSING, 1))
	TurnHelper.ready_to_act(state, ids[0])
	var start: Vector3 = state.get_model(ids[0]).position
	var size: int = state.history.size()
	_ok(BeginActionCommand.new(0, ids[0], &"charge", ids[1], true))
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE, "the climb's marker prompt")
	assert_true(state.resolution is StagedMove)
	assert_true((state.resolution as StagedMove).parent is ChargeResolution, "the charge waits under the move")
	var at_wall: Vector3 = state.get_model(ids[0]).position
	_ok(RollChoiceCommand.new(0, 1))
	_first_contact()
	var end: Vector3 = state.get_model(ids[0]).position
	var charged: Array[int] = state.turn.charged.duplicate()
	while state.history.size() > size + 1:
		assert_true(state.undo())
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE, "back at the prompt")
	assert_eq(state.get_model(ids[0]).position, at_wall)
	assert_true(state.undo())
	assert_eq(state.get_model(ids[0]).position, start)
	assert_null(state.resolution)
	while state.redo().error == "":
		pass
	assert_eq(state.get_model(ids[0]).position, end)
	assert_eq(state.turn.charged, charged)
	var replay: GameState = GameState.new(7)
	for command: Command in state.history:
		assert_eq(replay.execute(command), "", command.get_script().get_global_name())
	assert_eq(replay.get_model(ids[0]).position, end)
	assert_eq(replay.turn.charged, charged)
