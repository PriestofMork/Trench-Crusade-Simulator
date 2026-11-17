extends SceneTree
## Times the charge planner (all targets of one charger, both route choices)
## for every model on the test table that has an enemy in range, outside GUT:
## godot --headless --path . -s tools/bench_charge.gd


func _init() -> void:
	var state: GameState = GameState.new(1)
	var errors: PackedStringArray = TableSetup.apply_file(state, "res://data/tables/height_test_table.json")
	if not errors.is_empty():
		push_error(str(errors))
	state.height_field()
	state.sight_terrain()
	var total: float = 0.0
	var count: int = 0
	for model: ModelState in state.models:
		var planner: ChargePlanner = ChargePlanner.new(state, model.id)
		if planner.in_range().is_empty():
			continue
		var started: int = Time.get_ticks_usec()
		var labels: PackedStringArray = PackedStringArray()
		for target: ModelState in planner.in_range():
			var both: Array[ChargePlan] = planner.plans(target.id)
			labels.append("%d:%s | %s" % [target.id, both[0].label(), both[1].label()])
		var ms: float = (Time.get_ticks_usec() - started) / 1000.0
		total += ms
		count += 1
		var extended: String = " (+extended field)" if planner._extended != null else ""
		print("charger %2d: %4d targets in range, %7.1f ms%s  %s" % [model.id, planner.in_range().size(), ms, extended, "; ".join(labels)])
	print("%d chargers: %.1f ms in all, %.1f ms each" % [count, total, total / maxf(count, 1)])
	quit()
