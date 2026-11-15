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
## Movement characteristic, inches.
var movement: float
## Whether the model is Down (docs/rules/markers.md).
var down: bool = false
## Taken Out of Action (ruling 3 of brief 006): off the table for good. It no
## longer activates, blocks or counts as standing; its record stays here.
var out_of_action: bool = false
## Marker counts by kind (see Markers); kinds not present count as 0.
var markers: Dictionary[StringName, int] = {}


func _init(
	p_id: int, p_player: int, p_position: Vector3, p_base_mm: int, p_movement: float = 6.0
) -> void:
	id = p_id
	player = p_player
	position = p_position
	base_mm = p_base_mm
	movement = p_movement


## Whether the model is still on the table (not Out of Action).
func on_table() -> bool:
	return not out_of_action


func base_diameter_inches() -> float:
	return BaseSizes.mm_to_inches(base_mm)


func base_radius_inches() -> float:
	return base_diameter_inches() / 2.0


func height_inches() -> float:
	return BaseSizes.height_inches(base_mm)


func marker_count(kind: StringName) -> int:
	return markers.get(kind, 0)


## Only for commands and rules: sets a marker count, clamped to 0..Markers.CAP.
func set_markers(kind: StringName, count: int) -> void:
	markers[kind] = clampi(count, 0, Markers.CAP)
