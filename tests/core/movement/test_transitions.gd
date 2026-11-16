extends GutTest

const K = Transitions.Kind
const NONE_TAG = TerrainPiece.Tag.NONE
const SHEER = TerrainPiece.Tag.SHEER
const LADDER = TerrainPiece.Tag.LADDER


func _up(height: float, tag: TerrainPiece.Tag = NONE_TAG, low: bool = false) -> Transitions.Kind:
	return Transitions.roll_free_wall_kind(true, height, tag, low)


func _down(height: float, tag: TerrainPiece.Tag = NONE_TAG) -> Transitions.Kind:
	return Transitions.roll_free_wall_kind(false, height, tag, false)


func test_open_climb_up_to_three_inches() -> void:
	assert_eq(_up(2.0), K.OPEN_CLIMB)
	assert_eq(_up(3.0), K.OPEN_CLIMB, "exactly 3\" is an open climb")
	assert_eq(_up(3.0 + 0.00005), K.OPEN_CLIMB, "within the slack")
	assert_eq(_up(3.01), K.NONE, "higher needs a roll: part 2")
	assert_eq(Transitions.wall_options(true, 3.01, NONE_TAG, false), [K.SHEER_CLIMB_UP] as Array[Transitions.Kind])
	assert_true(Transitions.needs_roll(K.SHEER_CLIMB_UP))


func test_sheer_tag_always_needs_a_roll() -> void:
	assert_eq(_up(2.0, SHEER), K.NONE)
	assert_eq(_up(0.5, SHEER, true), K.NONE, "even a low one")
	assert_eq(Transitions.wall_options(true, 2.0, SHEER, false), [K.SHEER_CLIMB_UP] as Array[Transitions.Kind])


func test_ladder_tag_never_needs_a_roll() -> void:
	assert_eq(_up(4.0, LADDER), K.LADDER_UP)
	assert_eq(_up(10.0, LADDER), K.LADDER_UP)
	assert_eq(_down(4.0, LADDER), K.LADDER_DOWN)
	assert_eq(_down(2.0, LADDER), K.HOP_DOWN, "a small drop is a free hop, ladder or not")


func test_drops_below_three_inches_are_free_hops() -> void:
	assert_eq(_down(0.5), K.HOP_DOWN)
	assert_eq(_down(2.99), K.HOP_DOWN)
	assert_eq(_down(3.0), K.NONE, "3\" counts as falling: part 2")
	assert_eq(_down(3.0, SHEER), K.NONE)
	assert_eq(_down(2.0, SHEER), K.HOP_DOWN)
	assert_eq(Transitions.wall_options(false, 3.0, NONE_TAG, false), [K.DROP] as Array[Transitions.Kind], "Drop mode")
	var climb_down: Transitions.DescentMode = Transitions.DescentMode.CLIMB_DOWN
	assert_eq(Transitions.wall_options(false, 3.0, NONE_TAG, false, climb_down), [K.SHEER_CLIMB_DOWN] as Array[Transitions.Kind])
	assert_eq(Transitions.wall_options(false, 4.0, LADDER, false, climb_down), [K.SHEER_CLIMB_DOWN, K.LADDER_DOWN] as Array[Transitions.Kind])
	assert_eq(Transitions.wall_options(false, 2.0, NONE_TAG, false, climb_down), [K.HOP_DOWN] as Array[Transitions.Kind], "small drops in both")
	assert_true(Transitions.needs_roll(K.DROP))


func test_low_obstacles_are_free_to_step_onto() -> void:
	assert_eq(_up(0.5, NONE_TAG, true), K.STEP_ONTO_LOW_OBSTACLE)
	assert_eq(_up(1.0, NONE_TAG, true), K.STEP_ONTO_LOW_OBSTACLE)
	assert_eq(_up(0.5, LADDER, true), K.STEP_ONTO_LOW_OBSTACLE)
	assert_eq(_up(0.9, NONE_TAG, false), K.OPEN_CLIMB, "a step onto a taller piece is a climb")


func test_impassable_cannot_be_crossed() -> void:
	assert_eq(Transitions.wall_options(true, 0.5, TerrainPiece.Tag.IMPASSABLE, true).size(), 0)
	assert_eq(Transitions.wall_options(false, 0.5, TerrainPiece.Tag.IMPASSABLE, false).size(), 0)


func test_costs() -> void:
	var r: float = 0.63
	assert_almost_eq(Transitions.wall_cost(K.OPEN_CLIMB, r, 2.0), r + 2.0, 0.0001)
	assert_almost_eq(Transitions.wall_cost(K.LADDER_UP, r, 4.0), r + 4.0, 0.0001)
	assert_almost_eq(Transitions.wall_cost(K.LADDER_DOWN, r, 4.0), r + 4.0, 0.0001)
	assert_almost_eq(Transitions.wall_cost(K.HOP_DOWN, r, 2.5), r, 0.0001)
	assert_almost_eq(Transitions.wall_cost(K.STEP_ONTO_LOW_OBSTACLE, r, 0.5), r, 0.0001)
	assert_eq(Transitions.wall_cost(K.NONE, r, 1.0), INF)


func test_low_obstacle_detection_and_stop_surcharge() -> void:
	var state: GameState = GameState.new(1)
	var place: Callable = func(center: Vector2, size: Vector3, base: float) -> int:
		var command: PlaceTerrainCommand = PlaceTerrainCommand.new(center, size, 0.0, base)
		state.execute(command)
		return command.placed_terrain_id
	var crate: int = place.call(Vector2(5, 5), Vector3(3, 1, 3), 0.0)
	var tall: int = place.call(Vector2(15, 5), Vector3(3, 1.5, 3), 0.0)
	var platform: int = place.call(Vector2(25, 5), Vector3(6, 2, 6), 0.0)
	var sandbag_on_platform: int = place.call(Vector2(25, 5), Vector3(2, 0.5, 0.75), 2.0)
	var deck: int = place.call(Vector2(35, 5), Vector3(4, 0.5, 2), 3.0)
	var field: HeightField = HeightField.new(state)
	var by_piece: Dictionary[int, int] = {}
	for s: HeightField.Surface in field.surfaces:
		by_piece[s.piece_id()] = s.index
	assert_true(field.is_low_obstacle(by_piece[crate]))
	assert_false(field.is_low_obstacle(by_piece[tall]))
	assert_false(field.is_low_obstacle(by_piece[platform]))
	assert_true(field.is_low_obstacle(by_piece[sandbag_on_platform]))
	assert_false(field.is_low_obstacle(by_piece[deck]), "a floating deck is not a low obstacle")
	assert_false(field.is_low_obstacle(HeightField.TABLE))
	assert_almost_eq(field.stop_surcharge(by_piece[crate], PackedInt32Array([-1])), 1.0, 0.0001)
	assert_almost_eq(field.stop_surcharge(by_piece[crate], PackedInt32Array([crate])), 0.0, 0.0001)
	assert_almost_eq(field.stop_surcharge(by_piece[sandbag_on_platform], PackedInt32Array([platform])), 0.5, 0.0001)
	assert_almost_eq(field.stop_surcharge(by_piece[platform], PackedInt32Array([-1])), 0.0, 0.0001)
