extends SceneTree
## Times line of sight on the test table, outside GUT: every model against
## every enemy (brief 008 asks for one viewer against every enemy in well
## under a frame, under 5 ms in all):
## godot --headless --path . -s tools/bench_sight.gd


func _init() -> void:
	var state: GameState = GameState.new(1)
	var errors: PackedStringArray = TableSetup.apply_file(state, "res://data/tables/height_test_table.json")
	if not errors.is_empty():
		push_error(str(errors))
	state.height_field()
	state.sight_terrain()
	var sight: Sight = state.rules.sight
	var worst: float = 0.0
	var total: float = 0.0
	for round_index: int in 3:
		worst = 0.0
		total = 0.0
		for viewer: ModelState in state.models:
			var started: int = Time.get_ticks_usec()
			var seen: int = 0
			var enemies: int = 0
			for target: ModelState in state.models:
				if target.player == viewer.player:
					continue
				enemies += 1
				if sight.can_see(state, viewer, target):
					seen += 1
			var ms: float = (Time.get_ticks_usec() - started) / 1000.0
			total += ms
			worst = maxf(worst, ms)
			if round_index == 2:
				print("viewer %2d: sees %2d of %2d enemies, %6.2f ms" % [viewer.id, seen, enemies, ms])
	print("one viewer against every enemy: worst %.2f ms, mean %.2f ms over %d viewers" % [
		worst, total / state.models.size(), state.models.size()
	])
	quit()
