extends GutTest

var state: GameState


func before_each() -> void:
	state = GameState.new(1)


func _place(player: int, pos: Vector3, base_mm: int, movement: float = 6.0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, base_mm, movement)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


func _terrain(center: Vector2, size: Vector3, rotation: float = 0.0) -> void:
	var command: PlaceTerrainCommand = PlaceTerrainCommand.new(
		Vector3(center.x, size.y / 2.0, center.y), size, rotation
	)
	assert_eq(state.execute(command), "")


func test_start_is_a_node_and_reachable() -> void:
	var id: int = _place(0, Vector3(24.1, 0, 23.37), 32)
	var field: ReachField = ReachField.new(state, id)
	assert_true(field.is_reachable(Vector3(24.1, 0, 23.37)))
	assert_almost_eq(field.cost_to(Vector3(24.1, 0, 23.37)), 0.0, 0.0001)


func test_empty_table_is_close_to_a_disc_and_never_larger() -> void:
	var start: Vector3 = Vector3(24, 0, 24)
	var id: int = _place(0, start, 32, 6.0)
	var started: int = Time.get_ticks_usec()
	var field: ReachField = ReachField.new(state, id)
	gut.p("ReachField for 6\" on an empty table: %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	var in_disc: int = 0
	var reachable: int = 0
	for i: int in field.node_count():
		var d: float = field.node_position(i).distance_to(start)
		if d <= 6.0:
			in_disc += 1
		if field.is_node_reachable(i):
			reachable += 1
			assert_true(d <= 6.0 + 0.0001, "reachable node outside the disc at %.3f" % d)
	var ratio: float = float(reachable) / float(in_disc)
	gut.p("reachable nodes / nodes in the disc = %.4f" % ratio)
	assert_between(ratio, 0.95, 1.0)
	# Arbitrary points, not only nodes.
	assert_true(field.is_reachable(Vector3(29.9, 0, 24)))
	assert_false(field.is_reachable(Vector3(30.1, 0, 24)))
	assert_true(field.is_reachable(Vector3(24 + 4.2, 0, 24 + 4.2)))
	assert_false(field.is_reachable(Vector3(24 + 4.3, 0, 24 + 4.3)))
	assert_almost_eq(field.cost_to(Vector3(27, 0, 28)), 5.0, 0.0001)
	assert_eq(field.path_to(Vector3(27, 0, 28)), [Vector3(27, 0, 28)] as Array[Vector3])


func test_point_behind_wall_needs_way_around() -> void:
	# Wall from x = 20 to 28 at z = 20, half an inch thick.
	_terrain(Vector2(24, 20), Vector3(8, 2, 0.5))
	var target: Vector3 = Vector3(24, 0, 18)
	var short: int = _place(0, Vector3(24, 0, 22), 25, 6.0)
	var short_field: ReachField = ReachField.new(state, short)
	assert_false(short_field.is_reachable(target), "straight line is 4\" but through the wall")
	assert_eq(short_field.path_to(target).size(), 0)

	# The same wall and model, with enough movement to go round.
	state = GameState.new(1)
	_terrain(Vector2(24, 20), Vector3(8, 2, 0.5))
	var long: int = _place(0, Vector3(24, 0, 22), 25, 12.0)
	var long_field: ReachField = ReachField.new(state, long)
	assert_true(long_field.is_reachable(target))
	var cost: float = long_field.cost_to(target)
	# Around the end of the wall: about 2 * |(4.5, 2)| ~ 9.8".
	assert_between(cost, 9.5, 12.0)
	var path: Array[Vector3] = long_field.path_to(target)
	assert_gt(path.size(), 1, "the path bends round the wall")
	assert_eq(state.execute(MoveCommand.new(long, path)), "")
	assert_eq(state.get_model(long).position, target)


func test_nothing_reachable_within_one_inch_of_enemy() -> void:
	var id: int = _place(0, Vector3(24, 0, 24), 32, 6.0)
	_place(1, Vector3(27.5, 0, 24), 40)
	_place(1, Vector3(22, 0, 28), 25)
	var field: ReachField = ReachField.new(state, id)
	var r: float = BaseSizes.mm_to_inches(32) / 2.0
	var checked: int = 0
	for i: int in field.node_count():
		if not field.is_node_reachable(i):
			continue
		for enemy: ModelState in state.models:
			if enemy.player == 0:
				continue
			var edge: float = field.node_position(i).distance_to(enemy.position) - r - enemy.base_radius_inches()
			assert_true(edge >= 1.0 - 0.0001, "node %d is %.3f\" from an enemy" % [i, edge])
		checked += 1
	assert_gt(checked, 100)
	# Points between nodes too.
	for k: int in 400:
		var angle: float = k * 0.1
		var dist: float = fmod(k * 0.37, 6.0)
		var p: Vector3 = Vector3(24 + cos(angle) * dist, 0, 24 + sin(angle) * dist)
		if not field.is_reachable(p):
			continue
		for enemy: ModelState in state.models:
			if enemy.player == 0:
				continue
			var edge: float = p.distance_to(enemy.position) - r - enemy.base_radius_inches()
			assert_true(edge >= 1.0 - 0.0001)


func test_every_returned_path_is_accepted_by_move_command() -> void:
	_terrain(Vector2(20, 20), Vector3(6, 3, 1))
	_terrain(Vector2(27, 25), Vector3(2, 4, 5), 0.6)
	_terrain(Vector2(22, 29), Vector3(3, 2, 3), PI / 4.0)
	_terrain(Vector2(30, 18), Vector3(0.5, 3, 6), -0.3)
	var id: int = _place(0, Vector3(24, 0, 23), 40, 8.0)
	_place(0, Vector3(21, 0, 24), 32)
	_place(0, Vector3(25.5, 0, 20.5), 25)
	_place(1, Vector3(29, 0, 29), 50)
	_place(1, Vector3(17, 0, 25), 32)
	var started: int = Time.get_ticks_usec()
	var field: ReachField = ReachField.new(state, id)
	gut.p("ReachField for 8\" with terrain and models: %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))

	var tested: int = 0
	var bent: int = 0
	for i: int in range(0, field.node_count(), 3):
		if not field.is_node_reachable(i):
			continue
		var target: Vector3 = field.node_position(i)
		var path: Array[Vector3] = field.path_to(target)
		assert_false(path.is_empty())
		var command: MoveCommand = MoveCommand.new(id, path)
		var error: String = command.validate(state)
		assert_eq(error, "", "path to node %s" % str(target))
		var length: float = MoveCommand.path_length(state.get_model(id).position, path)
		assert_almost_eq(length, field.cost_to(target), 0.0001)
		assert_true(length <= field.node_cost(i) + 0.0001, "simplifying never lengthens the path")
		assert_true(length >= target.distance_to(state.get_model(id).position) - 0.0001)
		if path.size() > 1:
			bent += 1
		tested += 1
	gut.p("validated %d node paths, %d of them bend" % [tested, bent])
	assert_gt(tested, 300)
	assert_gt(bent, 20, "the terrain should force some paths to bend")

	# Off-grid points as well.
	var off_grid: int = 0
	for k: int in 2000:
		var p: Vector3 = Vector3(16.0 + fmod(k * 0.6180339, 16.0), 0, 15.0 + fmod(k * 0.4142135, 16.0))
		if not field.is_reachable(p):
			continue
		var path: Array[Vector3] = field.path_to(p)
		assert_eq(MoveCommand.new(id, path).validate(state), "", "path to %s" % str(p))
		assert_true(path[path.size() - 1].is_equal_approx(p))
		off_grid += 1
	assert_gt(off_grid, 200)


func test_field_after_a_move_shows_what_is_left() -> void:
	var id: int = _place(0, Vector3(24, 0, 24), 32, 6.0)
	var before: ReachField = ReachField.new(state, id)
	var path: Array[Vector3] = before.path_to(Vector3(28, 0, 24))
	assert_eq(state.execute(MoveCommand.new(id, path)), "")
	var after: ReachField = ReachField.new(state, id)
	assert_almost_eq(after.movement_left, 2.0, 0.0001)
	assert_true(after.is_reachable(Vector3(29.9, 0, 24)))
	assert_false(after.is_reachable(Vector3(30.1, 0, 24)))
	assert_false(after.is_reachable(Vector3(24, 0, 24)), "the old start is 4\" away now")
	var reachable: int = 0
	for i: int in after.node_count():
		if after.is_node_reachable(i):
			reachable += 1
	assert_lt(reachable, 260, "about pi * 2^2 / 0.25^2 ~ 201 nodes")


func test_model_with_no_movement_left_reaches_only_its_spot() -> void:
	var id: int = _place(0, Vector3(24, 0, 24), 32, 6.0)
	state.execute(MoveCommand.new(id, [Vector3(30, 0, 24)]))
	var field: ReachField = ReachField.new(state, id)
	assert_true(field.is_reachable(Vector3(30, 0, 24)))
	assert_false(field.is_reachable(Vector3(30.3, 0, 24)))


func test_contour_values_are_negative_inside_and_positive_outside() -> void:
	var id: int = _place(0, Vector3(24, 0, 24), 32, 4.0)
	_terrain(Vector2(26, 24), Vector3(1, 2, 2))
	var field: ReachField = ReachField.new(state, id)
	var values: PackedFloat32Array = field.contour_values()
	assert_eq(values.size(), field.node_count())
	for i: int in field.node_count():
		if field.is_node_reachable(i):
			assert_true(values[i] <= 0.0001, "reachable node %d has %f" % [i, values[i]])
		elif values[i] <= 0.0:
			# Only nodes just past the movement limit may round to the edge.
			assert_almost_eq(field.node_cost(i), field.movement_left, 0.001)


## A line of touching friendly 25 mm bases across the table at x = 26.
func _friendly_line() -> void:
	var d: float = BaseSizes.mm_to_inches(25)
	var z: float = 4.0
	while z < 44.0:
		_place(0, Vector3(26, 0, z), 25)
		z += d


func test_friendly_line_no_longer_blocks_the_spot_behind_it() -> void:
	var id: int = _place(0, Vector3(24, 0, 24), 32, 4.0)
	_friendly_line()
	# Before brief 003 the line was a wall: going round is far more than 4".
	var target: Vector3 = Vector3(27.9, 0, 24)
	var field: ReachField = ReachField.new(state, id)
	assert_true(field.is_reachable(target))
	assert_almost_eq(field.cost_to(target), 3.9, 0.0001)
	var path: Array[Vector3] = field.path_to(target)
	assert_eq(MoveCommand.new(id, path).validate(state), "")
	# But not stopping on the line itself.
	assert_false(field.is_reachable(Vector3(26, 0, 24)))
	assert_false(field.is_reachable(Vector3(26.5, 0, 24.3)))


func test_enemy_line_still_blocks() -> void:
	var id: int = _place(0, Vector3(20, 0, 24), 32, 6.0)
	var d: float = BaseSizes.mm_to_inches(25)
	var z: float = 4.0
	while z < 44.0:
		_place(1, Vector3(23, 0, z), 25)
		z += d
	var field: ReachField = ReachField.new(state, id)
	assert_false(field.is_reachable(Vector3(25.9, 0, 24)))


func test_no_destination_overlaps_any_base() -> void:
	var id: int = _place(0, Vector3(24, 0, 24), 32, 5.0)
	_friendly_line()
	_place(0, Vector3(22, 0, 26), 40)
	_place(0, Vector3(23.5, 0, 21), 50)
	_place(1, Vector3(20, 0, 20), 32)
	var field: ReachField = ReachField.new(state, id)
	var r: float = BaseSizes.mm_to_inches(32) / 2.0
	var checked: int = 0
	var points: Array[Vector3] = []
	for i: int in field.node_count():
		if field.is_node_reachable(i):
			points.append(field.node_position(i))
	for k: int in 3000:
		var p: Vector3 = Vector3(19.0 + fmod(k * 0.6180339, 10.0), 0, 19.0 + fmod(k * 0.4142135, 10.0))
		if field.is_reachable(p):
			points.append(p)
	for p: Vector3 in points:
		for other: ModelState in state.models:
			if other.id == id:
				continue
			var gap: float = p.distance_to(other.position) - r - other.base_radius_inches()
			assert_true(gap >= -0.0001, "destination %s overlaps model %d by %.4f" % [str(p), other.id, -gap])
		checked += 1
	gut.p("checked %d destinations" % checked)
	assert_gt(checked, 500)


func test_paths_through_friends_are_accepted_by_move_command() -> void:
	_terrain(Vector2(28, 20), Vector3(1, 2, 5))
	var id: int = _place(0, Vector3(24, 0, 24), 40, 7.0)
	_friendly_line()
	_place(0, Vector3(22, 0, 26.5), 40)
	_place(0, Vector3(24, 0, 21.5), 50)
	_place(1, Vector3(29, 0, 28), 32)
	var field: ReachField = ReachField.new(state, id)
	var tested: int = 0
	var through: int = 0
	for i: int in range(0, field.node_count(), 2):
		if not field.is_node_reachable(i):
			continue
		var target: Vector3 = field.node_position(i)
		var path: Array[Vector3] = field.path_to(target)
		assert_eq(MoveCommand.new(id, path).validate(state), "", "path to node %s" % str(target))
		if target.x > 26.0:
			through += 1
		tested += 1
	for k: int in 1500:
		var p: Vector3 = Vector3(17.0 + fmod(k * 0.6180339, 14.0), 0, 17.0 + fmod(k * 0.4142135, 14.0))
		if not field.is_reachable(p):
			continue
		assert_eq(MoveCommand.new(id, field.path_to(p)).validate(state), "", "path to %s" % str(p))
		tested += 1
	gut.p("validated %d paths, %d of them to nodes past the friendly line" % [tested, through])
	assert_gt(tested, 500)
	assert_gt(through, 50)


func test_closest_destination_inside_is_the_point_itself() -> void:
	var id: int = _place(0, Vector3(24, 0, 24), 32, 6.0)
	var field: ReachField = ReachField.new(state, id)
	assert_eq(field.closest_destination(Vector3(27, 0, 25), 0.63), Vector3(27, 0, 25))


func test_closest_destination_just_outside_snaps_to_the_closest_valid_centre() -> void:
	var start: Vector3 = Vector3(24, 0, 24)
	var id: int = _place(0, start, 32, 6.0)
	var field: ReachField = ReachField.new(state, id)
	var r: float = field.base_radius()
	for angle: float in [0.0, 0.5, 1.1, 2.3, 4.0]:
		var direction: Vector3 = Vector3(cos(angle), 0, sin(angle))
		var cursor: Vector3 = start + direction * 6.4
		var snapped: Variant = field.closest_destination(cursor, r)
		assert_not_null(snapped, "angle %.1f" % angle)
		var point: Vector3 = snapped
		# The closest valid centre is on the 6" circle, towards the cursor.
		assert_almost_eq(point.distance_to(cursor), 0.4, 0.01, "angle %.1f" % angle)
		assert_true(point.distance_to(start + direction * 6.0) < 0.1, "angle %.1f: %s" % [angle, str(point)])
		assert_true(field.is_reachable(point))
		assert_eq(MoveCommand.new(id, field.path_to(point)).validate(state), "")
	# Further out than a base radius: nothing.
	assert_null(field.closest_destination(start + Vector3(6.0 + r + 0.05, 0, 0), r))


func test_closest_destination_next_to_a_friend_and_a_wall() -> void:
	var id: int = _place(0, Vector3(24, 0, 24), 32, 6.0)
	var friend: int = _place(0, Vector3(27, 0, 24), 32)
	_terrain(Vector2(24, 28), Vector3(6, 2, 1))  # Faces at z = 27.5 and 28.5.
	var field: ReachField = ReachField.new(state, id)
	var r: float = field.base_radius()
	# Cursor where the base would overlap the friend: the base ends up touching it.
	var cursor: Vector3 = Vector3(26.15, 0, 24.1)
	var snapped: Variant = field.closest_destination(cursor, r)
	assert_not_null(snapped)
	var point: Vector3 = snapped
	assert_almost_eq(point.distance_to(state.get_model(friend).position), 2 * r, 0.01)
	assert_true(field.is_reachable(point))
	assert_eq(MoveCommand.new(id, field.path_to(point)).validate(state), "")
	# Cursor right at the wall face: the base touches the wall.
	var wall_cursor: Vector3 = Vector3(23, 0, 27.45)
	var at_wall: Variant = field.closest_destination(wall_cursor, r)
	assert_not_null(at_wall)
	assert_almost_eq((at_wall as Vector3).z, 27.5 - r, 0.01)
	assert_almost_eq((at_wall as Vector3).x, 23.0, 0.05)
	assert_eq(MoveCommand.new(id, field.path_to(at_wall)).validate(state), "")
