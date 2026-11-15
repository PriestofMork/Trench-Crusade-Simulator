extends SceneTree
## Opens the main scene, drives a select / hover / move sequence through the
## main scene's public methods, and saves a screenshot after each step. For
## checking the movement indicator without clicking in the window.
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_movement.gd -- <output folder>

var _main: Node3D
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
	var camera: TableCamera = _main.get_node("TableCamera")

	# 1. Whole table, model 1 selected, hovering a point round the corner of the box.
	_main.select_model(1)
	_main.set_hover_override(Vector3(15.5, 0, 19.6))
	await _shot("01_table_selected")

	# 2. Close up, from above at an angle, same hover.
	_look(camera, Vector3(18, 0, 21), 0.35, deg_to_rad(62), 22.0)
	await _shot("02_close_hover_round_box")

	# 3. Steeper, closer, to see the line quality.
	_look(camera, Vector3(19.5, 0, 24.5), 0.2, deg_to_rad(75), 10.0)
	await _shot("03_detail_enemy_and_box")

	# 4. Hover outside the area: red ghost, no path.
	_look(camera, Vector3(18, 0, 21), 0.35, deg_to_rad(62), 22.0)
	_main.set_hover_override(Vector3(23.5, 0, 17.0))
	await _shot("04_hover_outside")

	# 4b. Hover behind the friendly model 7: the path runs straight through its base.
	_look(camera, Vector3(20.5, 0, 19.5), 0.35, deg_to_rad(65), 16.0)
	_main.set_hover_override(Vector3(23.6, 0, 18.6))
	await _shot("04b_path_through_friend")

	# 4c. Hover on model 7's centre: outside the area (friendly bases are holes
	# in it), so the ghost is red.
	_main.set_hover_override(Vector3(22.2, 0, 19.0))
	await _shot("04c_hover_on_friend_centre")

	# 4c2. Hover on model 7's rim: the ghost snaps to touching its base.
	_main.set_hover_override(Vector3(22.0 - 0.55, 0, 19.0 + 0.1))
	await _shot("04c2_hover_on_friend_rim_snaps")

	# 4d. Close up at the box wall (x 11..17, z 14..18): the area reaches the wall
	# and a cursor right at the wall puts the base against it.
	_look(camera, Vector3(16, 0, 18.5), 0.6, deg_to_rad(70), 9.0)
	_main.set_hover_override(Vector3(16.2, 0, 18.05))
	await _shot("04d_wall_close_up")

	# 4e. Move through model 7, then back again through it after R.
	_main.set_hover_override(null)
	print("move through friend: '%s'" % _main.move_selected_to(Vector3(23.6, 0, 18.6)))
	while _main.is_sliding():
		await process_frame
	print("model 1 now at %s" % _main.state.get_model(1).position)
	_look(camera, Vector3(20.5, 0, 19.5), 0.35, deg_to_rad(65), 16.0)
	_main.set_hover_override(Vector3(23.6, 0, 21.5))
	await _shot("04e_after_move_through_friend")
	_key(KEY_R)
	print("move back: '%s'" % _main.move_selected_to(Vector3(18, 0, 20)))
	while _main.is_sliding():
		await process_frame
	_key(KEY_R)
	_look(camera, Vector3(18, 0, 21), 0.35, deg_to_rad(62), 22.0)

	# 5. Move round the corner of the box and look at what is left.
	_main.set_hover_override(null)
	var error: String = _main.move_selected_to(Vector3(15.5, 0, 19.6))
	print("move: '%s'" % error)
	while _main.is_sliding():
		await process_frame
	_main.set_hover_override(Vector3(13.8, 0, 19.0))
	await _shot("05_after_move")

	# 6. Another model (8" move): hover behind a box, so the path bends round its corner.
	_main.select_model(5)
	_main.set_hover_override(Vector3(36.8, 0, 28.4))
	_look(camera, Vector3(32, 0, 28), 0.9, deg_to_rad(60), 24.0)
	await _shot("06_model5_path_round_box")

	# 7. Make that move and look at what is left.
	_main.set_hover_override(null)
	print("move: '%s'" % _main.move_selected_to(Vector3(36.8, 0, 28.4)))
	while _main.is_sliding():
		await process_frame
	_main.set_hover_override(Vector3(36, 0, 25))
	await _shot("07_model5_after_move")

	# 8. The real input path: keys and clicks pushed as input events.
	_main.set_hover_override(null)
	_look(camera, Vector3(24, 0, 22), 0.0, deg_to_rad(70), 40.0)
	await _frames(2)
	_key(KEY_R)
	print("after R: %.1f\" left" % _main.state.get_model(5).movement_left)
	_key(KEY_ESCAPE)
	print("after Esc: selected %d" % _main.selected_model_id())
	var model_3: Vector3 = _main.state.get_model(3).position + Vector3(0, 1, 0)
	print("model 3 on screen at %s" % camera.unproject_position(model_3))
	_click(camera.unproject_position(model_3))
	print("after clicking model 3: selected %d" % _main.selected_model_id())
	var target: Vector3 = _main.state.get_model(3).position + Vector3(-3, 0, 2)
	_click(camera.unproject_position(target))
	print("after clicking the area: sliding %s" % _main.is_sliding())
	_click(camera.unproject_position(_main.state.get_model(1).position + Vector3(0, 1, 0)))
	print("click while sliding ignored: selected %d" % _main.selected_model_id())
	while _main.is_sliding():
		await process_frame
	print("model 3 now at %s, %.2f\" left" % [_main.state.get_model(3).position, _main.state.get_model(3).movement_left])
	_click(camera.unproject_position(Vector3(5, 0, 44)))
	print("after clicking far table: selected %d" % _main.selected_model_id())
	quit()


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event)


## `at` is in viewport coordinates (as unproject_position() gives); input events
## arrive in window coordinates, which differ under content scaling.
func _click(viewport_at: Vector2) -> void:
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


func _look(camera: TableCamera, focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	camera.focus = focus
	camera.yaw = yaw
	camera.pitch = pitch
	camera.distance = distance
	camera._update_transform()


func _shot(file_name: String) -> void:
	await _frames(4)
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(file_name + ".png")
	image.save_png(path)
	print("saved ", path)


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame
