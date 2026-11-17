extends SceneTree
## Checks for brief 007 (charge, melee zone, retreat), played through the
## game's own input and saved as screenshots. Model selection, hovering,
## prompts, the confirmation panel, the contact arc and the free-attack order
## are all answered with real mouse clicks and key presses pushed into the
## window; only the dice are rigged (as the tests do) so each case comes out
## the way it is meant to show.
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_charge.gd -- <output folder>
##
## Model ids as in data/tables/height_test_table.json: 15 charger, 16 clear
## target, 17 and 18 the multi-charge pair, 19 on the crate, 20 on the sheer
## wall, 21 the interposed charger, 22 its declared target, 23 the
## interposer, 24 in melee with 25 and 26.

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

	# 1. The charge block, with the pair already in melee linked.
	_look(Vector3(41, 0, 16.5), 0.0, deg_to_rad(60), 15.0)
	await _shot("01_charge_block_melee_links")
	_check(MeleeZone.melee_pairs(state).size() == 2, "24 is in melee with 25 and 26")

	# 2. Model 15 in charge mode (G): every enemy in range labelled.
	await _click_model(15)
	await _reach()
	await _shot("02_selected_zones_of_enemies_shown")
	_key(KEY_G)
	await _charges()
	await _shot("03_charge_mode_labels")
	var plans: Dictionary[int, ChargePlan] = _main.charge_plans()
	_check(plans.has(16) and plans[16].label() == "certain", "16 is a certain charge")
	_check(plans.has(17) and plans[17].label() == "needs 2+", "17 needs 2+ (%s)" % (plans[17].label() if plans.has(17) else "-"))
	_check(plans.has(20) and not plans[20].contact, "20 on the sheer wall: no roll-free way to contact (%s)" % (plans[20].label() if plans.has(20) else "-"))
	_check(plans.has(19) and plans[19].reachable(), "19 on the crate can be charged")
	await _hover_model(16)
	await _shot("04_hover_certain_charge_path")
	_check(_label_text().contains("certain"), "hover label: %s" % _label_text())
	await _hover_model(17)
	await _shot("05_hover_charge_needs_a_roll")
	_check(_label_text().contains("needs 2+"), "hover label: %s" % _label_text())
	await _hover_model(19)
	await _shot("06_hover_target_on_the_crate")
	await _hover_model(20)
	await _shot("07_hover_target_on_the_sheer_wall_out_of_reach")
	_check(_label_text().contains("no base contact"), "hover label: %s" % _label_text())

	# 3. A certain charge: click 16, confirm with a click, the D6 rolls.
	var before_charge: int = state.history.size()
	await _click_model(16)
	await _frames(3)
	await _shot("08_confirm_certain_charge")
	_check(_main.confirm_text().contains("Charge model 16"), "confirmation: %s" % _main.confirm_text().replace("\n", " / "))
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	await _shot("09_certain_charge_contact_arc")
	_check(state.pending != null and state.pending.kind == PendingDecision.Kind.CHARGE_CONTACT, "contact choice offered")
	_key(KEY_ENTER)
	await _idle()
	await _shot("10_certain_charge_in_contact")
	_check(MeleeZone.enemy_ids_within(state, state.get_model(15)).has(16), "15 in melee with 16")
	print("tray after the certain charge: ", _main.tray().text())

	# 4. Back (undo), then 17, which needs 2+: a 1 fails.
	await _undo_to(before_charge)
	_key(KEY_G)
	await _charges()
	DiceRig.rig(state, 1, 1, true, 1, 1)
	await _click_model(17)
	await _frames(3)
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	await _shot("11_charge_needs_2_rolled_1_fails")
	print("tray after the failed charge: ", _main.tray().text())
	_check(_main.tray().text().contains("Charge failed"), "the tray says the charge failed")
	_check(not MeleeZone.in_melee(state, state.get_model(15)), "15 stopped short, outside every zone")
	print("15 stopped at %s, %.2f\" from 17" % [state.get_model(15).position, MeleeZone.gap(state.get_model(15), state.get_model(17))])

	# 5. Back again: a 6 reaches with distance to spare; slide round 17 to
	# also charge 18, picked on the arc with a click.
	await _undo_to(before_charge)
	_key(KEY_G)
	await _charges()
	DiceRig.rig(state, 1, 1, true, 6, 6)
	await _click_model(17)
	await _frames(3)
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	_look(Vector3(41, 0, 15), 0.0, deg_to_rad(62), 12.0)
	await _shot("12_charge_needs_2_rolled_6_contact_arc")
	var decision: PendingDecision = state.pending
	var both: int = -1
	if decision != null and decision.kind == PendingDecision.Kind.CHARGE_CONTACT:
		for i: int in decision.positions.size():
			if (decision.charged_ids[i] as Array).has(18):
				both = i
				break
	_check(both != -1, "a position on the arc charges 18 too")
	if both != -1:
		var spot: Vector3 = decision.positions[mini(both + 2, decision.positions.size() - 1)]
		if not (decision.charged_ids[mini(both + 2, decision.positions.size() - 1)] as Array).has(18):
			spot = decision.positions[both]
		await _hover_world(spot)
		await _shot("13_hover_multi_charge_both_highlighted")
		_check(_label_text().contains("model 18"), "hover label: %s" % _label_text())
		_click_world(spot)
		await _idle()
		await _shot("14_multi_charge_in_contact_with_both")
		print("charged: ", state.turn.charged)
		_check(state.turn.charged.has(17) and state.turn.charged.has(18), "17 and 18 recorded as charged")
	await _end_activation(15)

	# 6. Player 2 passes with a model far away.
	await _pass_with(8)

	# 7. 21 charges 22, but 23 is in the way.
	_look(Vector3(42, 0, 12), 0.0, deg_to_rad(58), 16.0)
	await _click_model(21)
	await _reach()
	_key(KEY_G)
	await _charges()
	await _hover_model(22)
	await _shot("15_interposed_charge_label_and_path")
	_check(_main.charge_plans()[22].target_id == 23, "the charge on 22 goes to 23")
	_check(_label_text().contains("in the way of model 22"), "hover label: %s" % _label_text())
	await _click_model(22)
	await _frames(3)
	await _shot("16_interposed_charge_confirmation")
	_check(_main.confirm_text().contains("model 23 instead"), "confirmation: %s" % _main.confirm_text().replace("\n", " / "))
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	if state.pending != null and state.pending.kind == PendingDecision.Kind.CHARGE_CONTACT:
		_key(KEY_ENTER)
		await _idle()
	await _shot("17_interposed_charge_in_contact_with_23")
	_check(MeleeZone.enemy_ids_within(state, state.get_model(21)).has(23), "21 in melee with 23")
	await _end_activation(21)
	await _pass_with(11)

	# 8. 24 in melee: no Move indicator, the HUD says why; then Retreat.
	_look(Vector3(44.5, 0, 16), 0.0, deg_to_rad(58), 13.0)
	await _click_model(24)
	await _frames(4)
	await _shot("18_in_melee_cannot_move")
	_check(not _main.has_move_preview(), "no movement indicator for Move in melee")
	var move_button: Button = _main.hud().find_child("Action_move", true, false)
	_check(move_button.disabled and move_button.tooltip_text.contains("In melee"), "Move disabled: %s" % move_button.tooltip_text)
	await _click_control(_main.hud().find_child("Action_retreat", true, false))
	await _frames(3)
	await _shot("19_retreat_lists_two_free_attacks")
	_check(_main.confirm_text().contains("model 25") and _main.confirm_text().contains("model 26"), "confirmation: %s" % _main.confirm_text().replace("\n", " / "))
	await _click_control(_main.find_child("ConfirmMoveButton", true, false))
	await _idle()
	await _shot("20_enemy_player_orders_the_attacks")
	await _click_control(_main.hud().find_child("Attacker26", true, false))
	await _frames(3)
	await _shot("21_first_attacker_picked")
	await _click_control(_main.hud().find_child("Attacker25", true, false))
	await _frames(20)
	await _shot("22_free_attacks_in_the_tray")
	await _idle()
	await _reach()
	await _shot("23_retreat_movement_indicator")
	print("tray after the attacks: ", _main.tray().text())
	_check(_main.tray().text().contains("model 26 makes a free melee attack") or _main.tray().text().contains("Model 26 makes"), "the tray lists the attacks")
	_check(_main.has_move_preview(), "the retreat move shows the movement indicator")
	var target: Vector3 = Vector3(42.0, 0, 18.0)
	await _hover_world(target)
	await _shot("24_retreat_hover_destination")
	_click_world(target)
	await _idle()
	await _frames(10)
	await _shot("25_retreated_out_of_melee")
	_check(not MeleeZone.in_melee(state, state.get_model(24)), "24 is out of melee (at %s)" % state.get_model(24).position)
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
