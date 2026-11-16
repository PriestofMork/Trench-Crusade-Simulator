class_name ModelView
extends MeshInstance3D
## Draws one model as its rules cylinder: base diameter by height, coloured by owner.
## A Down model lies on its side; an Out of Action model is not shown. Moves
## are played back segment by segment: walks slide, climbs go straight up or
## down the wall, jumps follow an arc and drops and falls come straight down.
## Only displays a ModelState; it never changes one.

const PLAYER_COLOURS: Array[Color] = [
	Color(0.75, 0.18, 0.15),  # player 0: red
	Color(0.18, 0.35, 0.75),  # player 1: blue
]
const SELECTED_RING_COLOUR: Color = Color(1.0, 0.92, 0.55)
const SLIDE_SPEED_INCHES_PER_SECOND: float = 10.0
const FALL_SPEED_INCHES_PER_SECOND: float = 14.0
## How far above the higher ledge a jump's arc rises, inches.
const JUMP_ARC_HEIGHT: float = 1.0
const ARC_STEPS: int = 12

var model_id: int = -1
var radius: float = 0.0
var height: float = 0.0

var _colour: Color
var _material: StandardMaterial3D
var _ring: MeshInstance3D
var _tween: Tween
var _label: Label3D
var _selected: bool = false
var _activated: bool = false
var _down: bool = false
## Where the underside of the base is, and the up direction it is drawn
## with (tilted to sit flush on a slope; presentation only).
var _base: Vector3 = Vector3.ZERO
var _up: Vector3 = Vector3.UP
## Given a base position, the up direction of the floor there (set by main).
var floor_normal: Callable = Callable()

## The underside of the base; the view follows it, tilting to the floor.
var base_position: Vector3:
	get:
		return _base
	set(value):
		_base = value
		_apply_transform()


func setup(model: ModelState) -> void:
	model_id = model.id
	name = "Model%d" % model.id
	height = model.height_inches()
	radius = model.base_radius_inches()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	mesh = cylinder
	_material = StandardMaterial3D.new()
	_colour = PLAYER_COLOURS[model.player]
	_material.albedo_color = _colour
	material_override = _material
	_build_ring()
	_build_label()
	sync(model)


## Puts the view where the model is, upright or lying Down, and hides it
## once it is Out of Action.
func sync(model: ModelState) -> void:
	visible = model.on_table()
	_down = model.down
	# CylinderMesh is centred on its origin; the model position is the base underside.
	_base = model.position
	if _down:
		rotation = Vector3(0.0, 0.0, PI / 2.0)
		position = model.position + Vector3(0.0, radius, 0.0)
		_label.position = Vector3(radius + 0.5, 0.0, 0.0)
		_ring.position = Vector3(-radius + 0.025, 0.0, 0.0)
		_ring.rotation = Vector3(0.0, 0.0, -PI / 2.0)
	else:
		_up = _target_up()
		_apply_transform()
		_label.position = Vector3(0.0, height / 2.0 + 0.5, 0.0)
		_ring.position = Vector3(0.0, -height / 2.0 + 0.025, 0.0)
		_ring.rotation = Vector3.ZERO


func set_selected(selected: bool) -> void:
	_selected = selected
	_ring.visible = selected
	_apply_look()


## Shows the model's id, markers and Down state above it, and greys out a
## model that has activated this turn.
func show_status(model: ModelState, activated: bool, activating: bool) -> void:
	_activated = activated and not activating
	var parts: PackedStringArray = PackedStringArray([str(model.id)])
	var short_names: Dictionary[StringName, String] = {
		Markers.BLOOD: "Bl", Markers.BLESSING: "Bs", Markers.INFECTION: "In"
	}
	for kind: StringName in Markers.KINDS:
		if model.marker_count(kind) > 0:
			parts.append("%s%d" % [short_names.get(kind, String(kind)), model.marker_count(kind)])
	if model.down:
		parts.append("DOWN")
	if _activated:
		parts.append("done")
	elif activating:
		parts.append("active")
	_label.text = " ".join(parts)
	_label.modulate = Color(0.7, 0.7, 0.7) if _activated else Color.WHITE
	_apply_look()


func _apply_look() -> void:
	var base: Color = _colour.lerp(Color(0.35, 0.35, 0.35), 0.65) if _activated else _colour
	_material.albedo_color = base
	_material.emission_enabled = _selected
	_material.emission = base.lerp(Color.WHITE, 0.6) if _selected else Color.BLACK
	_material.emission_energy_multiplier = 0.35


## Animates the view along `path` (positions of the base, start first, with
## climbs and drops already split into their vertical and horizontal parts) at
## one steady speed, as one motion, and calls `on_done` at the end. Parts
## straight down are falls: a little faster, speeding up.
func slide_along(path: Array[Vector3], on_done: Callable) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_down = false
	_tween = create_tween()
	for i: int in range(1, path.size()):
		var step: Vector3 = path[i] - path[i - 1]
		var length: float = step.length()
		if length < 0.0001:
			continue
		var falling: bool = step.y < -0.5 and Vector2(step.x, step.z).length() < 0.01
		var speed: float = FALL_SPEED_INCHES_PER_SECOND if falling else SLIDE_SPEED_INCHES_PER_SECOND
		var tweener: PropertyTweener = _tween.tween_property(self, "base_position", path[i], length / speed)
		if falling:
			tweener.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(on_done)


## Puts the view at `base` (the underside of the base), standing, without
## reading the state: for the end of a played move, before later events
## (going Down, Out of Action) are shown.
func place_at(base: Vector3) -> void:
	_down = false
	_base = base
	_apply_transform()


## Eases the tilt towards the floor under the base, so it changes smoothly
## while moving (from level to a ramp and back).
func _process(delta: float) -> void:
	if _down or not visible:
		return
	var target: Vector3 = _target_up()
	if _up.is_equal_approx(target):
		return
	_up = _up.slerp(target, clampf(delta * 12.0, 0.0, 1.0)).normalized()
	_apply_transform()


func _target_up() -> Vector3:
	if not floor_normal.is_valid():
		return Vector3.UP
	return floor_normal.call(_base)


## Upright or tilted to `_up`, the base underside at `_base` (not when Down).
func _apply_transform() -> void:
	if _down:
		return
	var tilt: Basis = Basis(Quaternion(Vector3.UP, _up))
	transform = Transform3D(tilt, _base + _up * (height / 2.0))


## The points a jump from `a` to `b` passes through: an arc rising
## JUMP_ARC_HEIGHT above the higher end (b last, a left out).
static func jump_arc(a: Vector3, b: Vector3, to_middle_only: bool = false) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var top: float = maxf(a.y, b.y) + JUMP_ARC_HEIGHT
	var steps: int = ARC_STEPS / 2 if to_middle_only else ARC_STEPS
	for k: int in range(1, steps + 1):
		var t: float = float(k) / ARC_STEPS
		var flat: Vector3 = a.lerp(b, t)
		# A parabola through a.y at 0, top at the middle, b.y at 1.
		var y: float = (1.0 - t) * (1.0 - 2.0 * t) * a.y + 4.0 * t * (1.0 - t) * top + t * (2.0 * t - 1.0) * b.y
		points.append(Vector3(flat.x, y, flat.z))
	return points


## Distance along the ray to where it hits this model's cylinder, or INF if it misses.
## `direction` must be normalised for the result to be in inches.
func ray_hit_distance(origin: Vector3, direction: Vector3) -> float:
	if not visible:
		return INF
	var base: Vector3 = _base
	var best: float = INF
	# Side of the cylinder.
	var ox: float = origin.x - base.x
	var oz: float = origin.z - base.z
	var a: float = direction.x * direction.x + direction.z * direction.z
	if a > 0.000001:
		var b: float = 2.0 * (ox * direction.x + oz * direction.z)
		var c: float = ox * ox + oz * oz - radius * radius
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var t: float = (-b - sqrt(disc)) / (2.0 * a)
			var y: float = origin.y + direction.y * t
			if t > 0.0 and y >= base.y and y <= base.y + height:
				best = t
	# Top cap.
	if absf(direction.y) > 0.000001:
		var t: float = (base.y + height - origin.y) / direction.y
		if t > 0.0:
			var p: Vector3 = origin + direction * t
			if Vector2(p.x - base.x, p.z - base.z).length() <= radius:
				best = minf(best, t)
	return best


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "Status"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 26
	_label.outline_size = 8
	_label.position = Vector3(0.0, height / 2.0 + 0.5, 0.0)
	add_child(_label)


func _build_ring() -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	var inner: float = radius + 0.06
	var outer: float = radius + 0.16
	var segments: int = 48
	for k: int in segments:
		var d0: Vector3 = Vector3(cos(TAU * k / segments), 0, sin(TAU * k / segments))
		var d1: Vector3 = Vector3(cos(TAU * (k + 1) / segments), 0, sin(TAU * (k + 1) / segments))
		vertices.append_array([d0 * inner, d1 * inner, d1 * outer, d0 * inner, d1 * outer, d0 * outer])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var ring_mesh: ArrayMesh = ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = SELECTED_RING_COLOUR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring = MeshInstance3D.new()
	_ring.name = "SelectionRing"
	_ring.mesh = ring_mesh
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Just above the table, measured from the cylinder's centre.
	_ring.position = Vector3(0.0, -height / 2.0 + 0.025, 0.0)
	_ring.visible = false
	add_child(_ring)
