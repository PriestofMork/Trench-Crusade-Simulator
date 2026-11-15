extends GutTest

const R32: float = 0.62992126  # 32 mm base radius, inches
const H32: float = 1.9

var state: GameState


func before_each() -> void:
	state = GameState.new(1)


func _piece(
	center: Vector2, size: Vector3, base: float = 0.0, rotation: float = 0.0,
	tag: TerrainPiece.Tag = TerrainPiece.Tag.NONE, shape: TerrainPiece.Shape = TerrainPiece.Shape.BOX
) -> int:
	var command: PlaceTerrainCommand = PlaceTerrainCommand.new(center, size, rotation, base, tag, shape)
	assert_eq(state.execute(command), "")
	return command.placed_terrain_id


func _surface_of(field: HeightField, piece_id: int) -> int:
	for s: HeightField.Surface in field.surfaces:
		if s.piece_id() == piece_id:
			return s.index
	return -1


func test_floors_under_and_on_a_bridge() -> void:
	var bridge: int = _piece(Vector2(20, 20), Vector3(8, 0.5, 3), 3.0)
	var field: HeightField = HeightField.new(state)
	var ix: int = floori(20.0 / HeightField.CELL_SIZE)
	var floors: Array[HeightField.Floor] = field.cell_floors(ix, ix)
	assert_eq(floors.size(), 2)
	assert_eq(floors[0].piece_id, -1, "the table, lowest first")
	assert_almost_eq(floors[0].height, 0.0, 0.0001)
	assert_eq(floors[1].piece_id, bridge)
	assert_almost_eq(floors[1].height, 3.5, 0.0001)
	assert_eq(floors[1].slope_degrees, 0.0)
	# Beside the bridge only the table.
	assert_eq(field.surfaces_at(Vector2(20, 25)).size(), 1)
	# Under the bridge and on it are both passable and stoppable.
	var deck: int = _surface_of(field, bridge)
	assert_true(field.stoppable(Vector2(20, 20), HeightField.TABLE, R32, H32))
	assert_true(field.stoppable(Vector2(20, 20), deck, R32, H32))


func test_a_box_on_the_table_covers_it() -> void:
	var box: int = _piece(Vector2(10, 10), Vector3(4, 2, 4))
	var field: HeightField = HeightField.new(state)
	var here: PackedInt32Array = field.surfaces_at(Vector2(10, 10))
	assert_eq(here.size(), 1)
	assert_eq(field.surface_piece_id(here[0]), box)
	assert_almost_eq(field.surface_height(here[0], Vector2(10, 10)), 2.0, 0.0001)


func test_headroom_under_a_low_bridge() -> void:
	# Underside at 2": a 25 mm model (1.7") fits, a 60 mm one (3.0") does not.
	_piece(Vector2(20, 20), Vector3(8, 0.5, 6), 2.0)
	var field: HeightField = HeightField.new(state)
	var under: Vector2 = Vector2(20, 20)
	var r25: float = BaseSizes.mm_to_inches(25) / 2.0
	var r60: float = BaseSizes.mm_to_inches(60) / 2.0
	assert_true(field.stoppable(under, HeightField.TABLE, r25, BaseSizes.height_inches(25)))
	assert_false(field.stoppable(under, HeightField.TABLE, r60, BaseSizes.height_inches(60)))
	# Passing under is not a headroom question (see the report on brief 004).
	assert_true(field.passable(under, HeightField.TABLE, r60))
	# Partly under the edge of the bridge counts too.
	assert_false(field.stoppable(Vector2(20, 23 + r60 - 0.1), HeightField.TABLE, r60, 3.0))
	assert_true(field.stoppable(Vector2(20, 23 + r60 + 0.01), HeightField.TABLE, r60, 3.0))


func test_on_a_straight_ledge_is_stoppable_at_a_corner_only_passable() -> void:
	var platform: int = _piece(Vector2(10, 10), Vector3(4, 2, 4))
	var field: HeightField = HeightField.new(state)
	var top: int = _surface_of(field, platform)
	# Centre exactly on the middle of the east edge: half the base is over the top.
	var ledge: Vector2 = Vector2(12, 10)
	assert_almost_eq(field.support_fraction(ledge, top, R32), 0.5, 1e-6)
	assert_true(field.passable(ledge, top, R32))
	assert_true(field.stoppable(ledge, top, R32, H32))
	# A hair further out: still passable (centre on the edge), not stoppable.
	assert_false(field.stoppable(Vector2(12.0005, 10), top, R32, H32))
	# On the outward corner: a quarter of the base.
	var corner: Vector2 = Vector2(12, 12)
	assert_almost_eq(field.support_fraction(corner, top, R32), 0.25, 1e-6)
	assert_true(field.passable(corner, top, R32))
	assert_false(field.stoppable(corner, top, R32, H32))
	# Past the edge the centre is not over the floor.
	assert_false(field.passable(Vector2(12.01, 10), top, R32))


func test_turned_ledge_is_exact_too() -> void:
	var platform: int = _piece(Vector2(20, 20), Vector3(5, 2, 3), 0.0, 0.83)
	var field: HeightField = HeightField.new(state)
	var top: int = _surface_of(field, platform)
	var on_edge: Vector2 = PlanarGeometry.from_rect_local(Vector2(2.5, 0.4), Vector2(20, 20), 0.83)
	assert_true(field.stoppable(on_edge, top, R32, H32))


func test_narrow_beam_is_passable_not_stoppable() -> void:
	var beam: int = _piece(Vector2(10, 10), Vector3(6, 2, 0.3))
	var field: HeightField = HeightField.new(state)
	var top: int = _surface_of(field, beam)
	assert_true(field.passable(Vector2(10, 10), top, R32))
	assert_lt(field.support_fraction(Vector2(10, 10), top, R32), 0.5)
	assert_false(field.stoppable(Vector2(10, 10), top, R32, H32))
	assert_true(field.walk_clear(Vector2(7.5, 10), Vector2(12.5, 10), top, R32))


func test_overlapping_a_wall_is_neither() -> void:
	_piece(Vector2(10, 10), Vector3(4, 2, 4))
	var field: HeightField = HeightField.new(state)
	var against: Vector2 = Vector2(12 + R32 - 0.1, 10)
	assert_false(field.passable(against, HeightField.TABLE, R32))
	assert_false(field.stoppable(against, HeightField.TABLE, R32, H32))
	var touching: Vector2 = Vector2(12 + R32, 10)
	assert_true(field.stoppable(touching, HeightField.TABLE, R32, H32))
	assert_false(field.walk_clear(Vector2(16, 10), Vector2(12 + R32 - 0.1, 10), HeightField.TABLE, R32))
	assert_true(field.walk_clear(Vector2(16, 10), touching, HeightField.TABLE, R32))


func test_low_obstacle_blocks_a_base_on_the_ground() -> void:
	_piece(Vector2(10, 10), Vector3(0.75, 0.5, 4))
	var field: HeightField = HeightField.new(state)
	assert_false(field.passable(Vector2(10.375 + R32 - 0.05, 10), HeightField.TABLE, R32))
	assert_true(field.passable(Vector2(10.375 + R32, 10), HeightField.TABLE, R32))


func test_ramp_foot_and_top_are_the_floor_continuing() -> void:
	# Ramp from x = 4 (height 0) to x = 10 (height 2), then a 2" platform.
	var ramp: int = _piece(Vector2(7, 10), Vector3(6, 2, 3), 0.0, 0.0, TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	var platform: int = _piece(Vector2(13, 10), Vector3(6, 2, 6))
	var field: HeightField = HeightField.new(state)
	var slope: int = _surface_of(field, ramp)
	var top: int = _surface_of(field, platform)
	# At the foot, on the table, the base reaches over the start of the ramp.
	assert_true(field.passable(Vector2(4, 10), HeightField.TABLE, R32))
	assert_true(field.passable(Vector2(4, 10), slope, R32))
	assert_true(field.walk_clear(Vector2(1, 10), Vector2(4, 10), HeightField.TABLE, R32))
	# Beside the ramp half way up, the base may not overlap its side.
	assert_false(field.passable(Vector2(7, 11.5 + R32 - 0.1), HeightField.TABLE, R32))
	assert_true(field.passable(Vector2(7, 11.5 + R32), HeightField.TABLE, R32))
	# Up the ramp onto the platform.
	assert_true(field.walk_clear(Vector2(4, 10), Vector2(10, 10), slope, R32))
	assert_true(field.passable(Vector2(9.8, 10), slope, R32))
	assert_true(field.passable(Vector2(10, 10), top, R32))
	assert_true(field.stoppable(Vector2(7, 10), slope, R32, H32))
	assert_almost_eq(field.surface_height(slope, Vector2(7, 10)), 1.0, 0.0001)


func test_steep_ramp_and_impassable_give_no_floor_and_block() -> void:
	var steep: int = _piece(Vector2(10, 10), Vector3(0.8, 3, 3), 0.0, 0.0, TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	var stone: int = _piece(Vector2(20, 10), Vector3(2, 0.8, 2), 0.0, 0.0, TerrainPiece.Tag.IMPASSABLE)
	var field: HeightField = HeightField.new(state)
	assert_eq(_surface_of(field, steep), -1)
	assert_eq(_surface_of(field, stone), -1)
	assert_eq(field.surfaces_at(Vector2(20, 10)).size(), 0, "nothing to stand on inside it")
	assert_false(field.passable(Vector2(9.6 - R32 + 0.1, 10), HeightField.TABLE, R32))
	assert_false(field.passable(Vector2(21 + R32 - 0.1, 10), HeightField.TABLE, R32))


func test_stand_value_is_the_distance_to_a_straight_ledge() -> void:
	var platform: int = _piece(Vector2(10, 10), Vector3(4, 2, 4))
	var field: HeightField = HeightField.new(state)
	var top: int = _surface_of(field, platform)
	for d: float in [-0.3, -0.1, 0.0, 0.2, 0.5]:
		var p: Vector2 = Vector2(12 - d, 10)
		assert_almost_eq(field.stand_value(p, top, R32, H32), d, 0.0005, "%.1f inside the edge" % d)
	# Off the table edge and against a wall it is the clearance.
	assert_almost_eq(field.stand_value(Vector2(1, 30), HeightField.TABLE, R32, H32), 1 - R32, 0.0001)
	assert_almost_eq(field.stand_value(Vector2(13, 10), HeightField.TABLE, R32, H32), 1 - R32, 0.0001)


# Seams: the floor is the whole level surface, not one piece (terrain.md).


func test_stoppable_exactly_on_a_seam_between_two_same_height_boxes() -> void:
	var west: int = _piece(Vector2(10, 10), Vector3(4, 2, 4))
	var east: int = _piece(Vector2(14, 10), Vector3(4, 2, 4))
	var field: HeightField = HeightField.new(state)
	var a: int = _surface_of(field, west)
	var b: int = _surface_of(field, east)
	assert_true(field.joined_surfaces(a).has(b))
	assert_true(field.same_level(a, b))
	var seam: Vector2 = Vector2(12, 10)
	for s: int in [a, b]:
		assert_true(field.passable(seam, s, R32), "centre on the seam is over the floor")
		assert_almost_eq(field.support_fraction(seam, s, R32), 1.0, 1e-6, "both pieces count")
		assert_true(field.stoppable(seam, s, R32, H32))
	# Just off the seam onto either piece, still fully supported.
	assert_almost_eq(field.support_fraction(Vector2(11.8, 10), a, R32), 1.0, 1e-6)
	assert_almost_eq(field.stand_value(seam, a, R32, H32), field.stand_value(Vector2(11.9, 10), a, R32, H32), 0.11)


func test_near_the_outer_corner_of_a_seam_only_both_together_count() -> void:
	# Two boxes meeting at x = 12; their common outer edge is z = 12.
	var west: int = _piece(Vector2(10, 10), Vector3(4, 2, 4))
	_piece(Vector2(14, 10), Vector3(4, 2, 4))
	var field: HeightField = HeightField.new(state)
	var a: int = _surface_of(field, west)
	# On the seam at the outer edge: half the base over the two together.
	assert_almost_eq(field.support_fraction(Vector2(12, 12), a, R32), 0.5, 1e-6)
	assert_true(field.stoppable(Vector2(12, 12), a, R32, H32))
	assert_true(field.stoppable(Vector2(12, 11.9), a, R32, H32))
	assert_false(field.stoppable(Vector2(12, 12.0005), a, R32, H32), "under half, even together")
	# A lone box's corner is only a quarter.
	state = GameState.new(1)
	var alone: int = _piece(Vector2(10, 10), Vector3(4, 2, 4))
	field = HeightField.new(state)
	assert_almost_eq(field.support_fraction(Vector2(12, 12), _surface_of(field, alone), R32), 0.25, 1e-6)


func test_ramp_top_meeting_a_platform_supports_together() -> void:
	# A ramp only 0.5" wide, too narrow to hold half a 32 mm base on its own,
	# rising from x = 4 to its top at x = 10 where a 2" platform starts.
	var ramp: int = _piece(Vector2(7, 10), Vector3(6, 2, 0.5), 0.0, 0.0, TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	var platform: int = _piece(Vector2(13, 10), Vector3(6, 2, 6))
	var field: HeightField = HeightField.new(state)
	var slope: int = _surface_of(field, ramp)
	var top: int = _surface_of(field, platform)
	assert_true(field.joined_surfaces(slope).has(top))
	assert_false(field.same_level(slope, top), "different planes: joined, not one level")
	assert_false(field.stoppable(Vector2(7, 10), slope, R32, H32), "mid-ramp the strip is too narrow")
	assert_true(field.stoppable(Vector2(9.8, 10), slope, R32, H32), "at the top the platform helps")
	# The ramp's foot joins the table too.
	assert_true(field.joined_surfaces(slope).has(HeightField.TABLE))


func test_pieces_of_different_heights_do_not_support_each_other() -> void:
	var low: int = _piece(Vector2(10, 10), Vector3(4, 0.5, 4))
	var high: int = _piece(Vector2(14, 10), Vector3(4, 1, 4))
	var field: HeightField = HeightField.new(state)
	var a: int = _surface_of(field, low)
	var b: int = _surface_of(field, high)
	assert_false(field.joined_surfaces(a).has(b))
	assert_almost_eq(field.support_fraction(Vector2(12, 10), b, R32), 0.5, 1e-6, "only its own half")
	assert_false(field.stoppable(Vector2(11.999, 10), b, R32, H32), "lower ground never counts")
	assert_almost_eq(field.stop_surcharge(a, PackedInt32Array([high])), 0.5, 0.0001)
