extends GutTest

var state: GameState
var mover: int


func before_each() -> void:
	state = GameState.new(1)
	# 32 mm base: radius ~0.63". Movement 6".
	mover = _place(0, Vector3(10, 0, 10), 32, 6.0)


func _place(player: int, pos: Vector3, base_mm: int, movement: float = 6.0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, base_mm, movement)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _move(waypoints: Array[Vector3]) -> MoveCommand:
	return MoveCommand.new(mover, waypoints)


func test_model_starts_with_full_movement() -> void:
	var model: ModelState = state.get_model(mover)
	assert_eq(model.movement, 6.0)
	assert_eq(model.movement_left, 6.0)


func test_accepts_legal_path() -> void:
	var command: MoveCommand = _move([Vector3(13, 0, 10), Vector3(13, 0, 12)])
	assert_eq(state.execute(command), "")
	assert_eq(state.get_model(mover).position, Vector3(13, 0, 12))
	assert_eq(command.rejection, MoveCommand.Rejection.NONE)


func test_rejects_too_long() -> void:
	var command: MoveCommand = _move([Vector3(16.5, 0, 10)])
	assert_string_contains(state.execute(command), "Too far")
	assert_eq(command.rejection, MoveCommand.Rejection.TOO_FAR)
	assert_eq(state.get_model(mover).position, Vector3(10, 0, 10))


func test_rejects_through_terrain() -> void:
	state.execute(PlaceTerrainCommand.new(Vector3(13, 1, 10), Vector3(1, 2, 4)))
	var command: MoveCommand = _move([Vector3(15.5, 0, 10)])
	assert_string_contains(state.execute(command), "terrain")
	assert_eq(command.rejection, MoveCommand.Rejection.BLOCKED)


func test_ignores_terrain_that_does_not_block() -> void:
	state.execute(PlaceTerrainCommand.new(Vector3(13, 0.25, 10), Vector3(1, 0.5, 4), 0.0, false))
	assert_eq(state.execute(_move([Vector3(15.5, 0, 10)])), "")


func test_rejects_ending_inside_terrain() -> void:
	state.execute(PlaceTerrainCommand.new(Vector3(14, 1, 10), Vector3(2, 2, 2)))
	assert_ne(state.execute(_move([Vector3(14, 0, 10)])), "")


func test_rejects_through_rotated_terrain_corner() -> void:
	# A diamond whose corner pokes towards the straight path.
	state.execute(PlaceTerrainCommand.new(Vector3(13, 1, 12), Vector3(2, 2, 2), PI / 4.0))
	# Corner at z = 12 - sqrt(2) ~ 10.59; the base reaches z = 10.63 on the straight line.
	assert_ne(state.execute(_move([Vector3(15, 0, 10)])), "")
	# A path dipping away from the corner clears it.
	assert_eq(state.execute(_move([Vector3(13, 0, 9.8), Vector3(15, 0, 10)])), "")


func test_accepts_path_through_friendly_base() -> void:
	_place(0, Vector3(13, 0, 10), 32)
	var command: MoveCommand = _move([Vector3(15.5, 0, 10)])
	assert_eq(state.execute(command), "")
	assert_eq(state.get_model(mover).position, Vector3(15.5, 0, 10))


func test_accepts_bent_path_with_a_waypoint_on_a_friendly_base() -> void:
	_place(0, Vector3(13, 0, 10), 32)
	assert_eq(state.execute(_move([Vector3(13, 0, 10), Vector3(13, 0, 13)])), "")


func test_rejects_ending_on_friendly_base() -> void:
	_place(0, Vector3(13, 0, 10), 32)
	var command: MoveCommand = _move([Vector3(13.5, 0, 10)])
	assert_string_contains(state.execute(command), "another model")
	assert_eq(command.rejection, MoveCommand.Rejection.BLOCKED)
	assert_eq(state.get_model(mover).position, Vector3(10, 0, 10))
	# Through it and out the far side, but stopping still overlapping it.
	var r: float = BaseSizes.mm_to_inches(32) / 2.0
	assert_ne(state.execute(_move([Vector3(13 + 2 * r - 0.05, 0, 10)])), "")
	assert_eq(state.execute(_move([Vector3(13 + 2 * r, 0, 10)])), "", "touching is fine")


func test_rejects_path_through_enemy_base() -> void:
	# Far enough from the start and the end that only the base itself is in the way.
	var walker: int = _place(0, Vector3(10, 0, 30), 32, 10.0)
	_place(1, Vector3(15, 0, 30), 25)
	var command: MoveCommand = MoveCommand.new(walker, [Vector3(19.5, 0, 30)])
	assert_ne(state.execute(command), "")
	assert_eq(command.rejection, MoveCommand.Rejection.TOO_CLOSE_TO_ENEMY)
	assert_eq(state.get_model(walker).position, Vector3(10, 0, 30))


func test_rejects_off_table() -> void:
	var near_edge: int = _place(0, Vector3(2, 0, 20), 32)
	var command: MoveCommand = MoveCommand.new(near_edge, [Vector3(0.3, 0, 20)])
	assert_string_contains(state.execute(command), "table")
	assert_eq(command.rejection, MoveCommand.Rejection.BLOCKED)
	# Running along the edge with the base just touching it is fine.
	var r: float = BaseSizes.mm_to_inches(32) / 2.0
	assert_eq(state.execute(MoveCommand.new(near_edge, [Vector3(r, 0, 20), Vector3(r, 0, 23)])), "")


func test_rejects_ending_within_one_inch_of_enemy() -> void:
	# Enemy 32 mm base at x = 14: edge-to-edge 1" means centres 1 + 2 * 0.63 apart.
	_place(1, Vector3(14, 0, 10), 32)
	var r: float = BaseSizes.mm_to_inches(32) / 2.0
	var too_close: MoveCommand = _move([Vector3(14 - 2 * r - 0.9, 0, 10)])
	assert_string_contains(state.execute(too_close), "enemy")
	assert_eq(too_close.rejection, MoveCommand.Rejection.TOO_CLOSE_TO_ENEMY)
	var exactly_one_inch: MoveCommand = _move([Vector3(14 - 2 * r - 1.0, 0, 10)])
	assert_eq(state.execute(exactly_one_inch), "")


func test_rejects_passing_within_one_inch_of_enemy() -> void:
	# The path ends far from the enemy but passes 1.5" (centre to centre) from it.
	_place(1, Vector3(12, 0, 11.5), 32)
	var command: MoveCommand = _move([Vector3(14, 0, 10)])
	assert_eq(state.execute(command), "Too close to an enemy: only a charge may come within 1\".")
	assert_eq(command.rejection, MoveCommand.Rejection.TOO_CLOSE_TO_ENEMY)


func test_allows_passing_and_ending_near_friend() -> void:
	# Friend centre 1.5" off the line: bases (0.63 + 0.63) do not overlap, but
	# edges come within 1".
	_place(0, Vector3(12, 0, 11.5), 32)
	assert_eq(state.execute(_move([Vector3(12, 0, 10.2)])), "")
	assert_eq(state.execute(_move([Vector3(14, 0, 10)])), "")


func test_allows_touching_bases() -> void:
	var r: float = BaseSizes.mm_to_inches(32) / 2.0
	_place(0, Vector3(14, 0, 10), 32)
	assert_eq(state.execute(_move([Vector3(14 - 2 * r, 0, 10)])), "")


func test_deducts_path_length_and_allows_second_move() -> void:
	assert_eq(state.execute(_move([Vector3(13, 0, 10), Vector3(13, 0, 12)])), "")
	assert_almost_eq(state.get_model(mover).movement_left, 1.0, 0.0001)
	assert_ne(state.execute(_move([Vector3(13, 0, 13.5)])), "", "1.5\" is more than is left")
	assert_eq(state.execute(_move([Vector3(13, 0, 13)])), "")
	assert_almost_eq(state.get_model(mover).movement_left, 0.0, 0.0001)


func test_rejects_unknown_model_and_empty_path() -> void:
	assert_ne(state.execute(MoveCommand.new(999, [Vector3(11, 0, 10)])), "")
	assert_ne(state.execute(_move([])), "")


func test_rejects_leaving_flat_ground() -> void:
	assert_ne(state.execute(_move([Vector3(11, 2, 10)])), "")


func test_reset_movement_restores_full_movement() -> void:
	state.execute(_move([Vector3(14, 0, 10)]))
	assert_almost_eq(state.get_model(mover).movement_left, 2.0, 0.0001)
	assert_eq(state.execute(ResetMovementCommand.new(mover)), "")
	assert_eq(state.get_model(mover).movement_left, 6.0)
	assert_ne(state.execute(ResetMovementCommand.new(999)), "")


func test_place_terrain() -> void:
	var command: PlaceTerrainCommand = PlaceTerrainCommand.new(Vector3(5, 1, 5), Vector3(2, 2, 3), 0.5)
	assert_eq(state.execute(command), "")
	assert_eq(state.terrain.size(), 1)
	assert_eq(state.terrain[0].id, command.placed_terrain_id)
	assert_eq(state.terrain[0].rotation, 0.5)
	assert_true(state.terrain[0].blocks_movement)
	assert_ne(state.execute(PlaceTerrainCommand.new(Vector3(5, 1, 5), Vector3(0, 2, 3))), "")
