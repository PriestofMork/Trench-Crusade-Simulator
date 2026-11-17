extends GutTest
## Brief 008b, "one movement process": Move, Dash, Retreat and Charge (its
## route and its slide) are all carried out by MoveExecution, and falls by
## Falling. These read the sources of core/ and fail if a second way of
## moving a model, of reporting a move or a fall, or of rolling a climb or
## jump were added somewhere else.

## Where a model's position may be set: the move process, the fall, undo.
const POSITION_WRITERS: Array[String] = [
	"res://core/movement/move_execution.gd",
	"res://core/movement/falling.gd",
	"res://core/game_snapshot.gd",
]


func _core_sources() -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	var folders: Array[String] = ["res://core"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub: String in DirAccess.get_directories_at(folder):
			folders.append(folder.path_join(sub))
		for file: String in DirAccess.get_files_at(folder):
			if file.ends_with(".gd"):
				var path: String = folder.path_join(file)
				result[path] = FileAccess.get_file_as_string(path)
	return result


## The lines of `text` that are code (comments dropped).
func _code_lines(text: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n"):
		var code: String = line.strip_edges()
		if code.begins_with("#") or code == "":
			continue
		result.append(code)
	return result


func _files_with(pattern: RegEx) -> Array[String]:
	var found: Array[String] = []
	var sources: Dictionary[String, String] = _core_sources()
	for path: String in sources:
		for line: String in _code_lines(sources[path]):
			if pattern.search(line) != null:
				found.append(path)
				break
	found.sort()
	return found


func test_only_the_move_process_and_the_fall_set_model_positions() -> void:
	var pattern: RegEx = RegEx.create_from_string("\\.position\\s*=[^=]")
	var writers: Array[String] = _files_with(pattern)
	var expected: Array[String] = POSITION_WRITERS.duplicate()
	expected.sort()
	assert_eq(writers, expected)


func test_only_the_move_process_reports_moves_and_only_falling_reports_falls() -> void:
	assert_eq(_files_with(RegEx.create_from_string("Kind\\.MODEL_MOVED")), ["res://core/movement/move_execution.gd"] as Array[String])
	assert_eq(_files_with(RegEx.create_from_string("Kind\\.MODEL_FELL")), ["res://core/movement/falling.gd"] as Array[String])


func test_climbs_jumps_and_drops_are_rolled_in_one_place() -> void:
	# The risky roll before a climb or jump carries the move_roll context; the
	# injury roll of a drop or fall is made by Falling.injury_request().
	assert_eq(_files_with(RegEx.create_from_string("&\"move_roll\"")), ["res://core/movement/move_execution.gd"] as Array[String])
	assert_eq(_files_with(RegEx.create_from_string("roll_before\\(\\)")), [
		"res://core/movement/move_execution.gd", "res://core/movement/move_segment.gd",
	] as Array[String])
	assert_eq(_files_with(RegEx.create_from_string("&\"fall_inches\"")), ["res://core/movement/falling.gd"] as Array[String])


func test_the_charge_code_moves_nothing_itself() -> void:
	var sources: Dictionary[String, String] = _core_sources()
	for path: String in ["res://core/melee/charge_execution.gd", "res://core/melee/charge_planner.gd"]:
		var text: String = "\n".join(_code_lines(sources[path]))
		assert_false(text.contains("GameEvent.Kind.MODEL_MOVED"), path)
		assert_false(text.contains("RollPipeline.start(state, request, events)") and path.ends_with("planner.gd"), path)
	assert_true(sources["res://core/melee/charge_execution.gd"].contains("MoveExecution.run("), "the charge hands its moves to MoveExecution")
