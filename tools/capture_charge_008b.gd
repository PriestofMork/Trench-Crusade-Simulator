extends SceneTree
## Checks for brief 008b (charges on the movement process, the Down rules),
## played through the game's own input and saved as screenshots. Selection,
## charge mode (G), the route toggle button, hovering, the confirmation
## panel, the marker prompts, the override panel and undo are all real mouse
## clicks and key presses pushed into the window; only the dice are rigged
## (as the tests do) so each case comes out the way it is meant to show.
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_charge_008b.gd -- <output folder>
##
## Model ids as in data/tables/height_test_table.json: 34 the charger by the
## pillar (35 on it) and the sheer block (36 on it; the open block east of it
## is the long way round); 43 below 42 on the 2in step; 39 on the tower over
## the narrow 3in step; 40 by a ledge, 41 by a 1in step.

const SUCCESS: Array = [2, 2, true, 7, 12]
const FAILURE: Array = [2, 2, true, 2, 6]
const INJURY_PLUS1_BLOOD: Array = [3, 2, true, 2, 6]
const INJURY_PLUS1_DOWN: Array = [3, 2, true, 7, 8]

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


func _d6(roll: int) -> Array:
	return [1, 1, true, roll, roll]


func _rig(rolls: Array) -> void:
	_check(DiceRig.rig_sequence(_main.state, rolls), "dice rigged for %s" % str(rolls))


## Charge mode for `charger` with the toggle as wanted (clicking its
## button), then the target hovered, clicked and confirmed with a click; the
## dice rigged just before the confirmation.
func _declare(charger: int, target: int, allow_rolls: bool, rolls: Array, prefix: String) -> void:
	await _click_model(charger)
	await _reach()
	_key(KEY_G)
	await _charges()
	print("charge options for model %d: %.0f ms" % [charger, _main.charge_build_ms])
	if _main.is_charge_rolls() != allow_rolls:
		await _click_control(_main.hud().find_child("ChargeRollsButton", true, false))
		await _frames(3)
	_check(_main.is_charge_rolls() == allow_rolls, "climbs and jumps %s" % ("on" if allow_rolls else "off"))
	await _hover_model(target)
	await _shot(prefix + "_a_hover_route")
	print("hover: ", _label_text())
	await _click_model(target)
	await _frames(3)
	await _shot(prefix + "_b_confirm")
	print("confirm: ", _main.confirm_text().replace("\n", " / "))
	_rig(rolls)
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	await _answer_prompts()


## Answers marker prompts in the tray by clicking "0", and a contact choice
## with Enter (first contact).
func _answer_prompts() -> void:
	for i: int in 6:
		var state: GameState = _main.state
		if state.pending == null:
			return
		if state.pending.kind == PendingDecision.Kind.ROLL_CHOICE:
			await _click_control(_main.tray().prompt_button("Spend0"))
			await _idle()
		elif state.pending.kind == PendingDecision.Kind.CHARGE_CONTACT:
			_key(KEY_ENTER)
			await _idle()
		else:
			return


func _undo_to(size: int) -> void:
	var state: GameState = _main.state
	for i: int in 12:
		if state.history.size() <= size:
			break
		_key(KEY_Z, true)
		await _idle()
	_check(state.history.size() == size, "undone back to %d commands" % size)


func _tray() -> String:
	return _main.tray().text()


func _run() -> void:
	await _frames(5)
	_camera = _main.get_node("TableCamera")
	var state: GameState = _main.state
	await _click_control(_main.hud().find_child("First0", true, false))
	await _idle()
	var start: int = state.history.size()

	# 1. Up the sheer block with climbs and jumps on: the climb succeeds.
	_look(Vector3(15.5, 0, 31.5), 0.0, deg_to_rad(52), 12.0)
	await _declare(34, 36, true, [_d6(3), SUCCESS], "01_sheer_toggle_on")
	await _shot("01_sheer_toggle_on_c_climbed_in_contact")
	print("tray: ", _tray())
	var charger: ModelState = state.get_model(34)
	_check(absf(charger.position.y - 3.0) < 0.01, "34 climbed onto the block (at %s)" % charger.position)
	_check(MeleeZone.enemy_ids_within(state, charger).has(36), "34 in melee with 36")
	_check(state.turn.charged.has(36), "36 recorded as charged")

	# 2. The same, the climb fails: the charge fails, the activation ends.
	await _undo_to(start)
	await _declare(34, 36, true, [_d6(3), FAILURE], "02_sheer_toggle_on_fails")
	await _shot("02_sheer_toggle_on_fails_c_failed_climb")
	print("tray: ", _tray())
	_check(_tray().contains("charge failed"), "the tray shows the charge failing")
	_check(absf(state.get_model(34).position.y) < 0.01, "34 stays at the foot")
	_check(state.turn.active_model_id != 34, "the activation ended")
	_check(not state.turn.charged.has(36), "36 not charged")

	# 3. Toggle off: the long way round over the open block, no climb roll.
	await _undo_to(start)
	await _declare(34, 36, false, [_d6(6)], "03_sheer_toggle_off_long_way")
	await _shot("03_sheer_toggle_off_long_way_c_in_contact")
	_check(MeleeZone.enemy_ids_within(state, state.get_model(34)).has(36), "34 reached 36 the long way round")
	var rolls_on_route: int = -1
	for event: GameEvent in _main.event_log:
		if event.kind == GameEvent.Kind.CHARGE_DECLARED and int(event.data["target_id"]) == 36 and not bool(event.data["allow_rolls"]):
			rolls_on_route = (event.data["rolls"] as Array).size()
	_check(rolls_on_route == 0, "no rolls on the roll-free route")

	# 4. A hopeless charge: 40 is 13.6" away along the route.
	await _undo_to(start)
	_look(Vector3(15.5, 0, 39.5), 0.0, deg_to_rad(55), 16.0)
	await _declare(34, 40, false, [_d6(1)], "04_hopeless")
	await _shot("04_hopeless_c_stopped_short")
	print("tray: ", _tray())
	_check(_tray().contains("Charge failed"), "the tray says the charge fell short")
	_check(not MeleeZone.in_melee(state, state.get_model(34)), "34 stopped outside every zone")

	# 5. The pillar: no contact position; it ends touching the pillar, in melee.
	await _undo_to(start)
	_look(Vector3(11.5, 0, 31.5), 0.0, deg_to_rad(48), 9.0)
	await _declare(34, 35, false, [_d6(2)], "05_pillar")
	await _shot("05_pillar_c_in_melee_without_contact")
	print("34 at %s, %.2f\" from 35" % [state.get_model(34).position, MeleeZone.gap(state.get_model(34), state.get_model(35))])
	_check(state.turn.charged.has(35), "35 counts as charged")
	_check(MeleeZone.in_melee(state, state.get_model(34)), "34 in melee with the model on the pillar")
	await _end_activation(34)

	# 6. Player 2 passes; then 43 charges 42 on the 2in step from the ground.
	await _pass_with(14)
	_look(Vector3(30.5, 0, 19.5), 0.0, deg_to_rad(40), 8.0)
	await _declare(43, 42, false, [_d6(1)], "06_step")
	await _shot("06_step_c_contact_from_the_ground")
	var step_charger: ModelState = state.get_model(43)
	_check(absf(step_charger.position.y) < 0.01, "43 stays on the ground")
	_check(
		MeleeZone.in_base_contact(step_charger.position, step_charger.base_radius_inches(), step_charger.height_inches(), state.get_model(42)),
		"43 in base contact with 42 on the step"
	)
	await _end_activation(43)

	# 7. Player 2: model 40 by the ledge suffers a Down result (override
	# panel, through the rules): the ledge roll fails and it falls.
	_look(Vector3(15.5, 0, 45.5), 0.0, deg_to_rad(42), 9.0)
	await _click_model(40)
	await _frames(3)
	_key(KEY_O)
	await _frames(3)
	await _shot("07_ledge_a_model_by_the_ledge")
	_check(not GoingDown.ledge_for(state, state.get_model(40)).is_empty(), "40 is within 1\" of a ledge")
	_rig([FAILURE, INJURY_PLUS1_BLOOD])
	await _click_control(_main.override_panel().find_child("DownResult", true, false))
	await _frames(8)
	await _shot("07_ledge_b_ledge_roll_failed")
	print("tray: ", _tray())
	_check(_tray().contains("ledge roll"), "the tray says why the ledge roll is made")
	await _idle()
	await _shot("07_ledge_c_fell_and_down_below")
	var fallen: ModelState = state.get_model(40)
	_check(fallen.down and absf(fallen.position.y) < 0.01, "40 fell to the ground and is Down (at %s)" % fallen.position)
	# And 41 by the 1in step: no ledge roll.
	_look(Vector3(20, 0, 45.5), 0.0, deg_to_rad(42), 9.0)
	await _click_model(41)
	await _frames(3)
	while _main.tray().is_animating():
		await process_frame
	await _frames(30)
	var before: int = _main.event_log.size()
	await _click_control(_main.override_panel().find_child("DownResult", true, false))
	await _idle()
	var ledge_rolls: int = 0
	for i: int in range(before, _main.event_log.size()):
		if _main.event_log[i].kind == GameEvent.Kind.LEDGE_ROLL:
			ledge_rolls += 1
	_check(ledge_rolls == 0 and state.get_model(41).down, "41 by the 1in step goes Down with no ledge roll")
	await _shot("07_ledge_d_one_inch_step_no_roll")
	_key(KEY_O)
	await _frames(2)

	await _pass_with(7)

	# 8. 39 drops onto the narrow step: the landing puts it Down by the
	# ledge, the ledge roll fails, it falls again (no second ledge roll).
	_look(Vector3(7, 0, 45.5), 0.0, deg_to_rad(30), 10.0)
	await _click_model(39)
	await _reach()
	var land: Vector3 = Vector3(7.7, 3, 46)
	await _hover_world(land)
	await _shot("08_drop_a_hover_drop")
	_rig([INJURY_PLUS1_DOWN, FAILURE, INJURY_PLUS1_BLOOD])
	_click_world(land)
	await _frames(3)
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	for i: int in 4:
		if state.pending != null and state.pending.kind == PendingDecision.Kind.ROLL_CHOICE:
			await _frames(10)
			await _shot("08_drop_b_ledge_roll_prompt")
			await _click_control(_main.tray().prompt_button("Spend0"))
			await _idle()
	await _shot("08_drop_c_fell_off_the_step")
	print("tray: ", _tray())
	var dropper: ModelState = state.get_model(39)
	_check(dropper.down and absf(dropper.position.y) < 0.01, "39 fell off the narrow step and is Down (at %s)" % dropper.position)
	var ledge_count: int = 0
	for event: GameEvent in _main.event_log:
		if event.kind == GameEvent.Kind.LEDGE_ROLL and event.model_id == 39:
			ledge_count += 1
	_check(ledge_count == 1, "one ledge roll for 39")
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


func _charges() -> void:
	await _frames(2)
	for i: int in 900:
		if _main.is_charge_ready():
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
		if not _main.has_move_preview() or _main.is_reach_ready():
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
