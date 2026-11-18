extends SceneTree
## Checks for brief 008 (line of sight), played through the game's own input
## and saved as screenshots. Selection, hovering, the sight overview and debug
## buttons, charge mode and the charge click are all real mouse clicks and
## key presses pushed into the window.
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_sight.gd -- <output folder>
##
## Model ids as in data/tables/height_test_table.json: 27 the viewer, 28
## behind the 3in wall, 29 over the low wall, 30 hidden behind 29, 31 in the
## open, 32 behind the see-through screen, 33 on the sight ramp.

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
	await _click_control(_main.hud().find_child("First0", true, false))
	await _idle()
	var sight_view: SightView = _main.sight.view()

	# 1. The sight block, the viewer 27 selected.
	_look(Vector3(11, 0, 20.5), deg_to_rad(-20), deg_to_rad(52), 17.0)
	await _click_model(27)
	await _reach()
	await _shot("01_sight_block_viewer_selected")

	# 2. Hover an enemy in the open: the sight line.
	await _hover_model(31)
	await _shot("02_hover_sight_line_to_31")
	_check(_main.sight.hovered() == 31 and sight_view.has_line(), "a sight line to 31")
	_check(_label_text().contains("Model 31: visible"), "hover label: %s" % _label_text())

	# 3. Hover the enemy behind the 3in wall: not visible.
	await _hover_model(28)
	await _shot("03_hover_28_behind_the_wall_not_visible")
	_check(not sight_view.has_line(), "no line to 28")
	_check(sight_view.not_visible_ids().has(28), "28 labelled not visible")
	_check(_label_text().contains("Model 28: not visible"), "hover label: %s" % _label_text())

	# 4. Over the low wall: 29 is seen.
	await _hover_model(29)
	await _shot("04_hover_29_over_the_low_wall")
	_check(sight_view.has_line(), "a sight line over the low wall to 29")

	# 5. 30, hidden by 29 standing in front of it.
	await _hover_model(30)
	await _shot("05_hover_30_hidden_by_model_29")
	_check(not sight_view.has_line() and sight_view.not_visible_ids().has(30), "30 hidden by 29")

	# 6. 32 behind the see-through screen (seen from above, so the screen
	# does not cover it on the screen).
	_look(Vector3(9.5, 0, 19), deg_to_rad(-20), deg_to_rad(80), 12.0)
	await _hover_model(32)
	await _shot("06_hover_32_through_the_see_through_screen")
	_check(sight_view.has_line(), "a sight line through the screen to 32")

	# 7. The overview, by its button.
	await _hover_world(Vector3(11, 0, 26))
	await _click_control(_main.hud().find_child("SightOverviewButton", true, false))
	await _frames(4)
	_look(Vector3(12, 0, 20), deg_to_rad(-10), deg_to_rad(65), 22.0)
	await _shot("07_sight_overview")
	_check(_main.sight.is_overview(), "the overview is on")
	var unseen: Array[int] = sight_view.not_visible_ids()
	print("overview: not visible ", unseen)
	_check(unseen.has(28) and unseen.has(30) and not unseen.has(29) and not unseen.has(31) and not unseen.has(32), "overview marks: %s" % str(unseen))
	_check((_main.get_node("Models/Model28") as ModelView)._dimmed, "28 dimmed")
	_key(KEY_V)
	await _frames(3)
	_check(not _main.sight.is_overview(), "V turns it off")

	# 8. The model on the ramp with the debug cylinders (button).
	await _click_control(_main.hud().find_child("SightDebugButton", true, false))
	await _frames(4)
	_look(Vector3(19.5, 0.75, 18), deg_to_rad(180), deg_to_rad(38), 7.0)
	await _hover_world(Vector3(19.5, 0, 22))
	await _shot("08_ramp_model_debug_cylinder_side")
	_key(KEY_L)
	await _frames(3)
	await _shot("08b_ramp_model_drawn_without_cylinders")
	_key(KEY_L)
	await _frames(3)
	_look(Vector3(19.5, 0.75, 18), deg_to_rad(235), deg_to_rad(40), 7.0)
	await _shot("09_ramp_model_debug_cylinder_front")
	var view33: ModelView = _main.get_node("Models/Model33")
	var cyl33: SightCylinder = SightCylinder.for_model(state, state.get_model(33))
	_check(view33.drawn_up().distance_to(cyl33.axis) < 1e-4 and cyl33.axis.y < 0.99, "33 drawn tilted as its sight cylinder (%s)" % str(cyl33.axis))
	_key(KEY_L)
	await _frames(3)
	_check(not _main.sight.is_debug(), "L turns it off")

	# 9. Charge mode: enemies in range that cannot be seen are labelled, and a
	# click on one is refused.
	_look(Vector3(11, 0, 20.5), deg_to_rad(-20), deg_to_rad(52), 17.0)
	await _click_model(27)
	await _reach()
	_key(KEY_G)
	await _charges()
	await _shot("10_charge_mode_not_visible_labels")
	var declarations: Dictionary[int, String] = _main.charge.declarations()
	_check(declarations.get(28, "") != "" and _main.charge.label_text(28) == "not visible", "28: %s" % _main.charge.label_text(28))
	_check(declarations.get(30, "") != "" and _main.charge.label_text(30) == "not visible", "30: %s" % _main.charge.label_text(30))
	_check(declarations.get(31, "missing") == "", "31 can be declared")
	# Its route is worked out when it is clicked (brief 008c).
	await _click_model(31)
	await _charges()
	var plan: ChargePlan = _main.charge.plan()
	_check(plan != null and plan.reachable(), "31 can be charged (%s)" % (plan.label() if plan != null else "-"))
	await _click_control(_main.find_child("CancelMoveButton", true, false))
	await _frames(2)
	var before: int = state.history.size()
	await _click_model(28)
	await _frames(4)
	await _shot("11_charge_on_28_refused_not_visible")
	_check(state.history.size() == before and _main.confirm_text() == "", "no charge declared on 28")
	var message: RichTextLabel = _main.hud()._message
	print("message: ", message.get_parsed_text())
	_check(message.get_parsed_text().contains("cannot see model 28"), "the HUD says why")
	print("checks failed: %d" % _failures)
	quit()


func _check(ok: bool, what: String) -> void:
	print("%s: %s" % ["OK" if ok else "FAILED", what])
	if not ok:
		_failures += 1


func _label_text() -> String:
	var label: Label = _main.get_node("Ui/DistanceLabel")
	return label.text.replace("\n", " / ") if label.visible else ""


func _end_activation(id: int) -> void:
	var state: GameState = _main.state
	if state.turn.active_model_id != id:
		return
	if _main.selected_model_id() != id:
		await _click_model(id)
	await _click_control(_main.hud().find_child("EndActivationButton", true, false))
	await _idle()


## The player to act ends the activation of model `id` without doing anything.
func _pass_with(id: int) -> void:
	var view: ModelView = _main.get_node("Models/Model%d" % id)
	_look(view.base_position, 0.0, deg_to_rad(58), 16.0)
	await _click_model(id)
	await _frames(2)
	await _click_control(_main.hud().find_child("EndActivationButton", true, false))
	await _idle()


func _undo_to(size: int) -> void:
	var state: GameState = _main.state
	for i: int in 10:
		if state.history.size() <= size:
			break
		_key(KEY_Z, true)
		await _idle()
	_check(state.history.size() == size, "undone back to before the charge")
	await _click_model(15)
	await _reach()


func _charges() -> void:
	await _frames(2)
	for i: int in 900:
		if _main.charge.is_ready():
			break
		await process_frame
	await _frames(3)


func _idle() -> void:
	await _frames(2)
	while _main.is_busy():
		await process_frame
	await _frames(2)


func _reach() -> void:
	await _idle()
	for i: int in 900:
		if not _main.move.has_move_preview() or _main.move.is_reach_ready():
			return
		await process_frame


## A real click on the middle of the model's cylinder.
func _click_model(id: int) -> void:
	var view: ModelView = _main.get_node("Models/Model%d" % id)
	_click_world(view.base_position + Vector3(0, view.height * 0.5, 0))
	await _frames(3)


func _hover_model(id: int) -> void:
	var view: ModelView = _main.get_node("Models/Model%d" % id)
	await _hover_world(view.base_position + Vector3(0, view.height * 0.5, 0))


## A real mouse motion to the screen point of `point`.
func _hover_world(point: Vector3) -> void:
	var at: Vector2 = root.get_final_transform() * _camera.unproject_position(point)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	Input.warp_mouse(at)
	await _frames(4)


## A real left click on the middle of a control, through the window's input.
func _click_control(control: Control) -> void:
	if control == null:
		_check(false, "a control to click")
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


func _click_world(point: Vector3) -> void:
	var at: Vector2 = root.get_final_transform() * _camera.unproject_position(point)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = true
	root.push_input(event)
	var release: InputEventMouseButton = event.duplicate()
	release.pressed = false
	root.push_input(release)


func _key(keycode: Key, ctrl: bool = false) -> void:
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
