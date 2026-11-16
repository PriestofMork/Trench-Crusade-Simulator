extends GutTest
## Ruling 2 of brief 008: the model view is drawn with the same tilt as the
## sight cylinder core tests with.

var state: GameState


func before_each() -> void:
	state = GameState.new(1)
	assert_eq(state.execute(PlaceTerrainCommand.new(
		Vector2(24, 24), Vector3(4, 1.5, 3), 0.0, 0.0, TerrainPiece.Tag.NONE, TerrainPiece.Shape.RAMP
	)), "")


func _view_for(position: Vector3) -> Array:
	var command: PlaceModelCommand = PlaceModelCommand.new(1, position, 32, 6.0)
	assert_eq(state.execute(command), "")
	var model: ModelState = state.get_model(command.placed_model_id)
	var view: ModelView = autofree(ModelView.new())
	view.state = state
	view.setup(model)
	return [model, view]


func test_the_view_on_a_ramp_tilts_as_its_sight_cylinder() -> void:
	var made: Array = _view_for(Vector3(24, 0.75, 24))
	var model: ModelState = made[0]
	var view: ModelView = made[1]
	var cylinder: SightCylinder = SightCylinder.for_model(state, model)
	assert_true(cylinder.axis.dot(Vector3.UP) < 0.99, "the sight cylinder is tilted")
	assert_almost_eq(view.drawn_up().distance_to(cylinder.axis), 0.0, 1e-6, "drawn with the sight tilt")
	assert_almost_eq(view.transform.basis.y.normalized().distance_to(cylinder.axis), 0.0, 1e-5, "the mesh's up is the axis")
	var drawn_centre: Vector3 = view.transform.origin
	var sight_centre: Vector3 = cylinder.base + cylinder.axis * (cylinder.height / 2.0)
	assert_almost_eq(drawn_centre.distance_to(sight_centre), 0.0, 1e-5, "and centred where the sight cylinder is")


func test_the_view_on_level_ground_is_upright() -> void:
	var made: Array = _view_for(Vector3(10, 0, 10))
	var view: ModelView = made[1]
	assert_eq(view.drawn_up(), Vector3.UP)
	assert_eq(SightCylinder.for_model(state, made[0]).axis, Vector3.UP)
