extends GutTest
## Line of sight between model cylinders (brief 008): terrain, models and the
## tabletop block; tilt on ramps; height; see-through pieces; symmetry; Down
## and Out of Action.

const R25: float = 0.49212598
const R32: float = 0.62992126

var state: GameState


func before_each() -> void:
	state = GameState.new(3)


func _place(player: int, pos: Vector3, base_mm: int = 32) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, base_mm, 6.0)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _piece(
	center: Vector2, size: Vector3, base: float = 0.0, shape: TerrainPiece.Shape = TerrainPiece.Shape.BOX,
	blocks_sight: bool = true, turn_degrees: float = 0.0
) -> void:
	assert_eq(state.execute(PlaceTerrainCommand.new(
		center, size, deg_to_rad(turn_degrees), base, TerrainPiece.Tag.NONE, shape, blocks_sight
	)), "")


func _sees(a: int, b: int) -> bool:
	return state.rules.sight.can_see(state, state.get_model(a), state.get_model(b))


## Sight both ways, which must agree.
func _mutual(a: int, b: int) -> bool:
	var there: bool = _sees(a, b)
	assert_eq(_sees(b, a), there, "%d -> %d and back agree" % [a, b])
	return there


func test_the_standard_rules_use_real_line_of_sight() -> void:
	assert_true(state.rules.sight is LineOfSight)


func test_open_ground() -> void:
	var a: int = _place(0, Vector3(10, 0, 24))
	var b: int = _place(1, Vector3(30, 0, 24))
	assert_true(_mutual(a, b))
	var result: SightResult = state.rules.sight.check(state, state.get_model(a), state.get_model(b))
	assert_true(result.visible)
	assert_almost_eq(result.from.distance_to(Vector3(10, 0, 24)), 0.0, 2.0, "the segment starts on the viewer")
	assert_almost_eq(result.to.distance_to(Vector3(30, 0, 24)), 0.0, 2.0, "and ends on the target")


func test_a_wall_taller_than_both_blocks() -> void:
	var a: int = _place(0, Vector3(10, 0, 24))
	var b: int = _place(1, Vector3(20, 0, 24))
	_piece(Vector2(15, 24), Vector3(0.5, 2.5, 6))
	assert_false(_mutual(a, b))
	assert_false(state.rules.sight.check(state, state.get_model(a), state.get_model(b)).visible)


func test_a_wall_lower_than_the_models_does_not_block() -> void:
	var a: int = _place(0, Vector3(10, 0, 24))
	var b: int = _place(1, Vector3(20, 0, 24))
	_piece(Vector2(15, 24), Vector3(0.5, 1.0, 6))
	assert_true(_mutual(a, b))
	var result: SightResult = state.rules.sight.check(state, state.get_model(a), state.get_model(b))
	assert_true(result.from.y > 1.0 or result.to.y > 1.0, "the line goes over the wall")


func test_a_model_in_between_blocks_and_moved_aside_does_not() -> void:
	for player: int in [0, 1]:
		before_each()
		var a: int = _place(0, Vector3(10, 0, 24), 25)
		var b: int = _place(1, Vector3(20, 0, 24), 25)
		var middle: int = _place(player, Vector3(15, 0, 24), 60)
		assert_false(_mutual(a, b), "a %s model in between blocks" % ("friendly" if player == 0 else "enemy"))
		state.get_model(middle).position = Vector3(15, 0, 24 + 1.18 + 0.05)
		assert_true(_mutual(a, b), "moved aside by more than its radius, it does not")


func test_a_sliver_of_the_target_is_enough() -> void:
	var a: int = _place(0, Vector3(10, 0, 24))
	var b: int = _place(1, Vector3(20, 0, 24))
	# A tall wall just in front of b hides all of it but 0.25" at its +z edge.
	var edge: float = 24 + R32 - 0.25
	_piece(Vector2(19, (10.0 + edge) / 2.0), Vector3(0.2, 4, edge - 10.0))
	assert_true(_mutual(a, b), "0.25\" showing is visible")
	var result: SightResult = state.rules.sight.check(state, state.get_model(a), state.get_model(b))
	assert_true(result.to.z > edge, "seen through the sliver")
	before_each()
	a = _place(0, Vector3(10, 0, 24))
	b = _place(1, Vector3(20, 0, 24))
	edge = 24 + R32 + 0.05
	_piece(Vector2(19, (10.0 + edge) / 2.0), Vector3(0.2, 4, edge - 10.0))
	assert_false(_mutual(a, b), "wholly behind it is not")


func test_a_sliver_over_the_top_is_enough() -> void:
	var a: int = _place(0, Vector3(10, 0, 24))
	var b: int = _place(1, Vector3(20, 0, 24))
	_piece(Vector2(19, 24), Vector3(0.2, 1.9 - 0.25, 8))
	assert_true(_mutual(a, b))


func test_a_model_on_a_ramp_is_tilted() -> void:
	_piece(Vector2(24, 24), Vector3(3, 2, 3), 0.0, TerrainPiece.Shape.RAMP)
	var on_ramp: int = _place(1, Vector3(24, 1, 24))
	var flat: int = _place(0, Vector3(24, 0, 14))
	var tilted: SightCylinder = SightCylinder.for_model(state, state.get_model(on_ramp))
	assert_almost_eq(tilted.axis.dot(Vector3(-2.0 / 3.0, 1, 0).normalized()), 1.0, 0.0001, "axis is the ramp's normal")
	assert_eq(SightCylinder.for_model(state, state.get_model(flat)).axis, Vector3.UP, "upright on the table")


## The ramp rises along +x, so a model on it leans towards -x.
func _ramp_case(wall_from_x: float, wall_to_x: float) -> Array[bool]:
	before_each()
	_piece(Vector2(24, 24), Vector3(3, 2, 3), 0.0, TerrainPiece.Shape.RAMP)
	var target: int = _place(1, Vector3(24, 1, 24))
	var viewer: int = _place(0, Vector3(24, 0, 12))
	_piece(Vector2((wall_from_x + wall_to_x) / 2.0, 22.2), Vector3(wall_to_x - wall_from_x, 6, 0.2))
	var t: ModelState = state.get_model(target)
	var v: SightCylinder = SightCylinder.for_model(state, state.get_model(viewer))
	var tilted: SightCylinder = SightCylinder.for_model(state, t)
	var upright: SightCylinder = SightCylinder.new(t.position, Vector3.UP, t.base_radius_inches(), t.height_inches(), t.id)
	var ignored: PackedInt32Array = PackedInt32Array([viewer, target])
	return [
		state.rules.sight.check_between(state, v, tilted, ignored).visible,
		state.rules.sight.check_between(state, v, upright, ignored).visible,
	]


func test_tilt_can_show_a_model_an_upright_cylinder_would_hide() -> void:
	# The wall hides x > 23.2: all of an upright cylinder, not the leaning top.
	var seen: Array[bool] = _ramp_case(23.2, 40.0)
	assert_true(seen[0], "the tilted cylinder leans out past the wall")
	assert_false(seen[1], "the upright one would be hidden")


func test_tilt_can_hide_a_model_an_upright_cylinder_would_show() -> void:
	# The wall hides x < 24.55: an upright cylinder shows its +x rim, the tilted one does not.
	var seen: Array[bool] = _ramp_case(8.0, 24.55)
	assert_false(seen[0], "the tilted cylinder has leant behind the wall")
	assert_true(seen[1], "the upright one would show its edge")


func test_from_a_raised_floor_over_the_edge_but_not_under_it() -> void:
	_piece(Vector2(24, 24), Vector3(6, 4, 6))
	var up: int = _place(0, Vector3(24, 4, 24), 25)
	var far_below: int = _place(1, Vector3(24, 0, 32), 25)
	var tucked: int = _place(1, Vector3(24, 0, 27 + R25 + 0.02), 25)
	assert_true(_mutual(up, far_below), "seen over the edge")
	assert_false(_mutual(up, tucked), "tucked directly under the edge")


func test_under_a_bridge_and_on_it_do_not_see_each_other() -> void:
	_piece(Vector2(24, 24), Vector3(8, 0.5, 8), 3.0)
	var under: int = _place(0, Vector3(24, 0, 24), 25)
	var on_top: int = _place(1, Vector3(24, 3.5, 24), 25)
	assert_false(_mutual(under, on_top))


func test_models_on_the_same_floor_see_each_other_low_down() -> void:
	# Both on a 2" box: its top must not hide their bottoms (ruling 6).
	_piece(Vector2(24, 24), Vector3(12, 2, 4))
	var a: int = _place(0, Vector3(20, 2, 24), 25)
	var b: int = _place(1, Vector3(28, 2, 24), 25)
	assert_true(_mutual(a, b))
	# Cylinders of no height: only their undersides, flat on the box top.
	var low_a: SightCylinder = SightCylinder.new(Vector3(20, 2, 24), Vector3.UP, R25, 0.0)
	var low_b: SightCylinder = SightCylinder.new(Vector3(28, 2, 24), Vector3.UP, R25, 0.0)
	assert_true(state.rules.sight.check_between(state, low_a, low_b, PackedInt32Array([a, b])).visible,
		"two bases flat on the same floor see each other along it")
	# The same on a ramp: the bases lie in its plane.
	before_each()
	_piece(Vector2(24, 24), Vector3(12, 3, 4), 0.0, TerrainPiece.Shape.RAMP)
	var up: SightCylinder = SightCylinder.at(state, Vector3(27, 2.25, 24), 25)
	var down: SightCylinder = SightCylinder.at(state, Vector3(21, 0.75, 24), 25)
	var flat_up: SightCylinder = SightCylinder.new(up.base, up.axis, R25, 0.0)
	var flat_down: SightCylinder = SightCylinder.new(down.base, down.axis, R25, 0.0)
	assert_true(state.rules.sight.check_between(state, flat_up, flat_down, PackedInt32Array()).visible,
		"two bases flat on the same ramp see each other along it")


func test_a_see_through_piece_does_not_block() -> void:
	var a: int = _place(0, Vector3(10, 0, 24))
	var b: int = _place(1, Vector3(20, 0, 24))
	_piece(Vector2(15, 24), Vector3(0.5, 4, 6), 0.0, TerrainPiece.Shape.BOX, false)
	assert_true(_mutual(a, b))
	assert_false(state.terrain[0].blocks_sight)


func test_blocks_sight_is_read_from_table_data() -> void:
	var data: Dictionary = {"terrain": [
		{"center": [10, 10], "size": [1, 1, 1]},
		{"center": [20, 10], "size": [1, 1, 1], "blocks_sight": false},
	]}
	for command: Command in TableSetup.commands(data):
		assert_eq(state.execute(command), "")
	assert_true(state.terrain[0].blocks_sight, "default true")
	assert_false(state.terrain[1].blocks_sight)


func test_sight_is_symmetric_over_varied_positions() -> void:
	_piece(Vector2(14, 14), Vector3(6, 2, 6))
	_piece(Vector2(8, 14), Vector3(6, 2, 3), 0.0, TerrainPiece.Shape.RAMP)
	_piece(Vector2(24, 20), Vector3(0.5, 2.0, 8))
	_piece(Vector2(30, 14), Vector3(6, 1.5, 3), 0.0, TerrainPiece.Shape.RAMP, true, 30.0)
	_piece(Vector2(20, 30), Vector3(8, 0.5, 4), 3.0)
	var ids: Array[int] = []
	ids.append(_place(0, Vector3(14, 2, 14), 25))
	ids.append(_place(1, Vector3(8, 1, 14), 32))
	ids.append(_place(0, Vector3(30, 0.75, 14), 40))
	ids.append(_place(1, Vector3(20, 0, 30), 25))
	ids.append(_place(0, Vector3(20, 3.5, 30.5), 25))
	ids.append(_place(1, Vector3(27, 0, 20.3), 50))
	ids.append(_place(0, Vector3(21, 0, 19.1), 32))
	ids.append(_place(1, Vector3(12.3, 0, 19.4), 60))
	ids.append(_place(0, Vector3(33, 0, 24), 32))
	ids.append(_place(1, Vector3(16.5, 0, 25.7), 25))
	var seen: int = 0
	var pairs: int = 0
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var a: ModelState = state.get_model(ids[i])
			var b: ModelState = state.get_model(ids[j])
			var there: SightResult = state.rules.sight.check(state, a, b)
			var back: SightResult = state.rules.sight.check(state, b, a)
			assert_eq(there.visible, back.visible, "%d and %d agree" % [a.id, b.id])
			if there.visible and back.visible:
				assert_eq(there.from, back.to, "the same segment, reversed")
				assert_eq(there.to, back.from)
				seen += 1
			pairs += 1
	assert_true(seen > 0 and seen < pairs, "a mix of seen and hidden pairs (%d of %d seen)" % [seen, pairs])
	# The shortcuts (probes, hidden proofs) give the same answer as trying
	# every pair of sample points against every blocker.
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var a: ModelState = state.get_model(ids[i])
			var b: ModelState = state.get_model(ids[j])
			assert_eq(state.rules.sight.can_see(state, a, b), _brute_force(a, b), "%d and %d as by brute force" % [a.id, b.id])


## Whether any pair of sample points has a clear segment, trying everything.
func _brute_force(a: ModelState, b: ModelState) -> bool:
	var ca: SightCylinder = SightCylinder.for_model(state, a)
	var cb: SightCylinder = SightCylinder.for_model(state, b)
	var others: Array[SightCylinder] = []
	for model: ModelState in state.models_on_table():
		if model.id != a.id and model.id != b.id:
			others.append(SightCylinder.for_model(state, model))
	for p: Vector3 in ca.sample_points():
		for q: Vector3 in cb.sample_points():
			var clear: bool = not SightGeometry.segment_blocked_by_table(p, q)
			for solid: SightGeometry.Solid in state.sight_terrain().solids:
				if clear and SightGeometry.segment_blocked_by_solid(p, q, solid):
					clear = false
			for c: SightCylinder in others:
				if clear and SightGeometry.segment_blocked_by_cylinder(p, q, c.base, c.axis, c.radius, c.height):
					clear = false
			if clear:
				return true
	return false


func test_a_down_model_keeps_its_cylinder() -> void:
	var a: int = _place(0, Vector3(10, 0, 24), 25)
	var b: int = _place(1, Vector3(20, 0, 24), 25)
	var middle: int = _place(1, Vector3(15, 0, 24), 60)
	state.get_model(middle).down = true
	assert_false(_mutual(a, b), "a Down model still blocks")
	state.get_model(middle).position = Vector3(15, 0, 30)
	state.get_model(a).down = true
	state.get_model(b).down = true
	assert_true(_mutual(a, b), "Down models still see and are seen")
	_piece(Vector2(15, 24), Vector3(0.2, 1.7 - 0.2, 8))
	assert_true(_mutual(a, b), "over a wall lower than their standing height, as if standing")


func test_out_of_action_models_neither_block_nor_are_seen() -> void:
	var a: int = _place(0, Vector3(10, 0, 24), 25)
	var b: int = _place(1, Vector3(20, 0, 24), 25)
	var middle: int = _place(1, Vector3(15, 0, 24), 60)
	state.get_model(middle).out_of_action = true
	assert_true(_mutual(a, b), "an Out of Action model does not block")
	assert_false(_sees(a, middle), "and cannot be seen")
	assert_false(_sees(middle, a), "and sees nothing")


func test_a_query_from_a_position_moves_nothing() -> void:
	var a: int = _place(0, Vector3(10, 0, 24))
	var b: int = _place(1, Vector3(20, 0, 24))
	_piece(Vector2(15, 24), Vector3(0.5, 3, 6))
	var model: ModelState = state.get_model(a)
	var from_there: SightCylinder = SightCylinder.at(state, Vector3(10, 0, 32), model.base_mm, a)
	var result: SightResult = state.rules.sight.check_between(
		state, from_there, SightCylinder.for_model(state, state.get_model(b)), PackedInt32Array([a, b])
	)
	assert_true(result.visible, "seen from round the wall's end")
	assert_eq(model.position, Vector3(10, 0, 24), "the model has not moved")
	assert_false(_sees(a, b), "and from where it stands it still cannot see")


func test_sample_points_are_on_the_cylinder() -> void:
	var cylinder: SightCylinder = SightCylinder.new(Vector3(5, 1, 5), Vector3(-1, 2, 0), 0.6, 2.0)
	var points: PackedVector3Array = cylinder.sample_points()
	assert_eq(points.size(), SightCylinder.AXIS_LEVELS.size() + SightCylinder.RING_LEVELS.size() * SightCylinder.RING_POINTS)
	for p: Vector3 in points:
		var rel: Vector3 = p - cylinder.base
		var along: float = rel.dot(cylinder.axis)
		var across: float = (rel - cylinder.axis * along).length()
		assert_true(along >= -0.0001 and along <= 2.0001, "within the height")
		assert_true(across <= 0.6001, "within the radius")


func test_the_sight_block_on_the_test_table() -> void:
	assert_true(TableSetup.apply_file(state, "res://data/tables/height_test_table.json").is_empty())
	var viewer: ModelState = state.get_model(27)
	var expected: Dictionary[int, bool] = {28: false, 29: true, 30: false, 31: true, 32: true, 33: true}
	for id: int in expected:
		assert_eq(state.rules.sight.can_see(state, viewer, state.get_model(id)), expected[id], "27 sees %d" % id)
	for model: ModelState in state.models:
		if model.player != viewer.player:
			assert_eq(state.rules.sight.can_see(state, viewer, model), _brute_force(viewer, model), "27 and %d as by brute force" % model.id)
	assert_true(SightCylinder.for_model(state, state.get_model(33)).axis.y < 0.99, "33 on the ramp is tilted")
