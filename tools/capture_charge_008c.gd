extends SceneTree
## Checks for brief 008c (charge planning on demand), played through the
## game's own input and saved as screenshots: selection, charge mode (G),
## hovering, clicking targets, the confirmation panel's buttons and undo are
## real mouse clicks and key presses pushed into the window; only the dice
## are rigged (as the tests do) so each charge comes out as it is meant to.
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_charge_008c.gd -- <output folder>
##
## Model ids as in data/tables/height_test_table.json: 15 the charger in the
## charge block, 16 its near target, 17 a target needing a roll, 38 across
## the gap far to the north (no D6 reaches); 21 charges 22 past the
## interposer 23.

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


func _searches() -> int:
	return _main.state.charge_routes().searches


## Clicks `charger` and opens charge mode with G.
func _open(charger: int) -> void:
	await _click_model(charger)
	await _reach()
	var before: int = _searches()
	_key(KEY_G)
	await _frames(4)
	print("charge mode for %d opened in %.1f ms" % [charger, _main.charge.build_ms])
	_check(_main.charge.active, "charge mode is open for %d" % charger)
	_check(_searches() == before, "opening charge mode searched no route")
	_check(_main.charge.build_ms < 20.0, "opening took %.1f ms (under 20)" % _main.charge.build_ms)


## Clicks the target, waits for its route; returns how many searches it took.
func _select(target: int) -> int:
	var before: int = _searches()
	await _click_model(target)
	await _frames(1)
	var waiting: String = _main.charge.label_text(target)
	await _charges()
	print("selected %d: label while working '%s', now '%s'; route %.0f ms on the worker" % [
		target, waiting, _main.charge.label_text(target), _main.charge.route_ms
	])
	_check(_main.charge.target() == target, "%d is selected" % target)
	_check(_main.charge.plan() != null, "its route is ready")
	_check(_main.confirm_text() != "", "Confirm and Cancel are offered")
	return _searches() - before


func _undo_to(size: int) -> void:
	var state: GameState = _main.state
	for i: int in 12:
		if state.history.size() <= size:
			break
		_key(KEY_Z, true)
		await _idle()
	_check(state.history.size() == size, "undone back to %d commands" % size)


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


func _run() -> void:
	await _frames(5)
	_camera = _main.get_node("TableCamera")
	var state: GameState = _main.state
	await _click_control(_main.hud().find_child("First0", true, false))
	await _idle()
	var start: int = state.history.size()

	# 1. Charge mode opens with only the declaration check: every enemy in
	# range says "can charge" (or "not visible").
	_look(Vector3(40, 0, 19), 0.0, deg_to_rad(55), 20.0)
	await _open(15)
	var declarations: Dictionary[int, String] = _main.charge.declarations()
	var labels: PackedStringArray = PackedStringArray()
	var all_plain: bool = true
	for id: int in declarations:
		var text: String = _main.charge.label_text(id)
		labels.append("%d: %s" % [id, text])
		all_plain = all_plain and text == ("can charge" if declarations[id] == "" else "not visible")
	print("labels: ", ", ".join(labels))
	_check(declarations.size() > 3 and all_plain, "every enemy in range: can charge / not visible only")
	await _shot("01_charge_mode_opens_can_charge_labels")

	# 2. Hovering an enemy only highlights it.
	var before: int = _searches()
	await _hover_model(17)
	await _frames(6)
	_check(_main.charge.hovered() == 17, "17 is highlighted under the cursor")
	_check(_searches() == before, "hovering searched nothing")
	_check(_main.charge.label_text(17) == "can charge", "17's label is unchanged")
	await _shot("02_hover_only_highlights")

	# 3. The near target: clicked, one search, route and label.
	_check(await _select(16) == 1, "one search for 16")
	_check(_main.charge.label_text(16) == "certain", "16: %s" % _main.charge.label_text(16))
	await _shot("03_near_target_selected_certain")
	print("confirm: ", _main.confirm_text().replace("\n", " / "))

	# 4. Cancel, then the far target across the gap: no D6 reaches.
	await _click_control(_main.find_child("CancelMoveButton", true, false))
	await _frames(2)
	_check(_main.confirm_text() == "" and _main.charge.label_text(16) == "can charge", "cancelled: 16 back to can charge")
	_look(Vector3(41, 0, 25), 0.0, deg_to_rad(55), 24.0)
	_check(await _select(38) >= 1, "38 searched")
	_check(_main.charge.label_text(38).begins_with("cannot reach"), "38: %s" % _main.charge.label_text(38))
	await _shot("04_far_target_selected_cannot_reach")
	print("confirm: ", _main.confirm_text().replace("\n", " / "))

	# 5. Back to 16: already worked out, nothing searched.
	await _click_control(_main.find_child("CancelMoveButton", true, false))
	await _frames(2)
	before = _searches()
	await _click_model(16)
	await _frames(3)
	_check(_main.charge.plan() != null and _searches() == before, "16 again: shown at once, no search")

	# 6. A declared charge that succeeds: 16, a 2.
	_look(Vector3(37, 0, 19), 0.0, deg_to_rad(55), 14.0)
	_check(DiceRig.rig_sequence(state, [_d6(2)]), "dice rigged")
	before = _searches()
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	await _answer_prompts()
	_check(_searches() == before, "declaring searched nothing (the route shown)")
	_check(MeleeZone.enemy_ids_within(state, state.get_model(15)).has(16), "15 in contact with 16")
	await _shot("05_declared_charge_succeeds")
	print("tray: ", _main.tray().text())

	# 7. A declared charge that fails: 38, a 6, still not enough.
	await _undo_to(start)
	_look(Vector3(41, 0, 25), 0.0, deg_to_rad(55), 24.0)
	await _open(15)
	await _select(38)
	_check(DiceRig.rig_sequence(state, [_d6(6)]), "dice rigged")
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	await _answer_prompts()
	var failed: bool = false
	for event: GameEvent in _main.event_log:
		if event.kind == GameEvent.Kind.CHARGE_FAILED:
			failed = true
	_check(failed, "the charge on 38 failed")
	_check(not MeleeZone.in_melee(state, state.get_model(15)), "15 stopped outside every zone")
	_check(state.get_model(15).position.z > 22.5, "15 moved north along the route (%s)" % state.get_model(15).position)
	await _shot("06_declared_charge_fails")
	print("tray: ", _main.tray().text())

	# 8. The interposed target: 21 on 22, 23 in the way.
	await _undo_to(start)
	_look(Vector3(42, 0, 12), 0.0, deg_to_rad(55), 16.0)
	await _open(21)
	_check(await _select(22) == 2, "two searches: to 22, then to the interposer 23")
	var plan: ChargePlan = _main.charge.plan()
	_check(plan != null and plan.target_id == 23, "23 is charged instead")
	_check(_main.charge.label_text(22).contains("model 23 in the way"), "22: %s" % _main.charge.label_text(22))
	await _shot("07_interposed_target_selected")
	print("confirm: ", _main.confirm_text().replace("\n", " / "))

	print("%d check(s) failed" % _failures if _failures > 0 else "all checks OK")
	quit()


func _check(ok: bool, what: String) -> void:
	print("%s: %s" % ["OK" if ok else "FAILED", what])
	if not ok:
		_failures += 1


func _label_text() -> String:
	var label: Label = _main.get_node("Ui/DistanceLabel")
	return label.text.replace("\n", " / ") if label.visible else ""


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
