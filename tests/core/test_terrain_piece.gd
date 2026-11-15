extends GutTest


func _piece(shape: TerrainPiece.Shape, rotation: float = 0.0, height: float = 2.0) -> TerrainPiece:
	return TerrainPiece.new(1, Vector2(10, 10), Vector2(4, 2), rotation, 1.0, height,
		TerrainPiece.Tag.NONE, shape)


func test_box_top_is_flat() -> void:
	var box: TerrainPiece = _piece(TerrainPiece.Shape.BOX)
	assert_eq(box.top_at_center(), 3.0)
	assert_eq(box.top_plane_at(Vector2(11.5, 9.2)), 3.0)
	assert_eq(box.top_gradient(), Vector2.ZERO)
	assert_eq(box.slope_degrees(), 0.0)
	assert_true(box.has_floor())


func test_ramp_rises_along_its_own_x_axis() -> void:
	var ramp: TerrainPiece = _piece(TerrainPiece.Shape.RAMP)
	assert_almost_eq(ramp.top_plane_at(Vector2(8, 10)), 1.0, 0.0001, "low end at the underside")
	assert_almost_eq(ramp.top_plane_at(Vector2(12, 10.5)), 3.0, 0.0001, "high end")
	assert_almost_eq(ramp.slope_degrees(), rad_to_deg(atan(0.5)), 0.0001)
	# Turned a quarter turn the same way as Node3D.rotation.y: own +x is world -z.
	var turned: TerrainPiece = _piece(TerrainPiece.Shape.RAMP, PI / 2.0)
	assert_almost_eq(turned.top_plane_at(Vector2(10, 8)), 3.0, 0.0001)
	assert_almost_eq(turned.top_plane_at(Vector2(10, 12)), 1.0, 0.0001)
	var basis: Basis = Basis(Vector3.UP, PI / 2.0)
	var own_x: Vector3 = basis * Vector3.RIGHT
	assert_almost_eq(turned.local_x_axis().x, own_x.x, 0.0001)
	assert_almost_eq(turned.local_x_axis().y, own_x.z, 0.0001)


func test_steep_ramp_and_impassable_piece_have_no_floor() -> void:
	var steep: TerrainPiece = TerrainPiece.new(1, Vector2(10, 10), Vector2(0.8, 2), 0.0, 0.0, 3.0,
		TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	assert_gt(steep.slope_degrees(), TerrainRules.STEEP_SLOPE_DEGREES)
	assert_false(steep.has_floor())
	var walkable: TerrainPiece = TerrainPiece.new(1, Vector2(10, 10), Vector2(1.2, 2), 0.0, 0.0, 3.0,
		TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	assert_lt(walkable.slope_degrees(), TerrainRules.STEEP_SLOPE_DEGREES)
	assert_true(walkable.has_floor())
	var impassable: TerrainPiece = TerrainPiece.new(1, Vector2(10, 10), Vector2(2, 2), 0.0, 0.0, 1.0,
		TerrainPiece.Tag.IMPASSABLE)
	assert_false(impassable.has_floor())


func test_tunable_values_match_the_rules() -> void:
	assert_eq(TerrainRules.LOW_OBSTACLE_HEIGHT, 1.0)
	assert_eq(TerrainRules.OPEN_CLIMB_HEIGHT, 3.0)
	assert_eq(TerrainRules.STEEP_SLOPE_DEGREES, 70.0)
