extends SceneTree
## Times charge planning on the test table, outside GUT (brief 008c targets:
## opening charge mode under 20 ms; one target's route under 100 ms typical,
## 300 ms worst):
## godot --headless --path . -s tools/bench_charge.gd [-- verbose]
## - the declaration check (what opening charge mode computes) for every
##   model with an enemy in range;
## - one target's route, for every declarable target of every such model,
##   with each route choice, each from an empty cache.


func _init() -> void:
	var verbose: bool = OS.get_cmdline_user_args().has("verbose")
	var state: GameState = GameState.new(1)
	var errors: PackedStringArray = TableSetup.apply_file(state, "res://data/tables/height_test_table.json")
	if not errors.is_empty():
		push_error(str(errors))
	state.height_field()
	state.sight_terrain()
	var open_ms: Array[float] = []
	var route_ms: Array[float] = []
	var worst: String = ""
	var worst_ms: float = 0.0
	var only: PackedInt32Array = PackedInt32Array()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			for part: String in arg.substr(5).split(","):
				only.append(int(part))
	for model: ModelState in state.models:
		if not only.is_empty() and not only.has(model.id):
			continue
		var planner: ChargePlanner = ChargePlanner.new(state, model.id)
		var started: int = Time.get_ticks_usec()
		var declarations: Dictionary[int, String] = planner.declarations()
		var ms: float = (Time.get_ticks_usec() - started) / 1000.0
		if declarations.is_empty():
			continue
		open_ms.append(ms)
		var labels: PackedStringArray = PackedStringArray()
		for target_id: int in declarations:
			if declarations[target_id] != "":
				labels.append("%d:not visible" % target_id)
				continue
			for rolls: bool in [false, true]:
				# No plans cached, so every route is searched (the floors a
				# charger can get onto are kept per state, as in play).
				var fresh: ChargeRouteCache = state.charge_routes()
				fresh.clear_plans()
				var searches_before: int = fresh.searches
				var taken_before: int = planner.states_taken
				var t0: int = Time.get_ticks_usec()
				var plan: ChargePlan = planner.plan(target_id, rolls)
				var route: float = (Time.get_ticks_usec() - t0) / 1000.0
				route_ms.append(route)
				var expanded: int = planner.states_taken - taken_before
				labels.append("%d%s:%s %.0fms/%d" % [target_id, "+" if rolls else "", plan.label(), route, expanded])
				if route > worst_ms:
					worst_ms = route
					worst = "charger %d -> %d (%s): %.0f ms, %s, %d searches, %d states taken" % [
						model.id, target_id, "climbs on" if rolls else "climbs off", route, plan.label(), fresh.searches - searches_before, expanded
					]
		if verbose:
			print("charger %2d: %2d in range, open %5.1f ms; %s" % [model.id, declarations.size(), ms, "; ".join(labels)])
		else:
			print("charger %2d: %2d in range, open %5.1f ms" % [model.id, declarations.size(), ms])
	open_ms.sort()
	route_ms.sort()
	print("opening charge mode: %d chargers, median %.1f ms, worst %.1f ms" % [open_ms.size(), _median(open_ms), open_ms.back()])
	print("one target's route: %d routes, median %.1f ms, 90%% %.1f ms, worst %.1f ms" % [
		route_ms.size(), _median(route_ms), route_ms[int(route_ms.size() * 0.9)], route_ms.back()
	])
	print("worst route: %s" % worst)
	quit()


static func _median(values: Array[float]) -> float:
	return values[values.size() / 2] if not values.is_empty() else 0.0
