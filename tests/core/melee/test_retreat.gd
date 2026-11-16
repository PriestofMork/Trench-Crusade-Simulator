extends GutTest
## Retreat (ruling 10 of brief 007): only in melee; one free attack per enemy
## within 1" through the hook, in an order the enemy player picks when there
## are several; then a normal move that must end outside every zone and may
## not enter a new enemy's.

const R32: float = 0.62992126
const E = GameEvent.Kind


## Records the attacks it is asked for; can knock the target Down.
class RecordingHook:
	extends FreeAttackHook
	var calls: Array[Vector2i] = []
	var knock_down: bool = false

	func resolve(state: GameState, attacker_id: int, target_id: int, events: Array[GameEvent], done: Callable) -> void:
		calls.append(Vector2i(attacker_id, target_id))
		if knock_down:
			TurnFlow.knock_down(state, state.get_model(target_id), events)
		done.call(state, events)


var state: GameState
var a: int
var b: int
var c: int


func before_each() -> void:
	state = GameState.new(3)
	a = _place(0, Vector3(10, 0, 10))
	b = _place(1, Vector3(10 + 2 * R32 + 0.5, 0, 10))
	c = _place(1, Vector3(10, 0, 10 + 2 * R32 + 0.5))


func _place(player: int, pos: Vector3) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, 32, 6.0)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


func _of_kind(events: Array[GameEvent], kind: E) -> Array[GameEvent]:
	var found: Array[GameEvent] = []
	for event: GameEvent in events:
		if event.kind == kind:
			found.append(event)
	return found


func _retreat() -> Array[GameEvent]:
	TurnHelper.ready_to_act(state, a)
	return _ok(BeginActionCommand.new(0, a, &"retreat"))


func test_only_in_melee() -> void:
	var free: int = _place(0, Vector3(30, 0, 30))
	TurnHelper.ready_to_act(state, free)
	assert_string_contains(state.execute(BeginActionCommand.new(0, free, &"retreat")), "only for a model in melee")


func test_the_enemy_player_orders_several_free_attacks() -> void:
	var events: Array[GameEvent] = _retreat()
	assert_eq(_of_kind(events, E.RETREAT_STARTED)[0].data["enemies"], [b, c] as Array[int])
	var decision: PendingDecision = state.pending
	assert_eq(decision.kind, PendingDecision.Kind.FREE_ATTACK_ORDER)
	assert_eq(decision.player, 1, "the enemy player decides")
	assert_eq(decision.model_ids, [b, c] as Array[int])
	assert_eq(_of_kind(events, E.FREE_ATTACK).size(), 0, "nothing before the order is known")
	assert_ne(state.execute(ChooseAttackOrderCommand.new(0, [c, b] as Array[int])), "", "not the retreating player's choice")
	assert_ne(state.execute(ChooseAttackOrderCommand.new(1, [c] as Array[int])), "", "every attacker once")
	assert_ne(state.execute(ChooseAttackOrderCommand.new(1, [c, c] as Array[int])), "")
	events = _ok(ChooseAttackOrderCommand.new(1, [c, b] as Array[int]))
	var attacks: Array[GameEvent] = _of_kind(events, E.FREE_ATTACK)
	assert_eq(attacks.size(), 2, "one free attack per enemy within 1\"")
	assert_eq(attacks[0].model_id, c, "in the chosen order")
	assert_eq(attacks[1].model_id, b)
	assert_eq(attacks[0].data["target_id"], a)
	assert_true(attacks[0].data["temporary"])
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE, "then the move")
	assert_almost_eq(state.pending.budget, 6.0, 0.0001, "the normal Move budget")


func test_attacks_go_through_the_hook() -> void:
	var hook: RecordingHook = RecordingHook.new()
	state.rules.free_attack = hook
	_retreat()
	_ok(ChooseAttackOrderCommand.new(1, [b, c] as Array[int]))
	assert_eq(hook.calls, [Vector2i(b, a), Vector2i(c, a)] as Array[Vector2i])


func test_one_enemy_needs_no_order() -> void:
	state.get_model(c).position = Vector3(10, 0, 20)
	var events: Array[GameEvent] = _retreat()
	assert_eq(_of_kind(events, E.FREE_ATTACK).size(), 1)
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE)


func test_down_from_a_free_attack_ends_the_activation() -> void:
	var hook: RecordingHook = RecordingHook.new()
	hook.knock_down = true
	state.rules.free_attack = hook
	_retreat()
	var events: Array[GameEvent] = _ok(ChooseAttackOrderCommand.new(1, [b, c] as Array[int]))
	assert_eq(hook.calls.size(), 2, "the attacks still all happen")
	assert_eq(_of_kind(events, E.ACTIVATION_ENDED).size(), 1, "then the activation ends")
	assert_eq(state.turn.active_model_id, -1)
	assert_null(state.resolution)
	assert_true(state.get_model(a).down)


func test_the_move_must_end_outside_every_zone() -> void:
	_retreat()
	_ok(ChooseAttackOrderCommand.new(1, [b, c] as Array[int]))
	var inside: MoveCommand = MoveCommand.new(0, a, [Vector3(10, 0, 9.0)] as Array[Vector3])
	assert_eq(inside.validate(state), MoveLegality.describe(MoveLegality.Result.ENEMY), "still within 1\" of b")
	var outside: MoveCommand = MoveCommand.new(0, a, [Vector3(10, 0, 6.5)] as Array[Vector3])
	assert_eq(outside.validate(state), "")
	_ok(outside)
	assert_false(MeleeZone.in_melee(state, state.get_model(a)), "out of melee")


func test_a_new_enemys_zone_may_not_be_entered() -> void:
	var d: int = _place(1, Vector3(10, 0, 4))
	_retreat()
	_ok(ChooseAttackOrderCommand.new(1, [b, c] as Array[int]))
	var into: MoveCommand = MoveCommand.new(0, a, [Vector3(10, 0, 5.6)] as Array[Vector3])
	assert_eq(into.validate(state), MoveLegality.describe(MoveLegality.Result.ENEMY), "d's zone")
	var past: MoveCommand = MoveCommand.new(0, a, [Vector3(10.8, 0, 5.6), Vector3(11.4, 0, 6.6)] as Array[Vector3])
	assert_eq(past.validate(state), MoveLegality.describe(MoveLegality.Result.ENEMY), "passing through d's zone")
	var clear: MoveCommand = MoveCommand.new(0, a, [Vector3(5.5, 0, 9)] as Array[Vector3])
	assert_eq(clear.validate(state), "", "away from everyone")
	assert_eq(state.get_model(d).id, d)


func test_the_retreat_field_offers_only_places_outside_the_zones() -> void:
	_retreat()
	_ok(ChooseAttackOrderCommand.new(1, [b, c] as Array[int]))
	var decision: PendingDecision = state.pending
	var field: ReachField = ReachField.new(
		state, a, decision.budget, ReachField.CELL_SIZE, Transitions.DescentMode.DROP, decision.zones
	)
	var reachable: int = 0
	for k: int in range(0, field.state_count(), 7):
		if not field.is_state_reachable(k):
			continue
		reachable += 1
		var p: Vector3 = field.state_position(k)
		for enemy: int in [b, c]:
			assert_false(MeleeZone.is_within(MeleeZone.gap(state.get_model(a), state.get_model(enemy), p)))
		var path: Array[Vector3] = field.path_to(p)
		assert_eq(MoveCommand.new(0, a, path).validate(state), "", "the field's path is legal: %s" % str(p))
	assert_gt(reachable, 50)


func test_undo_through_a_retreat() -> void:
	_retreat()
	var size: int = state.history.size()
	_ok(ChooseAttackOrderCommand.new(1, [c, b] as Array[int]))
	_ok(MoveCommand.new(0, a, [Vector3(10, 0, 6.5)] as Array[Vector3]))
	assert_true(state.undo_to(size))
	assert_eq(state.pending.kind, PendingDecision.Kind.FREE_ATTACK_ORDER)
	assert_true(state.resolution is RetreatResolution)
	assert_true(MeleeZone.in_melee(state, state.get_model(a)))
	assert_eq(state.redo().error, "")
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE)
	assert_not_null(state.pending.zones, "the retreat's zones come back with it")
