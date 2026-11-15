class_name ModelView
extends MeshInstance3D
## Draws one model as its rules cylinder: base diameter by height, coloured by owner.
## Only displays a ModelState; it never changes one.

const PLAYER_COLOURS: Array[Color] = [
	Color(0.75, 0.18, 0.15),  # player 0: red
	Color(0.18, 0.35, 0.75),  # player 1: blue
]
const SELECTED_RING_COLOUR: Color = Color(1.0, 0.92, 0.55)
const SLIDE_SPEED_INCHES_PER_SECOND: float = 10.0

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


## Puts the view where the model is.
func sync(model: ModelState) -> void:
	# CylinderMesh is centred on its origin; the model position is the base underside.
	position = model.position + Vector3(0.0, height / 2.0, 0.0)


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
## one steady speed, as one motion, and calls `on_done` at the end.
func slide_along(path: Array[Vector3], on_done: Callable) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	for i: int in range(1, path.size()):
		var length: float = path[i].distance_to(path[i - 1])
		if length < 0.0001:
			continue
		var duration: float = length / SLIDE_SPEED_INCHES_PER_SECOND
		_tween.tween_property(self, "position", path[i] + Vector3(0.0, height / 2.0, 0.0), duration)
	_tween.tween_callback(on_done)


## Distance along the ray to where it hits this model's cylinder, or INF if it misses.
## `direction` must be normalised for the result to be in inches.
func ray_hit_distance(origin: Vector3, direction: Vector3) -> float:
	var base: Vector3 = position - Vector3(0.0, height / 2.0, 0.0)
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
