class_name PathPreview
extends Node3D
## The hover preview for a move: the path from the model to the cursor and a
## ghost of the base at the destination, blue if it can go there, red if not.

const PATH_COLOUR: Color = Color(0.85, 0.94, 1.0, 1.0)
const GHOST_OK_COLOUR: Color = Color(0.45, 0.78, 1.0)
const GHOST_BAD_COLOUR: Color = Color(1.0, 0.28, 0.22)
const PATH_WIDTH: float = 0.07
const RING_WIDTH: float = 0.07
const HEIGHT: float = 0.03
const RING_SEGMENTS: int = 64

var _path_mesh: MeshInstance3D
var _ghost_fill: MeshInstance3D
var _ghost_ring: MeshInstance3D
var _fill_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _radius: float = -1.0


func _init() -> void:
	name = "PathPreview"
	_path_mesh = _make_child("Path", _make_material(PATH_COLOUR, 3))
	_fill_material = _make_material(GHOST_OK_COLOUR, 2)
	_ring_material = _make_material(GHOST_OK_COLOUR, 3)
	_ghost_fill = _make_child("GhostFill", _fill_material)
	_ghost_ring = _make_child("GhostRing", _ring_material)
	hide_all()


func hide_all() -> void:
	_path_mesh.visible = false
	_ghost_fill.visible = false
	_ghost_ring.visible = false


## Shows the ghost base at `destination` and, if `path` is not empty, the path
## from `start` through it.
func show_preview(start: Vector3, path: Array[Vector3], destination: Vector3, base_radius: float) -> void:
	if not is_equal_approx(base_radius, _radius):
		_radius = base_radius
		_ghost_fill.mesh = _disc_mesh(base_radius)
		_ghost_ring.mesh = _ring_mesh(base_radius)
	var reachable: bool = not path.is_empty()
	var colour: Color = GHOST_OK_COLOUR if reachable else GHOST_BAD_COLOUR
	_fill_material.albedo_color = Color(colour, 0.22)
	_ring_material.albedo_color = Color(colour, 0.95)
	var at: Vector3 = Vector3(destination.x, destination.y + HEIGHT, destination.z)
	_ghost_fill.position = at
	_ghost_ring.position = at
	_ghost_fill.visible = true
	_ghost_ring.visible = true
	if reachable:
		var points: Array[Vector3] = [start]
		points.append_array(path)
		_path_mesh.mesh = _polyline_mesh(points)
		_path_mesh.visible = true
	else:
		_path_mesh.visible = false


func _polyline_mesh(points: Array[Vector3]) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var half: float = PATH_WIDTH * 0.5
	for i: int in points.size() - 1:
		var a: Vector3 = points[i] + Vector3(0, HEIGHT, 0)
		var b: Vector3 = points[i + 1] + Vector3(0, HEIGHT, 0)
		var along: Vector3 = b - a
		if along.length_squared() < 0.000001:
			continue
		var side: Vector3 = Vector3(-along.z, 0, along.x).normalized() * half
		vertices.append_array([a - side, b - side, b + side, a - side, b + side, a + side])
		# A round-ish joint: a small square turned to the segment, enough at this width.
		if i > 0:
			var fwd: Vector3 = along.normalized() * half
			vertices.append_array([a - side - fwd, a - side, a + side, a - side - fwd, a + side, a + side - fwd])
	var mesh: ArrayMesh = ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _disc_mesh(radius: float) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	for k: int in RING_SEGMENTS:
		var a0: float = TAU * k / RING_SEGMENTS
		var a1: float = TAU * (k + 1) / RING_SEGMENTS
		vertices.append_array([
			Vector3.ZERO,
			Vector3(cos(a0), 0, sin(a0)) * radius,
			Vector3(cos(a1), 0, sin(a1)) * radius,
		])
	return _mesh_from(vertices)


func _ring_mesh(radius: float) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var inner: float = radius - RING_WIDTH * 0.5
	var outer: float = radius + RING_WIDTH * 0.5
	for k: int in RING_SEGMENTS:
		var d0: Vector3 = Vector3(cos(TAU * k / RING_SEGMENTS), 0, sin(TAU * k / RING_SEGMENTS))
		var d1: Vector3 = Vector3(cos(TAU * (k + 1) / RING_SEGMENTS), 0, sin(TAU * (k + 1) / RING_SEGMENTS))
		vertices.append_array([d0 * inner, d1 * inner, d1 * outer, d0 * inner, d1 * outer, d0 * outer])
	return _mesh_from(vertices)


func _mesh_from(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_child(child_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var child: MeshInstance3D = MeshInstance3D.new()
	child.name = child_name
	child.material_override = material
	child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(child)
	return child


func _make_material(colour: Color, priority: int) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	return material
