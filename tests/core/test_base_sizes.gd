extends GutTest


func test_mm_to_inches() -> void:
	assert_almost_eq(BaseSizes.mm_to_inches(25.4), 1.0, 0.0001)
	assert_almost_eq(BaseSizes.mm_to_inches(32.0), 1.2598, 0.0001)
	assert_almost_eq(BaseSizes.mm_to_inches(50.0), 1.9685, 0.0001)


func test_model_exposes_base_in_inches() -> void:
	var model: ModelState = ModelState.new(1, 0, Vector3.ZERO, 40)
	assert_eq(model.base_mm, 40)
	assert_almost_eq(model.base_diameter_inches(), 40.0 / 25.4, 0.0001)
	assert_almost_eq(model.base_radius_inches(), 20.0 / 25.4, 0.0001)


func test_height_for_each_base_size() -> void:
	assert_almost_eq(BaseSizes.height_inches(25), 1.7, 0.0001)
	assert_almost_eq(BaseSizes.height_inches(32), 1.9, 0.0001)
	assert_almost_eq(BaseSizes.height_inches(40), 2.2, 0.0001)
	assert_almost_eq(BaseSizes.height_inches(50), 2.6, 0.0001)
	assert_almost_eq(BaseSizes.height_inches(60), 3.0, 0.0001)


func test_unknown_base_size_fails() -> void:
	assert_false(BaseSizes.is_known(28))
	assert_eq(BaseSizes.height_inches(28), -1.0)
	assert_push_error("Unknown base size")
