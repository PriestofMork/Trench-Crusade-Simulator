extends GutTest
## ReachField across heights (brief 004), mostly on the test table.

const TEST_TABLE: String = "res://data/tables/height_test_table.json"
const R32: float = 0.62992126

var state: GameState


func before_each() -> void:
	state = GameState.new(1)


func _test_table(include_models: bool = true) -> void:
	assert_eq(TableSetup.apply_file(state, TEST_TABLE, include_models), PackedStringArray(), "the test table builds")


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


## A fresh state with the test table's terrain and only this model.
func _model_at(pos: Vector3, base_mm: int, movement: float) -> int:
	state = GameState.new(1)
	_test_table(false)
	return _place(pos, base_mm, movement)


func _surface_of_piece(field: ReachField, name_center: Vector2) -> int:
	# The surface whose piece has its footprint centre at name_center.
	for s: HeightField.Surface in field.field.surfaces:
		if s.piece != null and s.piece.footprint_center.is_equal_approx(name_center):
			return s.index
	return -1


func _kinds(field: ReachField, id: int, path: Array[Vector3]) -> Array[Transitions.Kind]:
	var kinds: Array[Transitions.Kind] = []
	var previous: Vector3 = state.get_model(id).position
	for point: Vector3 in path:
		kinds.append(field.segment_kind(previous, point))
		previous = point
	return kinds


func _assert_valid(field: ReachField, id: int, target: Vector3, label: String) -> MoveCommand:
	var path: Array[Vector3] = field.path_to(target)
	assert_false(path.is_empty(), "%s: a path" % label)
	var command: MoveCommand = TurnHelper.move(state, id, path)
	assert_eq(command.validate(state), "", "%s: MoveCommand accepts %s" % [label, str(path)])
	assert_almost_eq(command.cost, field.cost_to(target), 0.0001, "%s: same cost" % label)
	return command


func test_platform_by_the_ramp_and_by_the_wall_at_different_costs() -> void:
	# Ramp x 5..11 rising to 2", platform x 11..17, z 11..17.
	_piece(Vector2(8, 14), Vector3(6, 2, 3), TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	_piece(Vector2(14, 14), Vector3(6, 2, 6))
	var id: int = _place(Vector3(8, 0, 19), 32, 12.0)
	var field: ReachField = ReachField.new(state, id)
	# Just inside the platform's south edge: climbing the wall is the cheap way.
	var by_wall: Vector3 = Vector3(12, 2, 16.5)
	assert_true(field.is_reachable(by_wall))
	var climb: MoveCommand = _assert_valid(field, id, by_wall, "by the wall")
	assert_true(_kinds(field, id, climb.waypoints).has(Transitions.Kind.OPEN_CLIMB))
	# On the ramp: from here the cheapest way is up its low side.
	var on_ramp: Vector3 = Vector3(9.5, 1.5, 14)
	assert_true(field.is_reachable(on_ramp))
	var ramp_walk: MoveCommand = _assert_valid(field, id, on_ramp, "onto the ramp")
	# Climbing onto the ramp side halfway up (1") is allowed, so the cheapest
	# route may do that; it is still cheaper than going round to its foot.
	assert_lt(ramp_walk.cost, 12.0)
	# From the far side of the ramp foot, the ramp is the way: the cost is
	# straight to the foot then along the slope.
	state = GameState.new(1)
	_piece(Vector2(8, 14), Vector3(6, 2, 3), TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP)
	_piece(Vector2(14, 14), Vector3(6, 2, 6))
	var walker: int = _place(Vector3(2, 0, 14), 32, 11.0)
	field = ReachField.new(state, walker)
	var top: Vector3 = Vector3(12, 2, 14)
	var walk: MoveCommand = _assert_valid(field, walker, top, "ramp then platform")
	assert_almost_eq(walk.cost, 3.0 + sqrt(36.0 + 4.0) + 1.0, 0.01)
	assert_false(_kinds(field, walker, walk.waypoints).has(Transitions.Kind.OPEN_CLIMB))


func test_four_inch_block_top_is_never_reachable() -> void:
	var id: int = _model_at(Vector3(6, 0, 30), 32, 12.0)
	var field: ReachField = ReachField.new(state, id)
	var block: int = _surface_of_piece(field, Vector2(6, 26))
	assert_ne(block, -1)
	var near: int = 0
	for k: int in field.state_count():
		if field.state_surface(k) == block:
			assert_eq(field.state_cost(k), INF, "block top state %s reached" % str(field.state_position(k)))
			near += 1
	assert_gt(near, 50, "the block's top is in the field")
	assert_false(field.is_reachable(Vector3(6, 4, 26)))


func test_sheer_wall_top_is_not_reachable_without_a_roll() -> void:
	var id: int = _model_at(Vector3(14, 0, 29), 32, 8.0)
	var field: ReachField = ReachField.new(state, id)
	assert_false(field.is_reachable(Vector3(14, 2, 26)))
	# But the far side is reachable by going round it.
	assert_true(field.is_reachable(Vector3(17, 0, 24)))


func test_tower_top_only_by_the_ladder_face() -> void:
	# Tower x 22.5..25.5, z 24.5..27.5; the ladder on its south face.
	var id: int = _model_at(Vector3(24, 0, 30), 32, 8.0)
	var field: ReachField = ReachField.new(state, id)
	var top: Vector3 = Vector3(24, 4, 26)
	assert_true(field.is_reachable(top))
	var up: MoveCommand = _assert_valid(field, id, top, "up the ladder")
	assert_true(_kinds(field, id, up.waypoints).has(Transitions.Kind.LADDER_UP))
	# From the north side, with plenty of movement, still only by the ladder.
	id = _model_at(Vector3(24, 0, 21.5), 32, 14.0)
	field = ReachField.new(state, id)
	var tower: int = _surface_of_piece(field, Vector2(24, 26))
	var checked: int = 0
	for k: int in range(0, field.state_count(), 3):
		if field.state_surface(k) != tower or not field.is_state_reachable(k):
			continue
		var command: MoveCommand = _assert_valid(field, id, field.state_position(k), "tower top")
		assert_true(_kinds(field, id, command.waypoints).has(Transitions.Kind.LADDER_UP))
		checked += 1
	assert_gt(checked, 10)


func test_down_from_the_tower_only_by_the_ladder_face() -> void:
	var id: int = _model_at(Vector3(24, 4, 25.5), 32, 10.0)
	var field: ReachField = ReachField.new(state, id)
	var checked: int = 0
	for k: int in range(0, field.state_count(), 2):
		if field.state_surface(k) != HeightField.TABLE or not field.is_state_reachable(k):
			continue
		var command: MoveCommand = _assert_valid(field, id, field.state_position(k), "down")
		assert_true(_kinds(field, id, command.waypoints).has(Transitions.Kind.LADDER_DOWN))
		checked += 1
	assert_gt(checked, 50)
	# North of the tower is 4" straight down: not without a roll, so only round.
	var north: Vector3 = Vector3(24, 0, 23.8)
	if field.is_reachable(north):
		var command: MoveCommand = _assert_valid(field, id, north, "north")
		assert_true(_kinds(field, id, command.waypoints).has(Transitions.Kind.LADDER_DOWN))


func test_a_corner_is_a_route_not_a_destination() -> void:
	# A 2" box x 10..14, z 10..14. The model is out from its south-east corner.
	_piece(Vector2(12, 12), Vector3(4, 2, 4))
	var id: int = _place(Vector3(16, 0, 16), 32, 8.0)
	var field: ReachField = ReachField.new(state, id)
	var corner: Vector3 = Vector3(14, 2, 14)
	assert_false(field.is_reachable(corner), "a quarter of the base on the corner: cannot stop")
	# On the diagonal, beyond the corner: the straight way climbs at the corner.
	var target: Vector3 = Vector3(12.8, 2, 12.8)
	var command: MoveCommand = _assert_valid(field, id, target, "over the corner")
	var through_corner: bool = false
	for point: Vector3 in command.waypoints:
		if point.distance_to(corner) < 0.01:
			through_corner = true
	assert_true(through_corner, "climbs at the corner: %s" % str(command.waypoints))
	# Straight-line plan distance plus the 2" climb.
	var straight: float = Vector2(16, 16).distance_to(Vector2(12.8, 12.8))
	assert_almost_eq(command.cost, straight + 2.0, 0.01)


func test_under_the_bridge_and_on_it_are_separate_destinations() -> void:
	var id: int = _model_at(Vector3(29, 0, 42.5), 32, 14.0)
	var field: ReachField = ReachField.new(state, id)
	var under: Vector3 = Vector3(33, 0, 38)
	var over: Vector3 = Vector3(33, 3.5, 38)
	assert_true(field.is_reachable(under))
	assert_true(field.is_reachable(over))
	var low: MoveCommand = _assert_valid(field, id, under, "under")
	var high: MoveCommand = _assert_valid(field, id, over, "over")
	assert_almost_eq(low.waypoints[low.waypoints.size() - 1].y, 0.0, 0.0001)
	assert_almost_eq(high.waypoints[high.waypoints.size() - 1].y, 3.5, 0.0001)
	assert_lt(low.cost, high.cost)
	# Two states at the node under the deck.
	var surfaces: Array[int] = []
	for k: int in field.state_count():
		if Vector2(field.state_position(k).x, field.state_position(k).z).distance_to(Vector2(33, 38)) < 0.13:
			surfaces.append(field.state_surface(k))
	assert_eq(surfaces.size(), 2)


func test_snapping_picks_the_floor_the_cursor_is_on() -> void:
	var id: int = _model_at(Vector3(29, 0, 42.5), 32, 14.0)
	var field: ReachField = ReachField.new(state, id)
	var r: float = field.base_radius()
	var on_deck: Variant = field.closest_destination(Vector3(33, 3.5, 38), r)
	var on_table: Variant = field.closest_destination(Vector3(33, 0, 38), r)
	assert_not_null(on_deck)
	assert_not_null(on_table)
	assert_almost_eq((on_deck as Vector3).y, 3.5, 0.0001)
	assert_almost_eq((on_table as Vector3).y, 0.0, 0.0001)
	# A cursor just past the platform's edge on its top snaps back onto the top.
	var climber: int = _model_at(Vector3(15, 2, 15), 25, 5.0)
	field = ReachField.new(state, climber)
	var off_edge: Variant = field.closest_destination(Vector3(17.2, 2, 15), field.base_radius())
	assert_not_null(off_edge)
	assert_almost_eq((off_edge as Vector3).y, 2.0, 0.0001)
	assert_almost_eq((off_edge as Vector3).x, 17.0, 0.01, "on the ledge: half the base supported")


func test_sandbags_crossed_for_free_crate_stop_pays_its_height() -> void:
	var id: int = _model_at(Vector3(7, 0, 41), 25, 6.0)
	var field: ReachField = ReachField.new(state, id)
	var beyond: Vector3 = Vector3(7, 0, 35.5)
	var across: MoveCommand = _assert_valid(field, id, beyond, "over the sandbags")
	assert_almost_eq(across.cost, 5.5, 0.01, "straight over, nothing extra")
	id = _model_at(Vector3(15, 0, 42), 40, 6.0)
	field = ReachField.new(state, id)
	var crate: Vector3 = Vector3(15, 1, 38.5)
	var stop: MoveCommand = _assert_valid(field, id, crate, "onto the crate")
	assert_almost_eq(field.surcharge_at(crate), 1.0, 0.0001)
	assert_almost_eq(stop.cost, 3.5 + 1.0, 0.01)
	# The small crate can be crossed but not stopped on.
	assert_false(field.is_reachable(Vector3(19.5, 1, 38)))


func test_beam_crossed_not_stopped_on() -> void:
	var id: int = _model_at(Vector3(16, 2, 14), 32, 8.0)
	var field: ReachField = ReachField.new(state, id)
	assert_false(field.is_reachable(Vector3(20, 2, 14)))
	var over: Vector3 = Vector3(24, 2, 14)
	var command: MoveCommand = _assert_valid(field, id, over, "along the beam")
	assert_almost_eq(command.cost, 8.0, 0.01, "straight along it")


func test_hop_down_from_the_platform() -> void:
	var id: int = _model_at(Vector3(15, 2, 15), 25, 5.0)
	var field: ReachField = ReachField.new(state, id)
	var below: Vector3 = Vector3(15, 0, 19)
	var command: MoveCommand = _assert_valid(field, id, below, "hop down")
	assert_true(_kinds(field, id, command.waypoints).has(Transitions.Kind.HOP_DOWN))
	assert_almost_eq(command.cost, 4.0, 0.01, "a free hop: only the distance on the table plane")


func test_consistency_on_the_test_table() -> void:
	_test_table()
	var total_paths: int = 0
	var started: int = Time.get_ticks_usec()
	var fields: int = 0
	for model: ModelState in state.models:
		var field: ReachField = ReachField.new(state, model.id)
		fields += 1
		var stride: int = maxi(field.state_count() / 400, 1)
		for k: int in range(0, field.state_count(), stride):
			if not field.is_state_reachable(k):
				continue
			var target: Vector3 = field.state_position(k)
			var path: Array[Vector3] = field.path_to(target)
			var command: MoveCommand = TurnHelper.move(state, model.id, path)
			assert_eq(command.validate(state), "", "model %d to %s via %s" % [model.id, str(target), str(path)])
			assert_almost_eq(command.cost, field.cost_to(target), 0.0001)
			assert_true(command.cost <= model.movement + 0.0001)
			total_paths += 1
		# Off-grid points on whatever floors are there.
		for j: int in 300:
			var p: Vector2 = Vector2(
				model.position.x - 6.0 + fmod(j * 0.6180339 * 7.0, 12.0),
				model.position.z - 6.0 + fmod(j * 0.4142135 * 7.0, 12.0)
			)
			for s: int in field.field.surfaces_at(p):
				var target: Vector3 = Vector3(p.x, field.field.surface_height(s, p), p.y)
				if not field.is_reachable(target):
					continue
				var path: Array[Vector3] = field.path_to(target)
				assert_eq(TurnHelper.move(state, model.id, path).validate(state), "", "model %d to %s" % [model.id, str(target)])
				total_paths += 1
	gut.p("validated %d paths over %d fields in %.0f ms" % [total_paths, fields, (Time.get_ticks_usec() - started) / 1000.0])
	assert_gt(total_paths, 1000)


func test_test_table_build_time() -> void:
	_test_table()
	for model: ModelState in state.models:
		var started: int = Time.get_ticks_usec()
		var field: ReachField = ReachField.new(state, model.id)
		gut.p("model %d (%d mm, %.0f\"): %d states, %.1f ms" % [
			model.id, model.base_mm, model.movement, field.state_count(),
			(Time.get_ticks_usec() - started) / 1000.0
		])
	pass_test("timing only")


func test_sandbag_row_is_one_area_and_one_straight_walk() -> void:
	var id: int = _model_at(Vector3(4.6, 0.5, 38), 25, 6.0)
	var field: ReachField = ReachField.new(state, id)
	for x: float in [6.0, 8.0, 7.0, 9.4]:
		assert_true(field.is_reachable(Vector3(x, 0.5, 38)), "on the row at x = %.1f" % x)
	var along: MoveCommand = _assert_valid(field, id, Vector3(9.4, 0.5, 38), "along the row")
	assert_eq(along.waypoints.size(), 1, "one straight segment across the seams: %s" % str(along.waypoints))
	assert_almost_eq(along.cost, 4.8, 0.0001)
	var row_layers: int = 0
	for layer: ReachField.Layer in field.contour_layers():
		if field.field.surface_height(layer.surface, Vector2(7, 38)) > 0.25:
			row_layers += 1
	assert_eq(row_layers, 1, "one layer for the whole row")
