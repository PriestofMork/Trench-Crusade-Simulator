class_name PathPreview
extends Node3D
## The hover preview for a move: the path from the model to the cursor, with
## its climbs and drops drawn as vertical parts, and a ghost of the base at the
## destination (lying on its floor), blue if it can go there, orange if only
## with rolls, red if not. A route with rolls shows a numbered marker at each
## roll point, in the order they are rolled.

const PATH_COLOUR: Color = Color(0.85, 0.94, 1.0, 1.0)
const RISKY_PATH_COLOUR: Color = Color(1.0, 0.82, 0.55, 1.0)
const GHOST_OK_COLOUR: Color = Color(0.45, 0.78, 1.0)
const GHOST_RISKY_COLOUR: Color = Color(1.0, 0.6, 0.2)
const GHOST_BAD_COLOUR: Color = Color(1.0, 0.28, 0.22)
const MARKER_COLOUR: Color = Color(1.0, 0.55, 0.12)
const MARKER_RADIUS: float = 0.32
const PATH_WIDTH: float = 0.07
const RING_WIDTH: float = 0.07
const HEIGHT: float = 0.03
const RING_SEGMENTS: int = 64

var _path_mesh: MeshInstance3D
var _ghost_fill: MeshInstance3D
var _ghost_ring: MeshInstance3D
var _fill_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _path_material: StandardMaterial3D
var _marker_material: StandardMaterial3D
var _markers: Array[Node3D] = []
var _radius: float = -1.0


func _init() -> void:
	name = "PathPreview"
	_path_material = _make_material(PATH_COLOUR, 3)
	_path_mesh = _make_child("Path", _path_material)
	_marker_material = _make_material(MARKER_COLOUR, 4)
	_marker_material.no_depth_test = true
	_fill_material = _make_material(GHOST_OK_COLOUR, 2)
	_ring_material = _make_material(GHOST_OK_COLOUR, 3)
	_ghost_fill = _make_child("GhostFill", _fill_material)
	_ghost_ring = _make_child("GhostRing", _ring_material)
	hide_all()


func hide_all() -> void:
	_path_mesh.visible = false
	_ghost_fill.visible = false
	_ghost_ring.visible = false
	for marker: Node3D in _markers:
		marker.visible = false


## Numbered markers at the roll points (in order); none if `points` is empty.
func show_roll_points(points: Array[Vector3]) -> void:
	while _markers.size() < points.size():
		var marker: Node3D = Node3D.new()
		marker.name = "RollPoint%d" % (_markers.size() + 1)
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.mesh = _ring_mesh_sized(MARKER_RADIUS, 0.1)
		ring.material_override = _marker_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(ring)
		var label: Label3D = Label3D.new()
		label.name = "Number"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0014
		label.font_size = 30
		label.outline_size = 10
		label.modulate = MARKER_COLOUR.lerp(Color.WHITE, 0.4)
		label.position = Vector3(0, 0.55, 0)
		marker.add_child(label)
		add_child(marker)
		_markers.append(marker)
	for i: int in _markers.size():
		var marker: Node3D = _markers[i]
		marker.visible = i < points.size()
		if marker.visible:
			marker.position = points[i] + Vector3(0, HEIGHT * 2.0, 0)
			(marker.get_node("Number") as Label3D).text = str(i + 1)


## Shows the ghost base at `destination` and, if `path` is not empty, the path
## from `start` through it (points as they should be drawn, vertical parts
## included). `floor_normal` is the up direction of the floor at the destination.
func show_preview(
	start: Vector3, path: Array[Vector3], destination: Vector3, base_radius: float,
	floor_normal: Vector3 = Vector3.UP, risky: bool = false
) -> void:
	if not is_equal_approx(base_radius, _radius):
		_radius = base_radius
		_ghost_fill.mesh = _disc_mesh(base_radius)
		_ghost_ring.mesh = _ring_mesh(base_radius)
	var reachable: bool = not path.is_empty()
	var colour: Color = (GHOST_RISKY_COLOUR if risky else GHOST_OK_COLOUR) if reachable else GHOST_BAD_COLOUR
	_path_material.albedo_color = RISKY_PATH_COLOUR if risky else PATH_COLOUR
	_fill_material.albedo_color = Color(colour, 0.22)
	_ring_material.albedo_color = Color(colour, 0.95)
	var tilt: Basis = Basis(Quaternion(Vector3.UP, floor_normal.normalized()))
	var at: Vector3 = destination + floor_normal.normalized() * HEIGHT
	_ghost_fill.transform = Transform3D(tilt, at)
	_ghost_ring.transform = Transform3D(tilt, at)
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
		var flat: Vector3 = Vector3(along.x, 0, along.z)
		if flat.length() < 0.001:
			# Straight up or down: two crossed ribbons, so it shows from any side.
			for side: Vector3 in [Vector3(half, 0, 0), Vector3(0, 0, half)]:
				vertices.append_array([a - side, b - side, b + side, a - side, b + side, a + side])
			continue
		var side: Vector3 = Vector3(-along.z, 0, along.x).normalized() * half
		vertices.append_array([a - side, b - side, b + side, a - side, b + side, a + side])
		# A round-ish joint: a small square turned to the segment, enough at this width.
		if i > 0:
			var fwd: Vector3 = flat.normalized() * half
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
	return _ring_mesh_sized(radius, RING_WIDTH)


func _ring_mesh_sized(radius: float, width: float) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var inner: float = radius - width * 0.5
	var outer: float = radius + width * 0.5
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
