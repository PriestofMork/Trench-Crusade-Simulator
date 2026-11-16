extends SceneTree
## Follow-up checks for brief 006, played through the game's own input and
## saved as screenshots:
## - a model walking up the ramp, tilted to sit flush on it (and level again
##   on the platform);
## - the movement area from the 5" platform in both descent modes (C switches);
## - marker prompts answered with real mouse clicks on the tray's buttons:
##   blood and infection both spent on an injury roll (a drop) and on a
##   success roll (Dash), with blessing spent by the other player.
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_descent.gd -- <output folder>
##
## Model ids as in data/tables/height_test_table.json: 1 ramp walker, 2 wall
## climber (player 1), 12 dropper on the 5" platform (player 2).

var _main: Node3D
var _camera: TableCamera
var _out_dir: String
var _failures: int = 0


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

	# 1. Model 1 walks onto the ramp: tilted with it, then level on the platform.
	_main.select_model(1)
	await _reach()
	_look(Vector3(8, 1, 14), 0.0, deg_to_rad(50), 14.0)
	_click_world(Vector3(8.0, 0.67, 14))
	await _idle()
	await _frames(20)
	print("model 1 at %s" % state.get_model(1).position)
	_look(Vector3(8, 1, 14), 0.0, deg_to_rad(12), 8.0)
	await _shot("30_tilted_on_the_ramp")
	var view: ModelView = _main.get_node("Models/Model1")
	_check(view.transform.basis.y.angle_to(Vector3.UP) > deg_to_rad(10), "model 1 tilts on the ramp (%.1f deg)" % rad_to_deg(view.transform.basis.y.angle_to(Vector3.UP)))
	await _reach()
	_click_world(Vector3(12.3, 2.0, 14))
	await _idle()
	await _frames(20)
	await _shot("31_level_again_on_the_platform")
	_check(view.transform.basis.y.angle_to(Vector3.UP) < deg_to_rad(0.5), "model 1 level on the platform")
	_finish(1)
	await _idle()

	# 2. Model 12 on the 5" platform: Drop mode, then Climb down mode.
	_main.select_model(12)
	await _reach()
	_look(Vector3(33, 2, 7), 0.0, deg_to_rad(52), 17.0)
	_main.set_hover_override(Vector3(34.9, 0, 5))
	await _shot("32_descent_drop_mode")
	var drop_labels: String = _main.get_node("Ui/DistanceLabel").text
	_key(KEY_C, false)
	await _reach()
	await _shot("33_descent_climb_down_mode")
	var climb_labels: String = _main.get_node("Ui/DistanceLabel").text
	print("drop label: %s | climb label: %s" % [drop_labels.replace("\n", " / "), climb_labels.replace("\n", " / ")])
	_check(drop_labels.contains("Drop 5.0 (injury +1)"), "Drop mode label")
	_check(climb_labels.contains("Climb down 5.0 (risky)"), "Climb down mode label")
	var started: int = Time.get_ticks_msec()
	_key(KEY_C, false)
	await _reach()
	print("switching back to Drop: %d ms (cached)" % (Time.get_ticks_msec() - started))
	_main.set_hover_override(null)

	# 3. The drop with blood and infection on model 12 (player 1 decides) and
	# blessing (player 2 decides), every count clicked with the mouse.
	_main.toggle_overrides()
	await _frames(2)
	var panel: OverridePanel = _main.override_panel()
	panel.set_markers(Markers.BLOOD, 2)
	await _idle()
	panel.set_markers(Markers.INFECTION, 1)
	await _idle()
	panel.set_markers(Markers.BLESSING, 1)
	await _idle()
	_main.toggle_overrides()
	await _reach()
	_click_world(Vector3(35.5, 0, 6))
	await _frames(4)
	_key(KEY_ENTER, false)
	await _idle()
	await _shot("34_injury_prompt_blood_and_infection")
	print("decision line: ", _decision_text())
	await _click_control(_main.tray().prompt_button("Pick0_2"))
	await _click_control(_main.tray().prompt_button("Pick1_2"))
	await _frames(3)
	await _shot("35_both_counts_picked")
	await _click_control(_main.tray().prompt_button("SpendPicked"))
	await _idle()
	await _shot("36_blessing_prompt_sees_the_spending")
	await _frames(3)
	await _click_control(_main.tray().prompt_button("Spend1"))
	await _frames(10)
	await _shot("37_injury_dice_tumbling_status_line")
	print("decision line while tumbling: ", _decision_text())
	await _idle()
	await _shot("38_injury_result")
	var dropper: ModelState = state.get_model(12)
	print("model 12: blood %d, infection %d, blessing %d, down %s, out %s" % [
		dropper.marker_count(Markers.BLOOD), dropper.marker_count(Markers.INFECTION),
		dropper.marker_count(Markers.BLESSING), dropper.down, dropper.out_of_action
	])
	_check(dropper.marker_count(Markers.INFECTION) == 0, "infection was spent")
	_check(dropper.marker_count(Markers.BLESSING) == 0, "blessing was spent")
	if state.turn.active_model_id == 12:
		_finish(12)
	await _idle()

	# 4. Model 2 dashes with blood, infection and blessing: the same prompts
	# on a success roll, clicked with the mouse.
	_main.select_model(2)
	_main.toggle_overrides()
	await _frames(2)
	panel.set_markers(Markers.BLOOD, 1)
	await _idle()
	panel.set_markers(Markers.INFECTION, 2)
	await _idle()
	panel.set_markers(Markers.BLESSING, 2)
	await _idle()
	_main.toggle_overrides()
	_look(Vector3(26, 1, 18), -0.4, deg_to_rad(45), 20.0)
	await _idle()
	_press("Action_dash")
	await _idle()
	await _shot("39_dash_prompt_blood_and_infection")
	await _click_control(_main.tray().prompt_button("Pick0_1"))
	await _click_control(_main.tray().prompt_button("Pick1_3"))
	await _click_control(_main.tray().prompt_button("SpendPicked"))
	await _idle()
	await _frames(3)
	await _click_control(_main.tray().prompt_button("Spend2"))
	await _idle()
	await _shot("40_dash_result_with_markers")
	var dasher: ModelState = state.get_model(2)
	print("model 2: blood %d, infection %d, blessing %d" % [
		dasher.marker_count(Markers.BLOOD), dasher.marker_count(Markers.INFECTION), dasher.marker_count(Markers.BLESSING)
	])
	_check(dasher.marker_count(Markers.BLOOD) == 0 and dasher.marker_count(Markers.INFECTION) == 0, "blood and infection spent on the Dash")
	_check(dasher.marker_count(Markers.BLESSING) == 0, "blessing spent on the Dash")
	print("checks failed: %d" % _failures)
	quit()


func _check(ok: bool, what: String) -> void:
	print("%s: %s" % ["OK" if ok else "FAILED", what])
	if not ok:
		_failures += 1


func _decision_text() -> String:
	var label: RichTextLabel = _main.hud().find_child("Status", true, false).find_children("*", "RichTextLabel", true, false)[1]
	return label.get_parsed_text().replace("\n", " / ")


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


## A real left click on the middle of a control, through the window's input.
func _click_control(control: Control) -> void:
	if control == null:
		_check(false, "a prompt button to click")
		return
	await _frames(2)
	var control_name: String = control.name
	var at: Vector2 = root.get_final_transform() * control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	await _frames(1)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = true
	root.push_input(event)
	await _frames(1)
	var release: InputEventMouseButton = event.duplicate()
	release.pressed = false
	root.push_input(release)
	await _frames(2)
	print("clicked ", control_name)


func _idle() -> void:
	await _frames(2)
	while _main.is_busy():
		await process_frame
	await _frames(2)


func _reach() -> void:
	await _idle()
	for i: int in 900:
		if not _main.has_move_preview() or _main.is_reach_ready():
			return
		await process_frame


func _click_world(point: Vector3) -> void:
	var at: Vector2 = root.get_final_transform() * _camera.unproject_position(point)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = true
	root.push_input(event)
	var release: InputEventMouseButton = event.duplicate()
	release.pressed = false
	root.push_input(release)


func _key(keycode: Key, ctrl: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.ctrl_pressed = ctrl
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
