class_name TableCamera
extends Camera3D
## Orbit camera around a focus point on the table.
## Right mouse drag: orbit. Middle mouse drag or WASD / arrow keys: pan.
## Mouse wheel: zoom. The focus stays over the table and the camera stays above it.

@export var orbit_speed: float = 0.005  # radians per pixel
@export var pan_speed_keys: float = 0.6  # camera distances per second
@export var zoom_step: float = 1.12
@export var min_distance: float = 4.0
@export var max_distance: float = 120.0
@export var min_pitch_deg: float = 8.0
@export var max_pitch_deg: float = 89.0

var focus: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = deg_to_rad(50.0)
var distance: float = 60.0

var _bounds_min: Vector2 = Vector2.ZERO
var _bounds_max: Vector2 = Vector2(48, 48)


## Limits the focus point to the table rectangle (x, z in inches) and centres on it.
func set_table_bounds(width: float, depth: float) -> void:
	_bounds_min = Vector2.ZERO
	_bounds_max = Vector2(width, depth)
	focus = Vector3(width / 2.0, 0.0, depth / 2.0)
	distance = clampf(maxf(width, depth) * 1.2, min_distance, max_distance)
	_update_transform()


func _ready() -> void:
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= motion.relative.x * orbit_speed
			pitch += motion.relative.y * orbit_speed
			_update_transform()
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan_screen(motion.relative)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance /= zoom_step
			_update_transform()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance *= zoom_step
			_update_transform()


func _process(delta: float) -> void:
	var input: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if input != Vector2.ZERO:
		var step: float = pan_speed_keys * distance * delta
		focus += (_ground_right() * input.x + _ground_forward() * input.y) * step
		_update_transform()


## Drag the table with the mouse: the point under the cursor follows it.
func _pan_screen(relative: Vector2) -> void:
	var viewport_height: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var inches_per_pixel: float = 2.0 * distance * tan(deg_to_rad(fov) / 2.0) / viewport_height
	focus += (-_ground_right() * relative.x + _ground_forward() * relative.y) * inches_per_pixel
	_update_transform()


func _ground_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _ground_right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _update_transform() -> void:
	pitch = clampf(pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	distance = clampf(distance, min_distance, max_distance)
	focus.x = clampf(focus.x, _bounds_min.x, _bounds_max.x)
	focus.z = clampf(focus.z, _bounds_min.y, _bounds_max.y)
	focus.y = 0.0
	var offset: Vector3 = Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * distance
	position = focus + offset
	look_at_from_position(position, focus, Vector3.UP)
