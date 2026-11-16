extends GutTest
## The melee zone (ruling 9 of brief 007): within 1" edge to edge in 3D is in
## melee, exactly 1" is not; height separates; Down models count; actions
## follow it; the existing Move rule against entering a zone stays.

const R32: float = 0.62992126
const H32: float = 1.9

var state: GameState


func before_each() -> void:
	state = GameState.new(5)


func _place(player: int, pos: Vector3, base_mm: int = 32, movement: float = 6.0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, base_mm, movement)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _piece(center: Vector2, size: Vector3) -> void:
	assert_eq(state.execute(PlaceTerrainCommand.new(center, size, 0.0, 0.0, TerrainPiece.Tag.NONE)), "")


func test_cylinder_gap_in_3d() -> void:
	assert_almost_eq(MeleeZone.cylinder_gap(Vector3(0, 0, 0), 1.0, 2.0, Vector3(3, 0, 0), 1.0, 2.0), 1.0, 1e-6)
	assert_almost_eq(MeleeZone.cylinder_gap(Vector3(0, 0, 0), 1.0, 2.0, Vector3(1, 3, 0), 1.0, 2.0), 1.0, 1e-6, "straight above")
	assert_almost_eq(MeleeZone.cylinder_gap(Vector3(0, 0, 0), 1.0, 2.0, Vector3(5, 6, 0), 1.0, 2.0), 5.0, 1e-6, "3-4-5 corner")
	assert_eq(MeleeZone.cylinder_gap(Vector3(0, 0, 0), 1.0, 2.0, Vector3(1.5, 0, 0), 1.0, 2.0), 0.0, "overlapping")


func test_in_and_out_at_exactly_one_inch() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	var b: int = _place(1, Vector3(10 + 2 * R32 + 1.0, 0, 10))
	var c: int = _place(1, Vector3(10, 0, 10 + 2 * R32 + 0.99))
	var model: ModelState = state.get_model(a)
	assert_eq(MeleeZone.enemy_ids_within(state, model), [c] as Array[int], "0.99\" is within, exactly 1\" is not")
	assert_false(MeleeZone.in_melee(state, state.get_model(b)), "b is exactly 1\" away")
	assert_true(MeleeZone.in_melee(state, state.get_model(c)))
	assert_true(MeleeZone.in_melee(state, model))


func test_friends_do_not_count() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	_place(0, Vector3(10 + 2 * R32, 0, 10))
	assert_false(MeleeZone.in_melee(state, state.get_model(a)))


func test_height_separates() -> void:
	# A deck 3" up: an enemy on it, straight above the model's base edge.
	_piece(Vector2(20, 10), Vector3(4, 3, 4))
	var high: int = _place(1, Vector3(20, 3, 10))
	var low: int = _place(0, Vector3(20 - 2 * R32 - 1.5, 0, 10))
	# The cylinders: low top at 1.9, high bottom at 3: 1.1" apart vertically, 1.5" across.
	assert_false(MeleeZone.in_melee(state, state.get_model(low)), "1.1\" below and 1.5\" across is not within 1\"")
	assert_almost_eq(MeleeZone.gap(state.get_model(low), state.get_model(high)), sqrt(1.1 * 1.1 + 1.5 * 1.5), 1e-4)
	var under: Vector3 = Vector3(20, 3 - H32 - 0.9, 10)
	assert_true(MeleeZone.is_within(MeleeZone.gap(state.get_model(low), state.get_model(high), under)), "0.9\" under the enemy's base")
	var below: Vector3 = Vector3(20, 3 - H32 - 1.2, 10)
	assert_false(MeleeZone.is_within(MeleeZone.gap(state.get_model(low), state.get_model(high), below)), "1.2\" under it")


func test_down_models_count() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	var b: int = _place(1, Vector3(10 + 2 * R32 + 0.5, 0, 10))
	state.get_model(b).down = true
	assert_true(MeleeZone.in_melee(state, state.get_model(a)), "a Down enemy still counts")
	state.get_model(a).down = true
	assert_true(MeleeZone.in_melee(state, state.get_model(b)), "and so does a Down model itself")


func test_out_of_action_models_do_not_count() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	var b: int = _place(1, Vector3(10 + 2 * R32 + 0.5, 0, 10))
	state.get_model(b).out_of_action = true
	assert_false(MeleeZone.in_melee(state, state.get_model(a)))


func test_action_availability_in_melee() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	var free: int = _place(0, Vector3(30, 0, 30))
	_place(1, Vector3(10 + 2 * R32 + 0.5, 0, 10))
	_place(1, Vector3(40, 0, 40))
	TurnHelper.ready_to_act(state, a)
	var model: ModelState = state.get_model(a)
	for action: StringName in [&"move", &"dash", &"charge"]:
		assert_string_contains(BeginActionCommand.unavailable_reason(state, model, action), "In melee", String(action))
	assert_ne(state.execute(BeginActionCommand.new(0, a, &"move")), "", "Move is refused")
	assert_ne(state.execute(BeginActionCommand.new(0, a, &"dash")), "", "Dash is refused")
	var other: ModelState = state.get_model(free)
	assert_eq(BeginActionCommand.unavailable_reason(state, other, &"move"), "")


func test_move_still_may_not_enter_a_zone() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	_place(1, Vector3(16, 0, 10))
	var command: MoveCommand = TurnHelper.move(state, a, [Vector3(16 - 2 * R32 - 0.5, 0, 10)] as Array[Vector3])
	assert_eq(command.validate(state), MoveLegality.describe(MoveLegality.Result.ENEMY))
	command = MoveCommand.new(0, a, [Vector3(16 - 2 * R32 - 1.0, 0, 10)] as Array[Vector3])
	assert_eq(command.validate(state), "", "exactly 1\" is allowed")


func test_enemy_zones_open_and_retreat() -> void:
	var a: int = _place(0, Vector3(10, 0, 10))
	var b: int = _place(1, Vector3(10 + 2 * R32 + 0.5, 0, 10))
	var c: int = _place(1, Vector3(14, 0, 14))
	var model: ModelState = state.get_model(a)
	var normal: MoveLegality = MoveLegality.new(state, model)
	assert_eq(normal.passing_result(Vector2(10, 10), 0), MoveLegality.Result.ENEMY, "the normal rule holds it")
	var retreat: MoveLegality = MoveLegality.new(state, model, null, EnemyZones.retreat([b]))
	assert_eq(retreat.passing_result(Vector2(10, 10), 0), MoveLegality.Result.OK, "b's zone is open to pass")
	assert_eq(retreat.point_result(Vector2(10, 10), 0), MoveLegality.Result.ENEMY, "but a retreat may not end in it")
	assert_eq(retreat.point_result(Vector2(10, 7), 0), MoveLegality.Result.OK)
	assert_eq(retreat.passing_result(Vector2(14 - 2 * R32 - 0.5, 14), 0), MoveLegality.Result.ENEMY, "c's zone stays shut")
	assert_eq(retreat.passing_result(Vector2(b_x() - 0.3, 10), 0), MoveLegality.Result.ENEMY, "b's base still blocks")
	var charge: MoveLegality = MoveLegality.new(state, model, null, EnemyZones.charge())
	assert_eq(charge.point_result(Vector2(14 - 2 * R32, 14), 0), MoveLegality.Result.OK, "a charge may end touching")
	assert_eq(charge.point_result(Vector2(14 - 2 * R32 + 0.05, 14), 0), MoveLegality.Result.ENEMY, "never overlapping")
	assert_eq(state.get_model(c).id, c)


func b_x() -> float:
	return 10 + 2 * R32 + 0.5
