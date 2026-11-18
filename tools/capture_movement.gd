extends SceneTree
## Opens the main scene (the brief 004 height test table), drives select /
## hover / move sequences through the main scene's public methods, and saves a
## screenshot after each step. For checking movement and the indicator
## without clicking in the window.
##
## Run with a rendering driver (not --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 -s tools/capture_movement.gd -- <output folder>
##
## Since brief 005 a model only gets a movement indicator on its own turn,
## so this script (written for brief 004's free movement) no longer runs to
## the end: selections that get no indicator time out. tools/capture_turns.gd
## drives the turn flow.
##
## Model ids are the order of "models" in data/tables/height_test_table.json:
## 1 ramp walker, 2 wall climber, 3 on the platform, 4 sandbag crosser,
## 5 crate stopper, 6 tower climber, 7 bridge walker, 8 enemy on the deck,
## 9 under the deck.

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

	# 0. The whole test table.
	_look(Vector3(24, 0, 26), 0.0, deg_to_rad(58), 62.0)
	await _shot("00_test_table")

	# 1. Ramp walker: the area runs up the ramp and onto the platform.
	await _select(1)
	_look(Vector3(10, 1, 15), 0.5, deg_to_rad(40), 20.0)
	_main.set_hover_override(Vector3(11.8, 2, 14))
	await _shot("01_ramp_walker_hover_platform")
	_look(Vector3(8, 1, 14), 1.4, deg_to_rad(25), 12.0)
	await _shot("01b_indicator_lies_on_the_ramp")
	await _move_and_film(Vector3(11.8, 2, 14), "01c_ramp_walk", Vector3(10, 1, 15), 0.5, deg_to_rad(40), 20.0)

	# 2. Wall climber: up the 2" wall and on, in one move.
	await _select(2)
	_look(Vector3(26, 1, 15.5), -0.6, deg_to_rad(35), 16.0)
	_main.set_hover_override(Vector3(26.3, 2, 14.6))
	await _shot("02_wall_climber_hover")
	await _move_and_film(Vector3(26.3, 2, 14.6), "02b_climb", Vector3(26, 1, 15.5), -0.6, deg_to_rad(35), 16.0)

	# 3. Sandbag crosser: straight over, nothing extra.
	await _select(4)
	_main.set_hover_override(Vector3(6, 0.5, 38))
	_look(Vector3(7, 0, 38.5), 0.0, deg_to_rad(75), 11.0)
	await _shot("03a_sandbag_row_one_area")
	_look(Vector3(7, 0, 38.5), 0.9, deg_to_rad(40), 14.0)
	_main.set_hover_override(Vector3(7, 0, 35.5))
	await _shot("03_sandbags_hover")
	await _move_and_film(Vector3(7, 0, 35.5), "03b_sandbags", Vector3(7, 0, 38.5), 0.9, deg_to_rad(40), 14.0)

	# 4. Crate stopper: onto the crate, the label shows the surcharge; the small crate is no destination.
	await _select(5)
	_look(Vector3(16.5, 0.5, 39.5), 0.4, deg_to_rad(42), 14.0)
	_main.set_hover_override(Vector3(15, 1, 38.5))
	await _shot("04_crate_hover_surcharge")
	_main.set_hover_override(Vector3(19.5, 1, 38))
	await _shot("04b_small_crate_hover")
	await _move_and_film(Vector3(15, 1, 38.5), "04c_onto_crate", Vector3(16.5, 0.5, 39.5), 0.4, deg_to_rad(42), 14.0)

	# 5. On the platform: hop down.
	await _select(3)
	_look(Vector3(15, 1, 16), 0.3, deg_to_rad(38), 14.0)
	_main.set_hover_override(Vector3(15.5, 0, 19))
	await _shot("05_platform_hover_below")
	await _move_and_film(Vector3(15.5, 0, 19), "05b_hop_down", Vector3(15, 1, 16), 0.3, deg_to_rad(38), 14.0)

	# 6. Tower climber: only by the ladder.
	await _select(6)
	_look(Vector3(24, 2, 27), 0.3, deg_to_rad(35), 16.0)
	_main.set_hover_override(Vector3(24, 4, 27))
	await _shot("06_tower_hover_top")
	await _move_and_film(Vector3(24, 4, 27), "06b_ladder_up", Vector3(24, 2, 27), 0.3, deg_to_rad(35), 16.0)

	# 7. Bridge walker: both levels, under the deck and on it.
	await _select(7)
	_look(Vector3(32, 1.5, 39), 0.25, deg_to_rad(22), 20.0)
	_main.set_hover_override(Vector3(33, 0, 38))
	await _shot("07_bridge_hover_under")
	_main.set_hover_override(Vector3(33, 3.5, 38))
	await _shot("07b_bridge_hover_on_top")
	_look(Vector3(32, 0, 38), 0.25, deg_to_rad(70), 24.0)
	await _shot("07c_bridge_from_above")
	await _move_and_film(Vector3(33, 3.5, 38), "07d_onto_deck", Vector3(32, 1.5, 39), 0.25, deg_to_rad(22), 20.0)

	# 8. Under the deck, below the enemy on it: the 1" rule is measured in 3D.
	await _select(9)
	_look(Vector3(34, 1, 36), 0.1, deg_to_rad(18), 16.0)
	_main.set_hover_override(Vector3(36.5, 0, 38))
	await _shot("08_under_enemy_on_deck")

	# 9. The real input path: a click on the enemy on the deck, then a click on the deck.
	_main.set_hover_override(null)
	_main.deselect()
	_look(Vector3(35, 2, 38), 0.0, deg_to_rad(55), 18.0)
	await _frames(2)
	var model_8: Vector3 = _main.state.get_model(8).position + Vector3(0, 1, 0)
	_click(_camera.unproject_position(model_8))
	print("after clicking model 8: selected %d" % _main.selected_model_id())
	while not _main.move.is_reach_ready():
		await process_frame
	_click(_camera.unproject_position(Vector3(33.5, 3.5, 38.5)))
	print("after clicking the deck: sliding %s" % _main.is_busy())
	while _main.is_busy():
		await process_frame
	print("model 8 now at %s, movement %.1f\"" % [_main.state.get_model(8).position, _main.state.get_model(8).movement])
	quit()


func _select(id: int) -> void:
	_main.set_hover_override(null)
	_main.select_model(id)
	for i: int in 600:
		if _main.move.is_reach_ready():
			return
		await process_frame
	print("model %d got no movement indicator (not its turn)" % id)


## Moves the selected model there, saving frames during the slide and after it.
func _move_and_film(target: Vector3, file_name: String, focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	_main.set_hover_override(null)
	var id: int = _main.selected_model_id()
	var destination: Variant = _main.move.destination_for(target)
	var error: String = "no destination near %s" % target
	if destination != null:
		error = _main.move.move_selected_to(destination)
	print("%s: move model %d to %s: '%s'" % [file_name, id, target, error])
	_look(focus, yaw, pitch, distance)
	var frame: int = 0
	while _main.is_busy():
		await _frames(9)
		if _main.is_busy():
			await _shot("%s_%d" % [file_name, frame])
			frame += 1
	print("  model %d now at %s, movement %.1f\"" % [id, _main.state.get_model(id).position, _main.state.get_model(id).movement])
	while not _main.move.is_reach_ready():
		await process_frame
	await _shot("%s_after" % file_name)


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
