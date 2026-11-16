extends GutTest
## Paths with rolls in them (brief 006): sheer climbs up and down, gap jumps
## and their limit (ruling 5), drops, and where a falling model lands.

const R32: float = 0.62992126
const K = Transitions.Kind

var state: GameState


func before_each() -> void:
	state = GameState.new(1)


func _piece(center: Vector2, size: Vector3, tag: TerrainPiece.Tag = TerrainPiece.Tag.NONE, base: float = 0.0) -> int:
	var command: PlaceTerrainCommand = PlaceTerrainCommand.new(center, size, 0.0, base, tag)
	assert_eq(state.execute(command), "")
	return command.placed_terrain_id


func _place(pos: Vector3, movement: float = 6.0, player: int = 0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, 32, movement)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _path(
	id: int, points: Array[Vector3], mode: Transitions.DescentMode = Transitions.DescentMode.DROP
) -> MovePath:
	TurnHelper.grant_move(state, id)
	return MovePath.new(state, id, points, state.pending.budget, mode)


func _kinds(path: MovePath) -> Array[StringName]:
	var result: Array[StringName] = []
	for roll: Dictionary in path.rolls():
		result.append(roll["kind"])
	return result


## Two 4" platforms, x 8..12 and x (12 + gap)..(16 + gap), z 8..12; the
## model stands on the west one.
func _platforms(gap: float, far_height: float = 4.0, movement: float = 6.0) -> int:
	_piece(Vector2(10, 10), Vector3(4, 4, 4))
	_piece(Vector2(14 + gap, 10), Vector3(4, far_height, 4))
	return _place(Vector3(11, 4, 10), movement)


func _jump(gap: float, far_height: float = 4.0) -> Array[Vector3]:
	return [Vector3(12, 4, 10), Vector3(12 + gap, far_height, 10), Vector3(13 + gap, far_height, 10)]


func test_sheer_climb_needs_the_movement_to_clear_the_wall() -> void:
	_piece(Vector2(12, 12), Vector3(4, 4, 4))
	var id: int = _place(Vector3(12, 0, 16))
	var climb: Array[Vector3] = [Vector3(12, 0, 14 + R32), Vector3(12, 4, 14), Vector3(12, 4, 13)]
	var short: MovePath = _path(id, climb)
	assert_false(short.is_legal(), "2 + 4 + 1 is more than 6")
	assert_eq(short.rejection, MovePath.Rejection.TOO_FAR)
	var just: Array[Vector3] = [Vector3(12, 0, 14 + R32), Vector3(12, 4, 14)]
	assert_true(_path(id, just).is_legal(), "2 + 4: just enough to stop on the edge")
	state = GameState.new(1)
	_piece(Vector2(12, 12), Vector3(4, 4, 4))
	id = _place(Vector3(12, 0, 16), 7.0)
	var path: MovePath = _path(id, climb)
	assert_true(path.is_legal(), path.error)
	assert_almost_eq(path.cost, 2.0 + 4.0 + 1.0, 0.0001, "the height is paid")
	assert_eq(_kinds(path), [&"climb"] as Array[StringName])
	assert_eq(path.segments[1].kind, K.SHEER_CLIMB_UP)
	assert_eq(path.rolls()[0]["at"], Vector3(12, 0, 14 + R32), "rolled at the wall")
	assert_string_contains(String(path.rolls()[0]["label"]), "Climb 4.0 (risky)")


func test_a_wall_tagged_sheer_needs_the_roll_at_any_height() -> void:
	_piece(Vector2(12, 12), Vector3(4, 1.5, 4), TerrainPiece.Tag.SHEER)
	var id: int = _place(Vector3(12, 0, 16))
	var path: MovePath = _path(id, [Vector3(12, 0, 14 + R32), Vector3(12, 1.5, 14), Vector3(12, 1.5, 13)])
	assert_true(path.is_legal(), path.error)
	assert_eq(_kinds(path), [&"climb"] as Array[StringName])


func test_climbing_down_a_sheer_surface_in_climb_down_mode() -> void:
	_piece(Vector2(12, 12), Vector3(4, 4, 4))
	var id: int = _place(Vector3(12, 4, 13), 8.0)
	var down: Array[Vector3] = [Vector3(12, 4, 14), Vector3(12, 0, 14 + R32), Vector3(12, 0, 16)]
	var drop: MovePath = _path(id, down)
	assert_eq(_kinds(drop), [&"injury"] as Array[StringName], "by default the free drop")
	assert_eq(drop.segments[1].kind, K.DROP)
	assert_almost_eq(drop.cost, 1.0 + 2.0, 0.0001, "a drop costs nothing extra")
	var climb: MovePath = _path(id, down, Transitions.DescentMode.CLIMB_DOWN)
	assert_true(climb.is_legal(), climb.error)
	assert_eq(_kinds(climb), [&"climb"] as Array[StringName])
	assert_eq(climb.segments[1].kind, K.SHEER_CLIMB_DOWN)
	assert_string_contains(String(climb.rolls()[0]["label"]), "Climb down 4.0 (risky)")
	assert_string_contains(String(drop.rolls()[0]["label"]), "Drop 4.0 (injury +1)")
	assert_eq(climb.rolls()[0]["at"], Vector3(12, 4, 14), "rolled at the top")
	assert_almost_eq(climb.cost, 1.0 + 4.0 + 2.0, 0.0001, "climbing down pays the height")


func test_a_ladder_is_always_taken_down_without_a_roll() -> void:
	_piece(Vector2(12, 12), Vector3(4, 4, 4), TerrainPiece.Tag.LADDER)
	var id: int = _place(Vector3(12, 4, 13), 8.0)
	var path: MovePath = _path(id, [Vector3(12, 4, 14), Vector3(12, 0, 14 + R32), Vector3(12, 0, 16)])
	assert_eq(path.segments[1].kind, K.LADDER_DOWN, "the safe way, though dearer")
	assert_false(path.has_rolls())


func test_jumping_a_gap_within_the_limit() -> void:
	var id: int = _platforms(2.5)
	var path: MovePath = _path(id, _jump(2.5))
	assert_true(path.is_legal(), path.error)
	assert_eq(path.segments[1].kind, K.GAP_JUMP)
	assert_almost_eq(path.cost, 1.0 + 2.5 + 1.0, 0.0001)
	assert_eq(_kinds(path), [&"jump"] as Array[StringName])
	assert_eq(path.rolls()[0]["at"], Vector3(12, 4, 10), "rolled at the ledge")
	assert_almost_eq(path.segments[1].fall_point.x, 13.25, 0.0001, "a failed jump falls from mid-gap")


func test_the_jump_limit_is_half_the_movement() -> void:
	var id: int = _platforms(3.0)
	assert_true(_path(id, _jump(3.0)).is_legal(), "exactly half of 6")
	state = GameState.new(1)
	id = _platforms(3.2)
	var path: MovePath = _path(id, _jump(3.2))
	assert_false(path.is_legal())
	assert_eq(path.rejection, MovePath.Rejection.TOO_WIDE)
	state = GameState.new(1)
	id = _platforms(3.2, 4.0, 8.0)
	assert_true(_path(id, _jump(3.2)).is_legal(), "a model with Movement 8 jumps 4\"")


func test_the_jump_limit_is_halved_again_after_standing_up() -> void:
	var id: int = _platforms(2.0)
	state.get_model(id).down = true
	var path: MovePath = _path(id, [Vector3(12, 4, 10), Vector3(14, 4, 10)])
	assert_true(state.turn.stood_up)
	assert_false(path.is_legal(), "half of the halved 3\" is 1.5\"")
	assert_eq(path.rejection, MovePath.Rejection.TOO_WIDE)
	state = GameState.new(1)
	id = _platforms(1.5)
	state.get_model(id).down = true
	assert_true(_path(id, [Vector3(12, 4, 10), Vector3(13.5, 4, 10)]).is_legal(), "1.5\" is within it")


func test_a_higher_far_side_adds_its_rise_to_the_width() -> void:
	var id: int = _platforms(2.5, 5.0)
	var path: MovePath = _path(id, _jump(2.5, 5.0))
	assert_false(path.is_legal(), "2.5 + 1 is more than 3")
	assert_eq(path.rejection, MovePath.Rejection.TOO_WIDE)
	state = GameState.new(1)
	id = _platforms(1.8, 5.0)
	path = _path(id, _jump(1.8, 5.0))
	assert_true(path.is_legal(), path.error)
	assert_almost_eq(path.cost, 1.0 + 1.8 + 1.0 + 1.0, 0.0001, "the rise is paid as width")
	assert_eq(_kinds(path), [&"jump"] as Array[StringName])
	assert_string_contains(String(path.rolls()[0]["label"]), "Jump 2.8")


func test_a_far_side_lower_by_three_inches_or_more_is_also_a_fall() -> void:
	var id: int = _platforms(2.5, 1.0)
	var path: MovePath = _path(id, _jump(2.5, 1.0))
	assert_true(path.is_legal(), path.error)
	assert_eq(_kinds(path), [&"jump", &"injury"] as Array[StringName])
	assert_almost_eq(float(path.rolls()[1]["fall_inches"]), 3.0, 0.0001)
	assert_almost_eq(path.surcharge, 1.0, 0.0001, "the far side is a low obstacle")
	assert_almost_eq(path.cost, 1.0 + 2.5 + 1.0 + 1.0, 0.0001, "coming down costs nothing")
	state = GameState.new(1)
	id = _platforms(2.5, 1.5)
	assert_eq(_kinds(_path(id, _jump(2.5, 1.5))), [&"jump"] as Array[StringName], "2.5\" lower: no injury roll")


func test_a_floor_between_the_ledges_is_not_a_gap() -> void:
	_piece(Vector2(10, 10), Vector3(4, 4, 4))
	_piece(Vector2(16.5, 10), Vector3(4, 4, 4))
	_piece(Vector2(13.25, 10), Vector3(2.5, 4, 4))
	var id: int = _place(Vector3(11, 4, 10))
	var path: MovePath = _path(id, _jump(2.5))
	assert_true(path.is_legal(), path.error)
	assert_eq(path.segments[1].kind, K.WALK, "a floor at the ledges' level is walked")
	assert_false(path.has_rolls())


func test_terrain_rising_into_the_jump_blocks_it() -> void:
	_piece(Vector2(10, 10), Vector3(4, 4, 4))
	_piece(Vector2(16.5, 10), Vector3(4, 4, 4))
	_piece(Vector2(13.25, 10), Vector3(0.5, 6, 4), TerrainPiece.Tag.IMPASSABLE)
	var id: int = _place(Vector3(11, 4, 10))
	assert_false(_path(id, _jump(2.5)).is_legal())


func test_the_whole_width_of_the_base_must_clear_terrain() -> void:
	# A pillar beside the line of the jump: the centre clears it, the base does not.
	_piece(Vector2(10, 10), Vector3(4, 4, 4))
	_piece(Vector2(16.5, 10), Vector3(4, 4, 4))
	_piece(Vector2(13.25, 10.8), Vector3(0.5, 6, 0.5), TerrainPiece.Tag.IMPASSABLE)
	var id: int = _place(Vector3(11, 4, 10))
	var path: MovePath = _path(id, _jump(2.5))
	assert_false(path.is_legal(), "the base clips the pillar")
	assert_eq(path.rejection, MovePath.Rejection.BLOCKED)
	var clear: Array[Vector3] = [Vector3(12, 4, 9.85), Vector3(14.5, 4, 9.85), Vector3(15.5, 4, 9.85)]
	assert_true(_path(id, clear).is_legal(), "a little further from it is fine")
	# The reach field agrees: the far platform is still reached, beside the pillar.
	var field: ReachField = ReachField.new(state, id, state.pending.budget)
	var far: Vector3 = Vector3(15.5, 4, 9.5)
	assert_true(field.is_reachable(far))
	var command: MoveCommand = MoveCommand.new(0, id, field.path_to(far))
	assert_eq(command.validate(state), "")


func test_falling_lands_on_the_first_surface_beneath() -> void:
	_piece(Vector2(10, 10), Vector3(4, 4, 4))
	_piece(Vector2(13, 10), Vector3(2, 1, 4))
	_piece(Vector2(16.5, 10), Vector3(4, 4, 4))
	var id: int = _place(Vector3(11, 4, 10))
	var legality: MoveLegality = MoveLegality.new(state, state.get_model(id))
	var below: int = legality.surface_below(Vector2(13, 10), 4.0)
	assert_eq(legality.field.surface_piece_id(below), 2, "the low block in the gap, not the table")
	assert_eq(legality.surface_below(Vector2(30, 30), 4.0), HeightField.TABLE)
	assert_eq(legality.surface_below(Vector2(30, 30), 0.0), -1, "nothing beneath the table")


func test_the_closest_place_to_stop_after_a_fall() -> void:
	# A 1" gap is too narrow for a 32 mm base: it is moved out along the gap.
	_piece(Vector2(10, 10), Vector3(4, 4, 4))
	_piece(Vector2(15, 10), Vector3(4, 4, 4))
	var id: int = _place(Vector3(11, 4, 10))
	var legality: MoveLegality = MoveLegality.new(state, state.get_model(id))
	var open: Variant = legality.closest_stop(Vector2(30, 30), HeightField.TABLE)
	assert_eq(open, Vector3(30, 0, 30), "a free spot is kept")
	var landed: Variant = legality.closest_stop(Vector2(12.5, 10), HeightField.TABLE)
	assert_not_null(landed)
	var at: Vector3 = landed
	assert_eq(legality.point_result(Vector2(at.x, at.z), HeightField.TABLE), MoveLegality.Result.OK)
	var moved: float = Vector2(at.x, at.z).distance_to(Vector2(12.5, 10))
	# Out of the end of the gap: clear of both corners at z = 12 + sqrt(R^2 - 0.5^2).
	var exact: float = 2.0 + sqrt(R32 * R32 - 0.25)
	assert_between(moved, exact - 0.001, exact + 2.0 * MoveLegality.STOP_RING_STEP)
