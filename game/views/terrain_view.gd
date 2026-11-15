class_name TerrainView
extends MeshInstance3D
## Draws one TerrainPiece as a plain box.

const BLOCKING_COLOUR: Color = Color(0.5, 0.5, 0.48)
const OPEN_COLOUR: Color = Color(0.42, 0.45, 0.36)


func setup(piece: TerrainPiece) -> void:
	name = "Terrain%d" % piece.id
	var box: BoxMesh = BoxMesh.new()
	box.size = piece.size
	mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = BLOCKING_COLOUR if piece.blocks_movement else OPEN_COLOUR
	material_override = material
	position = piece.center
	rotation = Vector3(0.0, piece.rotation, 0.0)
