extends SceneTree
## Plays turn 1 of the brief 004 test table through the HUD's own buttons
## (first-player prompt, Move by clicking, Dash, marker prompts in the dice
## tray, the override panel, End activation) and saves a screenshot after
## each step, so the hotseat flow can be checked without clicking in the window.
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_turns.gd -- <output folder>
##
## Model ids are the order of "models" in data/tables/height_test_table.json:
## player 1 (red) has 1-6 and 9, player 2 (blue) has 7 and 8.

var _main: Node3D
var _camera: TableCamera
var _out_dir: String


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	var scene: PackedScene = load("res://game/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	_camera = _main.get_node("TableCamera")
	var state: GameState = _main.state

	# 1. Start of turn 1: player 2 has fewer models standing and chooses.
	_look(Vector3(24, 0, 26), 0.0, deg_to_rad(58), 62.0)
	await _shot("00_turn1_first_player_prompt")
	_press("First0")
	await _idle()
	await _shot("01_player1_to_act")

	# 2. Player 1 previews model 1 and moves it by clicking in the blue area.
	_main.select_model(1)
	await _reach()
	_look(Vector3(9, 1, 15), 0.5, deg_to_rad(45), 22.0)
	_main.set_hover_override(Vector3(11.8, 2, 14))
	await _shot("02_model1_selected_move_preview")
	_main.set_hover_override(null)
	await _frames(2)
	# A Move in two steps: first onto the ramp, then on with what is left.
	_click_world(Vector3(7.5, 0.83, 14))
	await _reach()
	_main.set_hover_override(Vector3(11.8, 2, 14))
	await _shot("03_model1_first_step_indicator_shows_rest")
	print("after step 1: %.2f\" left" % state.pending.budget)
	_main.set_hover_override(null)
	await _frames(2)
	_click_world(Vector3(11.8, 2, 14))
	await _idle()
	await _shot("03b_model1_second_step_move_greyed")
	# Undo the second step with Ctrl+Z: the model and its distance come back.
	_key(KEY_Z)
	await _reach()
	await _shot("03c_undo_gives_the_step_back")
	print("after undo: at %s, %.2f\" left" % [state.get_model(1).position, state.pending.budget])
	_key(KEY_Y)
	await _idle()
	await _shot("03d_redo")
	print("after redo: at %s" % state.get_model(1).position)
	_press("EndActivationButton")
	await _idle()
	await _shot("04_model1_done_player2_to_act")

	# 3. Player 2 dashes with model 7: the tray with breakdown, dice and outcome.
	_main.select_model(7)
	await _reach()
	_look(Vector3(30, 1, 40), 0.2, deg_to_rad(45), 24.0)
	await _shot("05_model7_selected")
	_press("Action_dash")
	await _frames(12)
	await _shot("06_dash_dice_tumbling")
	await _idle()
	await _shot("07_dash_result")
	if state.pending != null and state.pending.kind == PendingDecision.Kind.MOVE:
		await _reach()
		_main.set_hover_override(Vector3(31, 0, 36))
		await _shot("08_dash_success_move_offered")
		_main.set_hover_override(null)
		var destination: Variant = _main.destination_for(Vector3(31, 0, 36))
		print("dash move: ", _main.move_selected_to(destination) if destination != null else "no destination")
		await _idle()
		await _shot("09_after_dash_move")
	if state.turn.active_model_id == 7:
		_press("EndActivationButton")
		await _idle()

	# 4. Overrides: blood and blessing on model 2, then a Dash with both prompts.
	_main.select_model(2)
	_main.toggle_overrides()
	await _frames(2)
	var panel: OverridePanel = _main.override_panel()
	panel.set_markers(Markers.BLOOD, 2)
	await _idle()
	panel.set_markers(Markers.BLESSING, 2)
	await _idle()
	_look(Vector3(26, 1, 18), -0.4, deg_to_rad(45), 20.0)
	await _reach()
	await _shot("10_override_panel_markers_set")
	_press("Action_dash")
	await _idle()
	await _shot("11_blood_prompt_for_player2")
	print("blood prompt for player %d" % state.pending.player)
	_main.tray().press_choice(1)
	await _idle()
	await _shot("12_blessing_prompt_for_player1_sees_blood")
	print("blessing prompt for player %d" % state.pending.player)
	_main.tray().press_choice(2)
	await _frames(12)
	await _shot("13_dash_with_markers_tumbling")
	await _idle()
	await _shot("14_dash_with_markers_result")
	_finish_activation(2)
	await _idle()

	# 5. A failed Dash: six blood markers on model 8, all spent: eight dice, keep the lowest two.
	_main.select_model(8)
	panel.set_markers(Markers.BLOOD, 6)
	await _idle()
	_main.toggle_overrides()
	_look(Vector3(35, 2, 38), 0.0, deg_to_rad(50), 20.0)
	_press("Action_dash")
	await _idle()
	_main.tray().press_choice(6)
	await _idle()
	await _shot("15_failed_dash_activation_ends")
	print("after the failed dash: active %d, to act %d" % [state.turn.active_model_id, state.turn.player_to_act])

	# 6. A Down model stands up and moves half.
	_main.select_model(3)
	_main.toggle_overrides()
	await _frames(2)
	panel.set_down(true)
	await _idle()
	_main.toggle_overrides()
	_look(Vector3(15, 1, 16), 0.3, deg_to_rad(45), 18.0)
	await _reach()
	await _shot("16_down_model_half_move_preview")
	_main.set_hover_override(Vector3(13.2, 2, 14))
	await _shot("16b_down_model_hover")
	_main.set_hover_override(null)
	_click_world(Vector3(13.2, 2, 14))
	await _idle()
	await _shot("17_stood_up_and_moved")
	_finish_activation(3)
	await _idle()

	# 7. The rest of turn 1: each player ends their remaining activations in turn.
	for guard: int in 20:
		if state.turn.turn != 1:
			break
		var player: int = state.turn.player_to_act
		var next_id: int = -1
		for model: ModelState in state.models:
			if model.player == player and not state.turn.has_activated(model.id):
				next_id = model.id
				break
		_main.select_model(next_id)
		await _idle()
		_press("EndActivationButton")
		await _idle()
	_main.deselect()
	_look(Vector3(24, 0, 26), 0.0, deg_to_rad(58), 62.0)
	await _idle()
	await _shot("18_turn2_first_player_prompt")
	print("turn %d, pending %s for player %d" % [
		state.turn.turn, PendingDecision.Kind.keys()[state.pending.kind], state.pending.player
	])
	print("events played: %d" % _main.event_log.size())
	quit()


func _finish_activation(id: int) -> void:
	var state: GameState = _main.state
	if state.pending != null and state.pending.kind == PendingDecision.Kind.MOVE:
		_press("StayButton")
		await _idle()
	if state.turn.active_model_id == id:
		_main.select_model(id)
		_press("EndActivationButton")


func _press(button_name: String) -> void:
	var hud: Hud = _main.hud()
	if hud.press(button_name):
		print("pressed ", button_name)
	else:
		print("could not press ", button_name)


## Waits until every event has played back.
func _idle() -> void:
	await _frames(2)
	while _main.is_busy():
		await process_frame
	await _frames(2)


## Waits for the selected model's movement indicator, if it gets one.
func _reach() -> void:
	await _idle()
	for i: int in 600:
		if not _main.has_move_preview() or _main.is_reach_ready():
			return
		await process_frame


func _click_world(point: Vector3) -> void:
	var viewport_at: Vector2 = _camera.unproject_position(point)
	var at: Vector2 = root.get_final_transform() * viewport_at
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = true
	root.push_input(event)
	var release: InputEventMouseButton = event.duplicate()
	release.pressed = false
	root.push_input(release)


func _key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.ctrl_pressed = true
	event.pressed = true
	root.push_input(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	root.push_input(release)


func _look(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	_camera.focus = focus
	_camera.yaw = yaw
	_camera.pitch = pitch
	_camera.distance = distance
	_camera._update_transform()


func _shot(file_name: String) -> void:
	await _frames(4)
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(file_name + ".png")
	image.save_png(path)
	print("saved ", path)


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame
