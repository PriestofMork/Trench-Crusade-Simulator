extends GutTest
## MoveCommand across heights: costs and the transitions of brief 004.

const R32: float = 0.62992126
const R25: float = 0.49212598
const R40: float = 0.78740157

var state: GameState


func before_each() -> void:
	state = GameState.new(1)


func _piece(
	center: Vector2, size: Vector3, tag: TerrainPiece.Tag = TerrainPiece.Tag.NONE,
	shape: TerrainPiece.Shape = TerrainPiece.Shape.BOX, base: float = 0.0, turn: float = 0.0
) -> int:
	var command: PlaceTerrainCommand = PlaceTerrainCommand.new(center, size, turn, base, tag, shape)
	assert_eq(state.execute(command), "")
	return command.placed_terrain_id


func _place(pos: Vector3, base_mm: int = 32, movement: float = 6.0, player: int = 0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, base_mm, movement)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _cost(id: int, path: Array[Vector3]) -> float:
	var command: MoveCommand = MoveCommand.new(id, path)
	assert_eq(command.validate(state), "", "path %s" % str(path))
	return command.cost


func _rejection(id: int, path: Array[Vector3]) -> MoveCommand.Rejection:
	var command: MoveCommand = MoveCommand.new(id, path)
	assert_ne(command.validate(state), "", "path %s should be rejected" % str(path))
	return command.rejection


## A box from x = 10 to 14 and z = 10 to 14 of the given height; the model
## stands south of it at z = 16 and climbs its south face (z = 14) straight north.
func _climb_path(height: float) -> Array[Vector3]:
	return [Vector3(12, 0, 14 + R32), Vector3(12, height, 14), Vector3(12, height, 13)]


func test_ramp_costs_the_distance_along_the_slope() -> void:
	# Ramp from x = 5 (height 0) to x = 11 (height 2).
	_piece(Vector2(8, 14), Vector3(6, 2, 3), TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	var id: int = _place(Vector3(3, 0, 14))
	var cost: float = _cost(id, [Vector3(5, 0, 14), Vector3(8, 1, 14)])
	assert_almost_eq(cost, 2.0 + sqrt(9.0 + 1.0), 0.0001)
	assert_eq(state.execute(MoveCommand.new(id, [Vector3(5, 0, 14), Vector3(8, 1, 14)])), "")
	assert_almost_eq(state.get_model(id).position.y, 1.0, 0.0001, "stands on the ramp")
	assert_almost_eq(state.get_model(id).movement_left, 6.0 - cost, 0.0001)


func test_a_waypoint_must_be_on_a_floor() -> void:
	_piece(Vector2(8, 14), Vector3(6, 2, 3), TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	var id: int = _place(Vector3(3, 0, 14))
	assert_eq(_rejection(id, [Vector3(5, 0, 14), Vector3(8, 1.5, 14)]), MoveCommand.Rejection.BLOCKED)
	# Straight from the table onto the ramp without changing surface at its foot: not one surface.
	assert_eq(_rejection(id, [Vector3(8, 1, 14)]), MoveCommand.Rejection.BLOCKED)


func test_open_climb_costs_its_height() -> void:
	_piece(Vector2(12, 12), Vector3(4, 2, 4))
	var id: int = _place(Vector3(12, 0, 16))
	# 2 - R32 to the wall, R32 across, 2 up, 1 on top.
	assert_almost_eq(_cost(id, _climb_path(2.0)), (2.0 - R32) + R32 + 2.0 + 1.0, 0.0001)
	assert_eq(state.execute(MoveCommand.new(id, _climb_path(2.0))), "")
	assert_eq(state.get_model(id).position, Vector3(12, 2, 13))


func test_three_inch_boundary_going_up() -> void:
	_piece(Vector2(12, 12), Vector3(4, 3, 4))
	var id: int = _place(Vector3(12, 0, 16), 32, 8.0)
	assert_almost_eq(_cost(id, _climb_path(3.0)), 2.0 + 3.0 + 1.0, 0.0001, "exactly 3\" is an open climb")
	state = GameState.new(1)
	_piece(Vector2(12, 12), Vector3(4, 3.05, 4))
	id = _place(Vector3(12, 0, 16), 32, 8.0)
	assert_eq(_rejection(id, _climb_path(3.05)), MoveCommand.Rejection.NEEDS_ROLL)


func test_sheer_needs_a_roll_ladder_never() -> void:
	_piece(Vector2(12, 12), Vector3(4, 2, 4), TerrainPiece.Tag.SHEER)
	var id: int = _place(Vector3(12, 0, 16))
	assert_eq(_rejection(id, _climb_path(2.0)), MoveCommand.Rejection.NEEDS_ROLL)
	state = GameState.new(1)
	_piece(Vector2(12, 12), Vector3(4, 5, 4), TerrainPiece.Tag.LADDER)
	id = _place(Vector3(12, 0, 16), 32, 10.0)
	assert_almost_eq(_cost(id, _climb_path(5.0)), 2.0 + 5.0 + 1.0, 0.0001)


func test_impassable_cannot_be_climbed() -> void:
	_piece(Vector2(12, 12), Vector3(4, 0.8, 4), TerrainPiece.Tag.IMPASSABLE)
	var id: int = _place(Vector3(12, 0, 16))
	assert_ne(MoveCommand.new(id, _climb_path(0.8)).validate(state), "")


func test_the_climb_arrives_directly_above_the_touch_point() -> void:
	_piece(Vector2(12, 12), Vector3(4, 2, 4))
	var id: int = _place(Vector3(12, 0, 16))
	# Arriving anywhere but straight across from the touch point is not a climb.
	assert_ne(MoveCommand.new(id, [Vector3(12, 0, 14 + R32), Vector3(12.5, 2, 14)]).validate(state), "")
	assert_ne(MoveCommand.new(id, [Vector3(12, 0, 14 + R32), Vector3(12, 2, 13.5)]).validate(state), "")
	assert_ne(MoveCommand.new(id, [Vector3(12, 0, 15), Vector3(12, 2, 14)]).validate(state), "", "not touching yet")


func test_drops_below_three_inches_are_free_and_from_three_need_a_roll() -> void:
	_piece(Vector2(12, 12), Vector3(4, 2.99, 4))
	var id: int = _place(Vector3(12, 2.99, 13))
	var down: Array[Vector3] = [Vector3(12, 2.99, 14), Vector3(12, 0, 14 + R32), Vector3(12, 0, 16)]
	assert_almost_eq(_cost(id, down), 1.0 + R32 + (2.0 - R32), 0.0001, "the drop itself is free")
	state = GameState.new(1)
	_piece(Vector2(12, 12), Vector3(4, 3, 4))
	id = _place(Vector3(12, 3, 13))
	down = [Vector3(12, 3, 14), Vector3(12, 0, 14 + R32), Vector3(12, 0, 16)]
	assert_eq(_rejection(id, down), MoveCommand.Rejection.NEEDS_ROLL)


func test_ladder_down_pays_the_height() -> void:
	_piece(Vector2(12, 12), Vector3(4, 4, 4), TerrainPiece.Tag.LADDER)
	var id: int = _place(Vector3(12, 4, 13), 32, 8.0)
	var down: Array[Vector3] = [Vector3(12, 4, 14), Vector3(12, 0, 14 + R32), Vector3(12, 0, 16)]
	assert_almost_eq(_cost(id, down), 1.0 + R32 + 4.0 + (2.0 - R32), 0.0001)


func test_crossing_sandbags_costs_nothing_extra() -> void:
	# A 0.5" sandbag from z = 9.625 to 10.375.
	_piece(Vector2(10, 10), Vector3(6, 0.5, 0.75))
	var id: int = _place(Vector3(10, 0, 13), 25)
	var path: Array[Vector3] = [
		Vector3(10, 0, 10.375 + R25), Vector3(10, 0.5, 10.375),
		Vector3(10, 0.5, 9.625), Vector3(10, 0, 9.625 - R25), Vector3(10, 0, 7),
	]
	assert_almost_eq(_cost(id, path), 6.0, 0.0001)
	# Walking straight through it on the table is not allowed.
	assert_eq(_rejection(id, [Vector3(10, 0, 7)]), MoveCommand.Rejection.BLOCKED)


func test_stopping_on_the_crate_costs_its_height() -> void:
	# A 1" crate from z = 36.5 to 39.5.
	_piece(Vector2(15, 38), Vector3(3, 1, 3))
	var id: int = _place(Vector3(15, 0, 42), 40)
	var on_top: Array[Vector3] = [Vector3(15, 0, 39.5 + R40), Vector3(15, 1, 39.5), Vector3(15, 1, 38)]
	# 2.5 - R40 to the crate, R40 across, 1.5 on top: 4, plus 1 for stopping there.
	assert_almost_eq(_cost(id, on_top), 4.0 + 1.0, 0.0001)
	assert_eq(state.execute(MoveCommand.new(id, on_top)), "")
	assert_almost_eq(state.get_model(id).movement_left, 1.0, 0.0001)
	# Moving about on top after starting there: no surcharge.
	assert_almost_eq(_cost(id, [Vector3(15, 1, 37.5)]), 0.5, 0.0001)


func test_crossing_the_crate_without_stopping_is_free() -> void:
	_piece(Vector2(15, 38), Vector3(3, 1, 3))
	var id: int = _place(Vector3(15, 0, 42), 40, 8.0)
	var across: Array[Vector3] = [
		Vector3(15, 0, 39.5 + R40), Vector3(15, 1, 39.5), Vector3(15, 1, 36.5),
		Vector3(15, 0, 36.5 - R40), Vector3(15, 0, 35),
	]
	assert_almost_eq(_cost(id, across), 7.0, 0.0001)


func test_enemy_far_below_a_bridge_does_not_hold_a_model_back() -> void:
	_piece(Vector2(20, 20), Vector3(8, 0.5, 3), TerrainPiece.Tag.NONE, TerrainPiece.Shape.BOX, 3.0)
	var walker: int = _place(Vector3(17, 3.5, 20), 32, 6.0)
	# Enemy right under the deck: 3.5 - 1.9 = 1.6" below the walker's base.
	_place(Vector3(20, 0, 20), 32, 6.0, 1)
	assert_eq(state.execute(MoveCommand.new(walker, [Vector3(23, 3.5, 20)])), "")


func test_enemy_on_the_same_level_still_holds_it_back() -> void:
	_piece(Vector2(20, 20), Vector3(8, 0.5, 3), TerrainPiece.Tag.NONE, TerrainPiece.Shape.BOX, 3.0)
	var walker: int = _place(Vector3(17, 3.5, 20), 25, 6.0)
	_place(Vector3(21, 3.5, 21), 25, 6.0, 1)
	var command: MoveCommand = MoveCommand.new(walker, [Vector3(23, 3.5, 20)])
	assert_ne(state.execute(command), "")
	assert_eq(command.rejection, MoveCommand.Rejection.TOO_CLOSE_TO_ENEMY)


func test_enemy_measured_in_three_d_near_the_limit() -> void:
	# A model on a 1.5" crate next to an enemy on the table: the walker's base is
	# 1.5 - 1.9 below the enemy's top, so they overlap vertically: horizontal 1" applies.
	_piece(Vector2(10, 10), Vector3(6, 1.5, 6))
	var walker: int = _place(Vector3(12, 1.5, 10), 32)
	_place(Vector3(13.5, 0, 13 + R32 + 0.01), 32, 6.0, 1)
	var close: MoveCommand = MoveCommand.new(walker, [Vector3(12, 1.5, 12.9)])
	assert_ne(state.execute(close), "")
	assert_eq(close.rejection, MoveCommand.Rejection.TOO_CLOSE_TO_ENEMY)


func test_friends_below_a_bridge_do_not_stop_a_model_on_it() -> void:
	_piece(Vector2(20, 20), Vector3(8, 0.5, 3), TerrainPiece.Tag.NONE, TerrainPiece.Shape.BOX, 3.0)
	var walker: int = _place(Vector3(17, 3.5, 20), 32, 6.0)
	_place(Vector3(20, 0, 20), 32)
	assert_eq(state.execute(MoveCommand.new(walker, [Vector3(20, 3.5, 20)])), "", "ends right above it")


func test_ends_must_be_stoppable() -> void:
	# A narrow beam: crossed but not stopped on.
	_piece(Vector2(10, 10), Vector3(6, 2, 0.3))
	_piece(Vector2(4, 10), Vector3(6, 2, 6))
	_piece(Vector2(16, 10), Vector3(6, 2, 6))
	var id: int = _place(Vector3(6, 2, 10), 32, 8.0)
	var command: MoveCommand = MoveCommand.new(id, [Vector3(7, 2, 10), Vector3(10, 2, 10)])
	assert_ne(state.execute(command), "")
	assert_string_contains(command.validate(state), "half the base")
	var across: Array[Vector3] = [Vector3(7, 2, 10), Vector3(13, 2, 10), Vector3(14, 2, 10)]
	assert_eq(state.execute(MoveCommand.new(id, across)), "", "crossing it is fine")
