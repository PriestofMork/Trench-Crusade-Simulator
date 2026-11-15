extends GutTest

var state: GameState


func before_each() -> void:
	state = GameState.new(1)


func test_table_defaults_to_48_by_48() -> void:
	assert_eq(state.table_width, 48.0)
	assert_eq(state.table_depth, 48.0)


func test_accepts_valid_placement() -> void:
	var command: PlaceModelCommand = PlaceModelCommand.new(1, Vector3(10, 0, 10), 32)
	assert_eq(state.execute(command), "")
	assert_eq(state.models.size(), 1)
	var model: ModelState = state.get_model(command.placed_model_id)
	assert_not_null(model)
	assert_eq(model.player, 1)
	assert_eq(model.position, Vector3(10, 0, 10))
	assert_eq(model.base_mm, 32)


func test_placed_models_get_distinct_ids() -> void:
	var a: PlaceModelCommand = PlaceModelCommand.new(0, Vector3(5, 0, 5), 25)
	var b: PlaceModelCommand = PlaceModelCommand.new(0, Vector3(10, 0, 5), 25)
	state.execute(a)
	state.execute(b)
	assert_ne(a.placed_model_id, b.placed_model_id)


func test_rejects_overlap() -> void:
	state.execute(PlaceModelCommand.new(0, Vector3(10, 0, 10), 32))
	# 32 mm bases: radius ~0.63". Centres 1" apart overlap.
	var command: PlaceModelCommand = PlaceModelCommand.new(1, Vector3(11, 0, 10), 32)
	assert_ne(state.execute(command), "")
	assert_eq(state.models.size(), 1)


func test_accepts_touching_bases() -> void:
	state.execute(PlaceModelCommand.new(0, Vector3(10, 0, 10), 32))
	var apart: float = BaseSizes.mm_to_inches(32)
	var command: PlaceModelCommand = PlaceModelCommand.new(1, Vector3(10 + apart, 0, 10), 32)
	assert_eq(state.execute(command), "")


func test_rejects_off_table() -> void:
	var cases: Array[Vector3] = [
		Vector3(-5, 0, 10),
		Vector3(60, 0, 10),
		Vector3(10, 0, -5),
		Vector3(10, 0, 60),
	]
	for pos: Vector3 in cases:
		assert_ne(state.execute(PlaceModelCommand.new(0, pos, 32)), "", str(pos))
	assert_eq(state.models.size(), 0)


func test_rejects_base_hanging_over_edge() -> void:
	# Centre on the table, but a 50 mm base (radius ~0.98") reaches past x = 0.
	assert_ne(state.execute(PlaceModelCommand.new(0, Vector3(0.5, 0, 10), 50)), "")


func test_off_table_uses_state_table_size() -> void:
	var small: GameState = GameState.new(1, 24.0, 24.0)
	assert_ne(small.execute(PlaceModelCommand.new(0, Vector3(30, 0, 10), 32)), "")
	assert_eq(state.execute(PlaceModelCommand.new(0, Vector3(30, 0, 10), 32)), "")


func test_rejects_unknown_base_size() -> void:
	assert_ne(state.execute(PlaceModelCommand.new(0, Vector3(10, 0, 10), 28)), "")


func test_rejects_invalid_player() -> void:
	assert_ne(state.execute(PlaceModelCommand.new(2, Vector3(10, 0, 10), 32)), "")
