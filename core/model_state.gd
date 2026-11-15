class_name ModelState
extends RefCounted
## One model on the table, as the rules see it: a vertical cylinder standing on
## its base. Plain data; changed only by commands.

var id: int
## Owning player, 0 or 1.
var player: int
## Centre of the base's underside, in inches.
var position: Vector3
## Base diameter in millimetres, as stored in data.
var base_mm: int


func _init(p_id: int, p_player: int, p_position: Vector3, p_base_mm: int) -> void:
	id = p_id
	player = p_player
	position = p_position
	base_mm = p_base_mm


func base_diameter_inches() -> float:
	return BaseSizes.mm_to_inches(base_mm)


func base_radius_inches() -> float:
	return base_diameter_inches() / 2.0


func height_inches() -> float:
	return BaseSizes.height_inches(base_mm)
