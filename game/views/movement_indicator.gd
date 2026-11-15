class_name MovementIndicator
extends MeshInstance3D
## Draws where the selected model's base centre can move to, XCOM style: a crisp
## blue outline with a soft glow on its inner side and a faint fill. Built from
## a ReachField's contour values with marching squares, so the edge follows
## terrain, other models and the remaining movement smoothly instead of in steps.
## The contour values are roughly the distance in inches to the edge, so the
## glow is a gradient on the fill itself and stays even in corners and corridors.

const FILL_COLOUR: Color = Color(0.15, 0.5, 1.0, 0.17)
const GLOW_COLOUR: Color = Color(0.3, 0.65, 1.0, 0.5)
const LINE_COLOUR: Color = Color(0.6, 0.86, 1.0, 1.0)
## Outline width and inner glow width, inches.
const LINE_WIDTH: float = 0.08
const GLOW_WIDTH: float = 0.5
## Height above the table, inches. The outline sits a hair above the fill.
const FILL_HEIGHT: float = 0.012
const LINE_HEIGHT: float = 0.02
## Outline points closer together than this are merged, inches.
const MIN_POINT_SPACING: float = 0.04

var _fill_material: StandardMaterial3D
var _line_material: StandardMaterial3D


func _init() -> void:
	name = "MovementIndicator"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill_material = _make_material(0)
	_line_material = _make_material(1)


## Rebuilds the indicator for `field`, or clears it if `field` is null.
func show_field(field: ReachField) -> void:
	if field == null or field.node_count() == 0:
		mesh = null
		return
	var contour: MarchingSquares.Contour = MarchingSquares.build(
		field.contour_values(), field.size_x, field.size_z
	)
	var array_mesh: ArrayMesh = ArrayMesh.new()
	_add_fill(array_mesh, contour, field)
	_add_outline(array_mesh, contour, field)
	mesh = array_mesh
	if array_mesh.get_surface_count() > 0:
		array_mesh.surface_set_material(0, _fill_material)
	if array_mesh.get_surface_count() > 1:
		array_mesh.surface_set_material(1, _line_material)


func _add_fill(array_mesh: ArrayMesh, contour: MarchingSquares.Contour, field: ReachField) -> void:
	if contour.triangles.is_empty():
		return
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.resize(contour.triangles.size())
	for k: int in contour.triangles.size():
		vertices[k] = _to_table(contour.triangles[k], field, FILL_HEIGHT)
	var colours: PackedColorArray = PackedColorArray()
	colours.resize(vertices.size())
	for k: int in vertices.size():
		var depth: float = maxf(-contour.triangle_values[k], 0.0)
		var glow: float = clampf(1.0 - depth / GLOW_WIDTH, 0.0, 1.0)
		colours[k] = FILL_COLOUR.lerp(GLOW_COLOUR, glow * glow)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _add_outline(array_mesh: ArrayMesh, contour: MarchingSquares.Contour, field: ReachField) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	var colours: PackedColorArray = PackedColorArray()
	for c: int in contour.chains.size():
		var points: PackedVector2Array = _table_points(contour.chains[c], field, contour.closed[c])
		if points.size() < 2:
			continue
		var closed: bool = contour.closed[c] and points.size() >= 3
		var normals: PackedVector2Array = _vertex_normals(points, closed)
		var segment_count: int = points.size() if closed else points.size() - 1
		var half: float = LINE_WIDTH * 0.5
		for s: int in segment_count:
			var a: int = s
			var b: int = (s + 1) % points.size()
			_quad(vertices, colours,
				points[a] - normals[a] * half, points[b] - normals[b] * half,
				points[b] + normals[b] * half, points[a] + normals[a] * half,
				LINE_COLOUR, LINE_COLOUR)
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Chain in grid coordinates -> table points (world x, z), with near-duplicate
## points merged so the miters stay well behaved.
func _table_points(chain: PackedVector2Array, field: ReachField, closed: bool) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in chain:
		var q: Vector2 = field.origin + p * field.cell_size
		if points.is_empty() or points[points.size() - 1].distance_to(q) >= MIN_POINT_SPACING:
			points.append(q)
	if closed and points.size() > 2 and points[0].distance_to(points[points.size() - 1]) < MIN_POINT_SPACING:
		points.remove_at(points.size() - 1)
	return points


## Mitered inside normals at each point, so the ribbon keeps its width round bends.
func _vertex_normals(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var n: int = points.size()
	var segment_normals: PackedVector2Array = PackedVector2Array()
	var segment_count: int = n if closed else n - 1
	for s: int in segment_count:
		segment_normals.append(MarchingSquares.inside_normal(points[s], points[(s + 1) % n]))
	var normals: PackedVector2Array = PackedVector2Array()
	normals.resize(n)
	for i: int in n:
		var before: Vector2
		var after: Vector2
		if closed:
			before = segment_normals[(i - 1 + n) % n]
			after = segment_normals[i % n]
		else:
			before = segment_normals[maxi(i - 1, 0)]
			after = segment_normals[mini(i, segment_count - 1)]
		var sum: Vector2 = before + after
		if sum.length_squared() < 0.0001:
			normals[i] = after
			continue
		var miter: Vector2 = sum.normalized()
		normals[i] = miter / maxf(miter.dot(after), 0.5)
	return normals


func _to_table(grid_point: Vector2, field: ReachField, height: float) -> Vector3:
	var p: Vector2 = field.origin + grid_point * field.cell_size
	return Vector3(p.x, field.start.y + height, p.y)


func _quad(
	vertices: PackedVector3Array, colours: PackedColorArray,
	a: Vector2, b: Vector2, c: Vector2, d: Vector2, edge_colour: Color, far_colour: Color
) -> void:
	var y: float = LINE_HEIGHT
	var va: Vector3 = Vector3(a.x, y, a.y)
	var vb: Vector3 = Vector3(b.x, y, b.y)
	var vc: Vector3 = Vector3(c.x, y, c.y)
	var vd: Vector3 = Vector3(d.x, y, d.y)
	vertices.append_array([va, vb, vc, va, vc, vd])
	colours.append_array([edge_colour, edge_colour, far_colour, edge_colour, far_colour, far_colour])


func _make_material(priority: int) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	return material
