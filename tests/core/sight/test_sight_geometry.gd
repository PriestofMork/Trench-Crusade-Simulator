extends GutTest
## Segment tests for line of sight (brief 008): boxes, ramps, tilted
## cylinders and the tabletop, with grazing cases and segments that start on
## a surface (ruling 6).

const T: float = SightGeometry.TOLERANCE


func _box(center: Vector2, size: Vector3, turn_degrees: float = 0.0, base: float = 0.0) -> SightGeometry.Solid:
	var piece: TerrainPiece = TerrainPiece.new(
		1, center, Vector2(size.x, size.z), deg_to_rad(turn_degrees), base, size.y
	)
	return SightGeometry.piece_solid(piece)


func _ramp(center: Vector2, size: Vector3, turn_degrees: float = 0.0) -> SightGeometry.Solid:
	var piece: TerrainPiece = TerrainPiece.new(
		1, center, Vector2(size.x, size.z), deg_to_rad(turn_degrees), 0.0, size.y,
		TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP
	)
	return SightGeometry.piece_solid(piece)


func _blocked(a: Vector3, b: Vector3, solid: SightGeometry.Solid) -> bool:
	return SightGeometry.segment_blocked_by_solid(a, b, solid)


func _cyl(a: Vector3, b: Vector3, axis: Vector3) -> bool:
	return SightGeometry.segment_blocked_by_cylinder(a, b, Vector3(10, 0, 10), axis, 0.5, 2.0)


# --- Box ----------------------------------------------------------------------


func test_segment_through_a_box_is_blocked() -> void:
	var box: SightGeometry.Solid = _box(Vector2(10, 10), Vector3(2, 2, 2))
	assert_true(_blocked(Vector3(5, 1, 10), Vector3(15, 1, 10), box), "straight through")
	assert_true(_blocked(Vector3(5, 0.5, 8), Vector3(15, 1.5, 12), box), "diagonally through")


func test_segment_past_or_over_a_box_is_clear() -> void:
	var box: SightGeometry.Solid = _box(Vector2(10, 10), Vector3(2, 2, 2))
	assert_false(_blocked(Vector3(5, 1, 12.5), Vector3(15, 1, 12.5), box), "beside it")
	assert_false(_blocked(Vector3(5, 2.5, 10), Vector3(15, 2.5, 10), box), "over it")
	assert_false(_blocked(Vector3(5, 1, 10), Vector3(8.5, 1, 10), box), "stops short of it")


func test_grazing_a_face_or_an_edge_is_clear() -> void:
	var box: SightGeometry.Solid = _box(Vector2(10, 10), Vector3(2, 2, 2))
	assert_false(_blocked(Vector3(5, 2, 10), Vector3(15, 2, 10), box), "along the top face")
	assert_false(_blocked(Vector3(5, 1, 11), Vector3(15, 1, 11), box), "along a side face")
	assert_false(_blocked(Vector3(7, 1, 10), Vector3(9, 2, 10), box), "ends on the top edge")
	# Through the near top edge (9, 2) and on upwards: touches the edge only.
	assert_false(_blocked(Vector3(5, 0, 10), Vector3(13, 4, 10), box), "touches the near top edge only")
	assert_true(_blocked(Vector3(5, 0, 10), Vector3(13, 4 - 100 * T, 10), box), "a little lower goes in")


func test_segments_starting_on_a_surface() -> void:
	var box: SightGeometry.Solid = _box(Vector2(10, 10), Vector3(2, 2, 2))
	assert_false(_blocked(Vector3(10, 2, 10), Vector3(20, 4, 10), box), "from the top, going up")
	assert_false(_blocked(Vector3(9.5, 2, 10), Vector3(10.5, 2, 9.5), box), "between two points on the top")
	assert_true(_blocked(Vector3(10, 2, 10), Vector3(14, 0, 10), box), "from the top, going down through it")
	assert_false(_blocked(Vector3(9, 0.5, 10), Vector3(4, 0.5, 10), box), "from a side face, going away")


func test_turned_box() -> void:
	var box: SightGeometry.Solid = _box(Vector2(10, 10), Vector3(4, 2, 0.5), 45.0)
	# The long side runs along (cos 45, -sin 45) in (x, z): from (8.6, 11.4) to (11.4, 8.6).
	assert_true(_blocked(Vector3(8, 1, 8), Vector3(12, 1, 12), box), "across the turned wall")
	assert_false(_blocked(Vector3(6, 1, 6), Vector3(9, 1, 9), box), "short of it")
	assert_false(_blocked(Vector3(7.4, 1, 13.4), Vector3(13.4, 1, 7.4), box), "alongside it, outside its half-width")
	assert_true(box.bounds_min.x < 8.7 and box.bounds_max.x > 11.3, "its box covers the turned footprint")


func test_floating_box_lets_a_line_pass_under_it() -> void:
	var deck: SightGeometry.Solid = _box(Vector2(10, 10), Vector3(4, 0.5, 4), 0.0, 3.0)
	assert_false(_blocked(Vector3(5, 1, 10), Vector3(15, 1, 10), deck), "under the deck")
	assert_true(_blocked(Vector3(10, 1, 10), Vector3(10, 4, 10), deck), "from under it to on top")


# --- Ramp ---------------------------------------------------------------------


func test_segment_against_a_ramp() -> void:
	# Rises along +x from 0 at x = 7 to 2 at x = 13.
	var ramp: SightGeometry.Solid = _ramp(Vector2(10, 10), Vector3(6, 2, 3))
	assert_true(_blocked(Vector3(5, 0.5, 10), Vector3(15, 0.5, 10), ramp), "low along its length")
	assert_false(_blocked(Vector3(5, 0.5, 10), Vector3(8, 0.5, 10), ramp), "over its low end")
	assert_true(_blocked(Vector3(12, 0.5, 5), Vector3(12, 0.5, 15), ramp), "across it near the high end")
	assert_false(_blocked(Vector3(8, 0.5, 5), Vector3(8, 0.5, 15), ramp), "across it above the slope")


func test_segment_along_a_ramp_surface_is_clear() -> void:
	var ramp: SightGeometry.Solid = _ramp(Vector2(10, 10), Vector3(6, 2, 3))
	# Its top: y = (x - 7) / 3.
	assert_false(_blocked(Vector3(7, 0, 10), Vector3(13, 2, 10), ramp), "along the slope")
	assert_false(_blocked(Vector3(8, 1.0 / 3.0, 10), Vector3(12, 5.0 / 3.0, 9), ramp), "between two points on it")
	assert_true(_blocked(Vector3(8, 1.0 / 3.0, 10), Vector3(12, 1.0, 10), ramp), "from it into it")


func test_turned_ramp_rises_the_other_way() -> void:
	var ramp: SightGeometry.Solid = _ramp(Vector2(10, 10), Vector3(6, 2, 3), 180.0)
	assert_true(_blocked(Vector3(8, 0.5, 5), Vector3(8, 0.5, 15), ramp), "high end now at x = 7")
	assert_false(_blocked(Vector3(12, 0.5, 5), Vector3(12, 0.5, 15), ramp), "low end now at x = 13")


# --- Cylinder -----------------------------------------------------------------


func test_segment_against_an_upright_cylinder() -> void:
	assert_true(_cyl(Vector3(5, 1, 10), Vector3(15, 1, 10), Vector3.UP), "through")
	assert_false(_cyl(Vector3(5, 1, 10.5), Vector3(15, 1, 10.5), Vector3.UP), "tangent")
	assert_false(_cyl(Vector3(5, 2, 10), Vector3(15, 2, 10), Vector3.UP), "along the top")
	assert_true(_cyl(Vector3(5, 0, 10), Vector3(15, 0, 10), Vector3.UP), "along the underside: it stands there (see the undersides below)")
	assert_false(_cyl(Vector3(5, -0.01, 10), Vector3(15, -0.01, 10), Vector3.UP), "below the underside")
	assert_true(_cyl(Vector3(10, 5, 10), Vector3(10, 1, 10), Vector3.UP), "down the axis into it")
	assert_false(_cyl(Vector3(10.5, 1, 10), Vector3(15, 1, 10), Vector3.UP), "from its side, going away")
	assert_false(_cyl(Vector3(5, 1, 10), Vector3(9.4, 1, 10), Vector3.UP), "stops short")


func test_segment_against_a_tilted_cylinder() -> void:
	var axis: Vector3 = Vector3(-1, 1, 0).normalized()
	# The top centre leans to (10 - 1.414, 1.414) for height 2.
	var high: Vector3 = Vector3(10 - 1.3, 1.4, 5)
	assert_true(_cyl(high, high + Vector3(0, 0, 10), axis), "through the leaning top")
	assert_false(_cyl(high, high + Vector3(0, 0, 10), Vector3.UP), "an upright one would miss")
	var upright_only: Vector3 = Vector3(10.2, 1.8, 5)
	assert_true(_cyl(upright_only, upright_only + Vector3(0, 0, 10), Vector3.UP), "upright is hit")
	assert_false(_cyl(upright_only, upright_only + Vector3(0, 0, 10), axis), "the tilted one has leant away")


# --- Tabletop -----------------------------------------------------------------


func test_tabletop() -> void:
	assert_false(SightGeometry.segment_blocked_by_table(Vector3(0, 0, 0), Vector3(10, 0, 0)), "along the table")
	assert_false(SightGeometry.segment_blocked_by_table(Vector3(0, 0, 0), Vector3(10, 2, 0)), "from the table up")
	assert_true(SightGeometry.segment_blocked_by_table(Vector3(0, 1, 0), Vector3(10, -1, 0)), "into the table")


# --- Undersides ---------------------------------------------------------------


func test_a_line_along_the_floor_is_blocked_by_what_stands_on_it() -> void:
	var wall: SightGeometry.Solid = _box(Vector2(10, 10), Vector3(0.5, 2, 4))
	assert_true(_blocked(Vector3(5, 0, 10), Vector3(15, 0, 10), wall), "along the table under the wall's foot")
	var on_box: SightGeometry.Solid = _box(Vector2(10, 10), Vector3(0.5, 1, 4), 0.0, 2.0)
	assert_true(_blocked(Vector3(5, 2, 10), Vector3(15, 2, 10), on_box), "along a box top under a piece on it")
	assert_true(SightGeometry.segment_blocked_by_cylinder(
		Vector3(5, 0, 10), Vector3(15, 0, 10), Vector3(10, 0, 10), Vector3.UP, 0.5, 2.0
	), "along the floor under a model standing on it")
