class_name PlaceTerrainCommand
extends Command
## Adds a terrain piece to the table. See TerrainPiece for what the fields mean.

var footprint_center: Vector2
## Footprint size along the piece's own x and z axes in x and z, height in y.
var size: Vector3
var rotation: float
var base_height: float
var tag: TerrainPiece.Tag
var shape: TerrainPiece.Shape
var blocks_sight: bool
## Id of the placed piece, set by apply().
var placed_terrain_id: int = -1


func _init(
	p_footprint_center: Vector2,
	p_size: Vector3,
	p_rotation: float = 0.0,
	p_base_height: float = 0.0,
	p_tag: TerrainPiece.Tag = TerrainPiece.Tag.NONE,
	p_shape: TerrainPiece.Shape = TerrainPiece.Shape.BOX,
	p_blocks_sight: bool = true
) -> void:
	footprint_center = p_footprint_center
	size = p_size
	rotation = p_rotation
	base_height = p_base_height
	tag = p_tag
	shape = p_shape
	blocks_sight = p_blocks_sight


func validate(_state: GameState) -> String:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return "Terrain size must be positive, got %s." % str(size)
	if base_height < 0.0:
		return "Terrain may not reach below the table, got base height %s." % base_height
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	placed_terrain_id = state.add_terrain(
		footprint_center, Vector2(size.x, size.z), rotation, base_height, size.y, tag, shape, blocks_sight
	).id
	return []
