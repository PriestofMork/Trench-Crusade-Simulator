class_name TerrainView
extends MeshInstance3D
## Draws one TerrainPiece: a box, or a wedge for a ramp (its top rising along
## the piece's own x axis). Tagged pieces are tinted so tags show while testing.

const OPEN_COLOUR: Color = Color(0.5, 0.5, 0.48)
const LOW_OBSTACLE_COLOUR: Color = Color(0.62, 0.56, 0.42)
const TAG_COLOURS: Dictionary[TerrainPiece.Tag, Color] = {
	TerrainPiece.Tag.SHEER: Color(0.72, 0.3, 0.26),
	TerrainPiece.Tag.LADDER: Color(0.86, 0.66, 0.22),
	TerrainPiece.Tag.IMPASSABLE: Color(0.24, 0.16, 0.3),
}


func setup(piece: TerrainPiece) -> void:
	name = "Terrain%d" % piece.id
	if piece.shape == TerrainPiece.Shape.RAMP:
		mesh = _wedge_mesh(piece)
		position = Vector3(piece.footprint_center.x, piece.base_height, piece.footprint_center.y)
	else:
		var box: BoxMesh = BoxMesh.new()
		box.size = piece.bounds_size()
		mesh = box
		position = piece.bounds_center()
	rotation = Vector3(0.0, piece.rotation, 0.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour_for(piece)
	if not piece.blocks_sight:
		# See-through for sight (brief 008): drawn see-through too.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.35
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material


static func colour_for(piece: TerrainPiece) -> Color:
	if TAG_COLOURS.has(piece.tag):
		return TAG_COLOURS[piece.tag]
	if piece.shape == TerrainPiece.Shape.BOX and piece.height <= TerrainRules.LOW_OBSTACLE_HEIGHT:
		return LOW_OBSTACLE_COLOUR
	return OPEN_COLOUR


## A wedge in the piece's own frame, underside at y = 0.
static func _wedge_mesh(piece: TerrainPiece) -> ArrayMesh:
	var hx: float = piece.footprint_size.x / 2.0
	var hz: float = piece.footprint_size.y / 2.0
	var h: float = piece.height
	# Bottom corners, then the top edge at the high end (+x).
	var b0: Vector3 = Vector3(-hx, 0, -hz)
	var b1: Vector3 = Vector3(hx, 0, -hz)
	var b2: Vector3 = Vector3(hx, 0, hz)
	var b3: Vector3 = Vector3(-hx, 0, hz)
	var t1: Vector3 = Vector3(hx, h, -hz)
	var t2: Vector3 = Vector3(hx, h, hz)
	var inside: Vector3 = Vector3(hx / 3.0, h / 3.0, 0)  # the centroid
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangles(tool, inside, [b0, t2, t1, b0, b3, t2])  # slope
	_triangles(tool, inside, [b1, t1, t2, b1, t2, b2])  # high end
	_triangles(tool, inside, [b0, t1, b1])  # side -z
	_triangles(tool, inside, [b3, b2, t2])  # side +z
	_triangles(tool, inside, [b0, b1, b2, b0, b2, b3])  # underside
	return tool.commit()


## Adds triangles with flat normals pointing away from `inside`, wound so the
## outside is the front face.
static func _triangles(tool: SurfaceTool, inside: Vector3, points: Array[Vector3]) -> void:
	for k: int in range(0, points.size(), 3):
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var c: Vector3 = points[k + 2]
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		if normal.dot((a + b + c) / 3.0 - inside) < 0.0:
			normal = -normal
		else:
			# Godot's front faces wind clockwise seen from outside.
			var swap: Vector3 = b
			b = c
			c = swap
		for p: Vector3 in [a, b, c]:
			tool.set_normal(normal)
			tool.add_vertex(p)
