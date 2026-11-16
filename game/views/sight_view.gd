class_name SightView
extends Node3D
## What brief 008 adds to the table: the sight line from the selected model
## to a hovered enemy (or a "not visible" label), the overview marks on the
## enemies the selected model can see, and the debug view of every model's
## sight cylinder, tilted as core has it. Only draws what it is given; the
## sight answers come from core through main's cache.

const LINE_COLOUR: Color = Color(0.55, 1.0, 0.75, 0.95)
const SEEN_COLOUR: Color = Color(0.45, 1.0, 0.6, 0.9)
const HIDDEN_COLOUR: Color = Color(1.0, 0.45, 0.4)
const CYLINDER_COLOUR: Color = Color(0.3, 0.95, 1.0, 0.22)
const CYLINDER_EDGE_COLOUR: Color = Color(0.3, 0.95, 1.0, 0.95)
const LINE_WIDTH: float = 0.05
const DOT_SIZE: float = 0.11
const SEGMENTS: int = 40

var _line: MeshInstance3D
var _marks: MeshInstance3D
var _cylinders: MeshInstance3D
var _cylinder_edges: MeshInstance3D
var _labels: Dictionary[int, Label3D] = {}


func _init() -> void:
	name = "SightView"
	_line = _child("SightLine", _material(LINE_COLOUR, 8, true))
	_marks = _child("SeenMarks", _material(SEEN_COLOUR, 4, true))
	_cylinders = _child("SightCylinders", _material(CYLINDER_COLOUR, 2, false))
	_cylinder_edges = _child("SightCylinderEdges", _material(CYLINDER_EDGE_COLOUR, 3, true))


## The clear segment between two models, as a thin bar with a dot at each end.
func show_line(from: Vector3, to: Vector3) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	_add_bar(vertices, from, to, LINE_WIDTH)
	_add_dot(vertices, from, DOT_SIZE)
	_add_dot(vertices, to, DOT_SIZE)
	_set_mesh(_line, vertices)


func hide_line() -> void:
	_set_mesh(_line, PackedVector3Array())


## Whether a sight line is drawn (for scripted checks).
func has_line() -> bool:
	return _line.mesh != null


## "not visible" over each model in `ids` (and over no others).
func show_not_visible(state: GameState, ids: Array[int]) -> void:
	for id: int in _labels.keys():
		if not ids.has(id):
			_labels[id].queue_free()
			_labels.erase(id)
	for id: int in ids:
		var model: ModelState = state.get_model(id)
		if model == null:
			continue
		var label: Label3D = _labels.get(id)
		if label == null:
			label = Label3D.new()
			label.name = "NotVisible%d" % id
			label.text = "not visible"
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.fixed_size = true
			label.pixel_size = 0.0012
			label.font_size = 22
			label.outline_size = 10
			label.modulate = HIDDEN_COLOUR
			add_child(label)
			_labels[id] = label
		label.position = model.position + Vector3(0.0, model.height_inches() + 1.45, 0.0)


## The models labelled "not visible" (for scripted checks).
func not_visible_ids() -> Array[int]:
	var result: Array[int] = []
	result.assign(_labels.keys())
	result.sort()
	return result


## Overview: a ring round the base of each model in `seen`.
func show_seen(state: GameState, seen: Array[int]) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	for id: int in seen:
		var model: ModelState = state.get_model(id)
		if model != null:
			_add_ring(vertices, model.position + Vector3(0.0, 0.05, 0.0), model.base_radius_inches() + 0.3, 0.12)
	_set_mesh(_marks, vertices)


## Debug: every cylinder as a see-through shell with its rims drawn.
func show_cylinders(cylinders: Array[SightCylinder]) -> void:
	var shell: PackedVector3Array = PackedVector3Array()
	var edges: PackedVector3Array = PackedVector3Array()
	for c: SightCylinder in cylinders:
		var tilt: Basis = c.tilt_basis()
		var top: Vector3 = c.top_centre()
		for k: int in SEGMENTS:
			var a0: float = TAU * k / SEGMENTS
			var a1: float = TAU * (k + 1) / SEGMENTS
			var r0: Vector3 = tilt * Vector3(cos(a0) * c.radius, 0.0, sin(a0) * c.radius)
			var r1: Vector3 = tilt * Vector3(cos(a1) * c.radius, 0.0, sin(a1) * c.radius)
			shell.append_array([c.base + r0, c.base + r1, top + r1, c.base + r0, top + r1, top + r0])
			shell.append_array([top, top + r0, top + r1])
			for centre: Vector3 in [c.base, top]:
				_add_bar(edges, centre + r0, centre + r1, 0.03)
		# The axis and four lines up the side.
		_add_bar(edges, c.base, top, 0.03)
		for k: int in 4:
			var r: Vector3 = tilt * Vector3(cos(TAU * k / 4) * c.radius, 0.0, sin(TAU * k / 4) * c.radius)
			_add_bar(edges, c.base + r, top + r, 0.03)
	_set_mesh(_cylinders, shell)
	_set_mesh(_cylinder_edges, edges)


func hide_cylinders() -> void:
	_set_mesh(_cylinders, PackedVector3Array())
	_set_mesh(_cylinder_edges, PackedVector3Array())


func clear_all() -> void:
	hide_line()
	show_not_visible(null, [] as Array[int])
	_set_mesh(_marks, PackedVector3Array())


## A bar of square section from a to b.
static func _add_bar(vertices: PackedVector3Array, a: Vector3, b: Vector3, width: float) -> void:
	var along: Vector3 = b - a
	if along.length_squared() < 1e-10:
		return
	var helper: Vector3 = Vector3.UP if absf(along.normalized().y) < 0.9 else Vector3.RIGHT
	var u: Vector3 = along.cross(helper).normalized() * (width / 2.0)
	var v: Vector3 = along.cross(u).normalized() * (width / 2.0)
	var corners: Array[Vector3] = [u + v, u - v, -u - v, -u + v]
	for k: int in 4:
		var c0: Vector3 = corners[k]
		var c1: Vector3 = corners[(k + 1) % 4]
		vertices.append_array([a + c0, b + c0, b + c1, a + c0, b + c1, a + c1])


## A small diamond (octahedron) at p.
static func _add_dot(vertices: PackedVector3Array, p: Vector3, size: float) -> void:
	var tips: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]
	for k: int in 4:
		var a: Vector3 = p + tips[k] * size
		var b: Vector3 = p + tips[(k + 1) % 4] * size
		vertices.append_array([a, b, p + Vector3.UP * size, a, b, p + Vector3.DOWN * size])


static func _add_ring(vertices: PackedVector3Array, centre: Vector3, radius: float, width: float) -> void:
	var inner: float = radius - width / 2.0
	var outer: float = radius + width / 2.0
	for k: int in SEGMENTS:
		var d0: Vector3 = Vector3(cos(TAU * k / SEGMENTS), 0, sin(TAU * k / SEGMENTS))
		var d1: Vector3 = Vector3(cos(TAU * (k + 1) / SEGMENTS), 0, sin(TAU * (k + 1) / SEGMENTS))
		vertices.append_array([
			centre + d0 * inner, centre + d1 * inner, centre + d1 * outer,
			centre + d0 * inner, centre + d1 * outer, centre + d0 * outer,
		])


static func _set_mesh(instance: MeshInstance3D, vertices: PackedVector3Array) -> void:
	if vertices.is_empty():
		instance.mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = mesh


func _child(child_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var child: MeshInstance3D = MeshInstance3D.new()
	child.name = child_name
	child.material_override = material
	child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(child)
	return child


static func _material(colour: Color, priority: int, on_top: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	material.no_depth_test = on_top
	return material
