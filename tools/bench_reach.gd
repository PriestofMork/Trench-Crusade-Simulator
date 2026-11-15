extends SceneTree
## Times the reach field for every model on the test table, outside GUT:
## godot --headless --path . -s tools/bench_reach.gd


func _init() -> void:
	var state: GameState = GameState.new(1)
	var errors: PackedStringArray = TableSetup.apply_file(state, "res://data/tables/height_test_table.json")
	if not errors.is_empty():
		push_error(str(errors))
	state.height_field()
	var total: float = 0.0
	for round_index: int in 2:
		total = 0.0
		for model: ModelState in state.models:
			var started: int = Time.get_ticks_usec()
			var field: ReachField = ReachField.new(state, model.id)
			var layers: Array[ReachField.Layer] = field.contour_layers()
			var ms: float = (Time.get_ticks_usec() - started) / 1000.0
			total += ms
			if round_index == 1:
				print("model %2d (%d mm, %.0f\"): %5d states, %6.1f ms total (field %s, %d layers)" % [
					model.id, model.base_mm, model.movement, field.state_count(), ms, str(field.get("timings")), layers.size()
				])
	print("all models: %.1f ms" % total)
	quit()
