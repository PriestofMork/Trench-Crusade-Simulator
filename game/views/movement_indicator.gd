class_name MovementIndicator
extends MeshInstance3D
## Draws where the selected model's base edge can reach, XCOM style: a crisp
## blue outline with a soft glow on its inner side and a faint fill. One layer
## per floor (ReachField.contour_layers()), each drawn on its own surface: on a
## platform on the platform, on a ramp lying on the ramp, under a bridge and on
## it both. Built with marching squares from the layer's contour values (the
## centre's area grown by the base radius), then clipped to where that surface
## can be seen, so the edge follows terrain, other models and the remaining
## movement smoothly instead of in steps.

const FILL_COLOUR: Color = Color(0.15, 0.5, 1.0, 0.17)
const GLOW_COLOUR: Color = Color(0.3, 0.65, 1.0, 0.5)
const LINE_COLOUR: Color = Color(0.6, 0.86, 1.0, 1.0)
## Outline width and inner glow width, inches.
const LINE_WIDTH: float = 0.08
const GLOW_WIDTH: float = 0.5
## Height above the surface, inches. The outline sits a little above the fill,
## both far enough above the terrain not to flicker against it.
const FILL_HEIGHT: float = 0.02
const LINE_HEIGHT: float = 0.035
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
## `layers` are field.contour_layers(), passed in when already computed.
func show_field(field: ReachField, layers: Array[ReachField.Layer] = []) -> void:
	if field == null or field.node_count() == 0:
		mesh = null
		return
	if layers.is_empty():
		layers = field.contour_layers()
	var fill: PackedVector3Array = PackedVector3Array()
	var fill_colours: PackedColorArray = PackedColorArray()
	var line: PackedVector3Array = PackedVector3Array()
	var line_colours: PackedColorArray = PackedColorArray()
	for layer: ReachField.Layer in layers:
		var contour: MarchingSquares.Contour = _layer_contour(layer, field)
		_add_fill(fill, fill_colours, contour, layer, field)
		_add_outline(line, line_colours, contour, layer, field)
	var array_mesh: ArrayMesh = ArrayMesh.new()
	for part: Array in [[fill, fill_colours, _fill_material], [line, line_colours, _line_material]]:
		var vertices: PackedVector3Array = part[0]
		if vertices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = part[1]
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, part[2])
	mesh = array_mesh


## Contour where the centre may end, grown by the base radius (the area the
## base edge can touch), clipped to the visible surface. Values stay in inches
## for the glow.
func _layer_contour(layer: ReachField.Layer, field: ReachField) -> MarchingSquares.Contour:
	var centre: MarchingSquares.Contour = MarchingSquares.build(layer.values, layer.size_x, layer.size_z)
	var grown: PackedFloat32Array = MarchingSquares.grown_values(
		layer.values, layer.size_x, layer.size_z, centre, field.base_radius() / field.cell_size
	)
	for k: int in grown.size():
		grown[k] = maxf(grown[k] * field.cell_size, layer.clip[k])
	return MarchingSquares.build(grown, layer.size_x, layer.size_z)


func _add_fill(
	vertices: PackedVector3Array, colours: PackedColorArray, contour: MarchingSquares.Contour,
	layer: ReachField.Layer, field: ReachField
) -> void:
	for k: int in contour.triangles.size():
		vertices.append(_on_surface(_to_table(contour.triangles[k], layer, field), layer, field, FILL_HEIGHT))
		var depth: float = maxf(-contour.triangle_values[k], 0.0)
		var glow: float = clampf(1.0 - depth / GLOW_WIDTH, 0.0, 1.0)
		colours.append(FILL_COLOUR.lerp(GLOW_COLOUR, glow * glow))


func _add_outline(
	vertices: PackedVector3Array, colours: PackedColorArray, contour: MarchingSquares.Contour,
	layer: ReachField.Layer, field: ReachField
) -> void:
	for c: int in contour.chains.size():
		var points: PackedVector2Array = _table_points(contour.chains[c], layer, field, contour.closed[c])
		if points.size() < 2:
			continue
		var closed: bool = contour.closed[c] and points.size() >= 3
		var normals: PackedVector2Array = _vertex_normals(points, closed)
		var segment_count: int = points.size() if closed else points.size() - 1
		var half: float = LINE_WIDTH * 0.5
		for s: int in segment_count:
			var a: int = s
			var b: int = (s + 1) % points.size()
			var corners: Array[Vector2] = [
				points[a] - normals[a] * half, points[b] - normals[b] * half,
				points[b] + normals[b] * half, points[a] + normals[a] * half,
			]
			var v: Array[Vector3] = []
			for corner: Vector2 in corners:
				v.append(_on_surface(corner, layer, field, LINE_HEIGHT))
			vertices.append_array([v[0], v[1], v[2], v[0], v[2], v[3]])
			for _k: int in 6:
				colours.append(LINE_COLOUR)


## Chain in layer grid coordinates -> table points (world x, z), with
## near-duplicate points merged so the miters stay well behaved.
func _table_points(
	chain: PackedVector2Array, layer: ReachField.Layer, field: ReachField, closed: bool
) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in chain:
		var q: Vector2 = _to_table(p, layer, field)
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


static func _to_table(grid_point: Vector2, layer: ReachField.Layer, field: ReachField) -> Vector2:
	return field.origin + (grid_point + Vector2(layer.ix0, layer.iz0)) * field.cell_size


static func _on_surface(p: Vector2, layer: ReachField.Layer, field: ReachField, lift: float) -> Vector3:
	return Vector3(p.x, field.surface_height(layer.surface, p) + lift, p.y)


func _make_material(priority: int) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	return material
