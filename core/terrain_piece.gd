class_name TerrainPiece
extends RefCounted
## One piece of terrain as the rules see it: a box standing on the table,
## turned about the vertical axis. Plain data; the 3D scene and every rules
## check are built from it.

var id: int
## Centre of the box, inches. The box stands on the table when center.y == size.y / 2.
var center: Vector3
## Full size along the box's own x, y and z axes, inches.
var size: Vector3
## Rotation about the vertical axis, radians, with the same sign as Node3D.rotation.y.
var rotation: float
## Whether models may not move through it.
var blocks_movement: bool


func _init(
	p_id: int, p_center: Vector3, p_size: Vector3, p_rotation: float, p_blocks_movement: bool
) -> void:
	id = p_id
	center = p_center
	size = p_size
	rotation = p_rotation
	blocks_movement = p_blocks_movement


## Footprint centre on the table plane (world x, z).
func footprint_center() -> Vector2:
	return Vector2(center.x, center.z)


## Half the footprint along the box's own x and z axes.
func footprint_half_extents() -> Vector2:
	return Vector2(size.x, size.z) / 2.0
