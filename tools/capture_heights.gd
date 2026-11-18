extends SceneTree
## Plays the brief 006 flows on the test table through the game's own input
## (hover, clicks on the table, Enter to confirm, the dice tray's buttons, the
## override panel) and saves a screenshot after each step: the orange area,
## the path preview with roll points, the confirmation, a sheer climb that
## fails, a jump, a failed jump that falls with blood and infection spent on
## the injury roll, a drop survived standing, a drop that puts a model Down
## (and it standing up at half movement next turn), and one taken Out of
## Action.
##
## Outcomes are chosen by giving the game a dice seed that rolls them right
## before each roll (the only thing done to the state from outside; the game
## itself still only sends commands).
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_heights.gd -- <output folder>
##
## Model ids are the order of "models" in data/tables/height_test_table.json:
## 8 enemy on the bridge deck, 10 gap jumper, 11 ledge jumper, 12 dropper,
## 13 wide gap jumper, 14 block climber.

const SUCCESS: Array = [2, 2, true, 7, 12]
const FAILURE: Array = [2, 2, true, 2, 6]

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
	_press("First0")
	await _idle()

	# 1. Player 1, model 10 on the west jump platform: blue on its platform,
	# orange on the far platform (a jump) and on the ground (a 4" drop).
	_main.select_model(10)
	await _reach()
	_look(Vector3(9, 1.5, 6), 0.0, deg_to_rad(50), 17.0)
	await _shot("01_gap_jumper_blue_and_orange")
	_main.set_hover_override(Vector3(10.5, 4, 5))
	await _shot("02_hover_far_platform_jump_roll_point")
	_main.set_hover_override(Vector3(5, 0, 8.6))
	await _shot("02b_hover_ground_drop_injury_roll")
	_main.set_hover_override(null)
	await _frames(2)
	# Click the far platform: the route is pinned and waits for confirmation.
	_click_world(Vector3(10.5, 4, 5))
	await _frames(4)
	print("pinned: ", _main.move.pinned_destination())
	await _shot("03_orange_click_asks_for_confirmation")
	_rig(state, [SUCCESS])
	_key(KEY_ENTER)
	await _frames(14)
	await _shot("04_jump_roll_at_the_ledge")
	await _idle()
	await _shot("05_jumped_the_gap")
	print("after jump: model 10 at %s" % state.get_model(10).position)
	_finish(10)
	await _idle()

	# 2. Player 2, model 14: the top of the 4" block is orange; the climb fails.
	_main.select_model(14)
	await _reach()
	_look(Vector3(6, 2, 28.5), 0.0, deg_to_rad(45), 14.0)
	_main.set_hover_override(Vector3(6, 4, 26))
	await _shot("06_block_top_orange_climb_roll")
	_main.set_hover_override(null)
	await _frames(2)
	_click_world(Vector3(6, 4, 26))
	await _frames(4)
	_rig(state, [FAILURE])
	_main.move.confirm_pinned()
	await _idle()
	await _shot("07_failed_climb_stays_at_the_foot")
	print("after failed climb: model 14 at %s, active %d" % [state.get_model(14).position, state.turn.active_model_id])

	# 3. Player 1, model 13: the gap east is too wide (no orange on the far
	# side); it drops off the platform and is taken Out of Action.
	_main.select_model(13)
	await _reach()
	_look(Vector3(42.5, 1.5, 6.5), 0.0, deg_to_rad(50), 15.0)
	await _shot("08_wide_gap_no_jump_offered")
	_main.set_hover_override(Vector3(39.5, 0, 8.6))
	await _shot("08b_hover_drop")
	_main.set_hover_override(null)
	await _frames(2)
	_click_world(Vector3(39.5, 0, 8.6))
	await _frames(4)
	_rig(state, [[3, 2, true, 9, 12]])
	_key(KEY_ENTER)
	await _frames(14)
	await _shot("09_drop_injury_roll")
	await _idle()
	await _shot("10_out_of_action_removed")
	print("model 13 out of action: %s" % state.get_model(13).out_of_action)

	# 4. Player 2, model 11 with blood and infection markers: a failed jump to
	# the lower ledge falls 4" into the gap; player 1 spends both on the injury roll.
	_main.select_model(11)
	_main.toggle_overrides()
	await _frames(2)
	var panel: OverridePanel = _main.override_panel()
	panel.set_markers(Markers.BLOOD, 1)
	await _idle()
	panel.set_markers(Markers.INFECTION, 1)
	await _idle()
	_main.toggle_overrides()
	await _reach()
	_look(Vector3(21.5, 2, 7), 0.0, deg_to_rad(45), 13.0)
	_main.set_hover_override(Vector3(24, 2.5, 5))
	await _shot("11_ledge_jump_preview")
	_main.set_hover_override(null)
	await _frames(2)
	_click_world(Vector3(24, 2.5, 5))
	await _frames(4)
	# The jump roll: player 1 spends nothing; it fails. The injury roll: 1
	# blood and 1 infection spent, +1 for the fall: 5 dice, keep the highest 2.
	_rig(state, [FAILURE, [5, 2, true, 2, 6]])
	_key(KEY_ENTER)
	await _idle()
	await _shot("12_jump_roll_prompt_blood_and_infection")
	_main.tray().press_choices([0, 0] as Array[int])
	await _idle()
	await _shot("13_injury_prompt_after_the_fall")
	_main.tray().press_choices([1, 1] as Array[int])
	await _frames(14)
	await _shot("14_injury_roll_with_markers")
	await _idle()
	await _shot("15_fell_into_the_gap_blood_marker")
	var jumper: ModelState = state.get_model(11)
	print("model 11 at %s, blood %d, infection %d" % [jumper.position, jumper.marker_count(Markers.BLOOD), jumper.marker_count(Markers.INFECTION)])

	# 5. Player 1 passes with model 1.
	_main.select_model(1)
	_press("EndActivationButton")
	await _idle()

	# 6. Player 2, model 12: a drop from the 5" platform, survived standing; it carries on.
	_main.select_model(12)
	await _reach()
	_look(Vector3(34, 2, 7), 0.0, deg_to_rad(45), 14.0)
	_main.set_hover_override(Vector3(35.5, 0, 6))
	await _shot("16_drop_preview_injury_plus_one")
	_main.set_hover_override(null)
	await _frames(2)
	_click_world(Vector3(35.5, 0, 6))
	await _frames(4)
	_rig(state, [[3, 2, true, 2, 6]])
	_key(KEY_ENTER)
	await _idle()
	await _reach()
	await _shot("17_drop_survived_standing_move_left")
	print("model 12 at %s, %.2f\" left" % [state.get_model(12).position, state.pending.budget if state.pending != null else -1.0])
	_click_world(Vector3(37, 0, 7))
	await _idle()
	await _shot("18_carried_on_after_the_drop")
	_finish(12)
	await _idle()

	# 7. Player 1 passes with model 2.
	_main.select_model(2)
	_press("EndActivationButton")
	await _idle()

	# 8. Player 2, model 8 on the bridge deck: a 3.5" drop puts it Down.
	_main.select_model(8)
	await _reach()
	_look(Vector3(36, 2, 40), 0.0, deg_to_rad(45), 13.0)
	_main.set_hover_override(Vector3(36.5, 0, 40.4))
	await _shot("19_deck_drop_preview")
	_main.set_hover_override(null)
	await _frames(2)
	_click_world(Vector3(36.5, 0, 40.4))
	await _frames(4)
	_rig(state, [[3, 2, true, 7, 8]])
	_key(KEY_ENTER)
	await _idle()
	await _shot("20_down_lying_activation_ended")
	print("model 8 down %s, active %d" % [state.get_model(8).down, state.turn.active_model_id])

	# 9. The rest of turn 1: everyone else ends their activations.
	for guard: int in 100:
		if state.turn.turn != 1:
			break
		var player: int = state.turn.player_to_act
		var next_id: int = -1
		for model: ModelState in state.models:
			if model.player == player and model.on_table() and not state.turn.has_activated(model.id):
				next_id = model.id
				break
		_main.select_model(next_id)
		await _idle()
		_press("EndActivationButton")
		await _idle()
	_main.deselect()
	_look(Vector3(24, 0, 24), 0.0, deg_to_rad(58), 62.0)
	await _idle()
	await _shot("21_turn2_overview")
	print("turn %d, pending %s for player %d" % [
		state.turn.turn, PendingDecision.Kind.keys()[state.pending.kind], state.pending.player
	])

	# 10. Turn 2: model 8 stands up and moves at half movement.
	if state.pending.kind == PendingDecision.Kind.ROLL_OFF:
		_press("RollOffButton")
		await _idle()
	var chooser: int = state.pending.player
	_press("First1")
	await _idle()
	print("player %d chose player 2 first" % chooser)
	_main.select_model(8)
	_look(Vector3(36.5, 1, 41), 0.0, deg_to_rad(45), 13.0)
	await _idle()
	await _shot("22_down_model_selected_next_turn")
	_press("Action_move")
	await _reach()
	await _shot("23_stood_up_half_movement")
	print("model 8 stood up: down %s, budget %.2f" % [state.get_model(8).down, state.pending.budget])
	print("events played: %d" % _main.event_log.size())
	quit()


## Gives the game a dice seed whose next rolls come out as `rolls` says (see DiceRig).
func _rig(state: GameState, rolls: Array) -> void:
	var found: int = DiceRig.seed_for_sequence(rolls)
	if found < 0:
		push_error("no seed for %s" % str(rolls))
		return
	state.dice = Dice.new(found)


func _finish(id: int) -> void:
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
	for i: int in 900:
		if not _main.move.has_move_preview() or _main.move.is_reach_ready():
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
