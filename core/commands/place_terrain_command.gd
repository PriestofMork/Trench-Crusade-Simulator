class_name PlaceTerrainCommand
extends Command
## Adds a terrain piece to the table.

var center: Vector3
var size: Vector3
var rotation: float
var blocks_movement: bool
## Id of the placed piece, set by apply().
var placed_terrain_id: int = -1


func _init(
	p_center: Vector3, p_size: Vector3, p_rotation: float = 0.0, p_blocks_movement: bool = true
) -> void:
	center = p_center
	size = p_size
	rotation = p_rotation
	blocks_movement = p_blocks_movement


func validate(_state: GameState) -> String:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return "Terrain size must be positive, got %s." % str(size)
	return ""


func apply(state: GameState) -> void:
	placed_terrain_id = state.add_terrain(center, size, rotation, blocks_movement).id
