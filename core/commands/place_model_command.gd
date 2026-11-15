class_name PlaceModelCommand
extends Command
## Adds a model to the table. Rejected unless it stands somewhere a move could
## end (see HeightField.stoppable(): on a floor, half the base supported,
## headroom, no overlap with terrain), or if its cylinder would overlap another
## model's or its base reach past the table edge. Touching is allowed.

const EPSILON: float = 0.0001

var player: int
var position: Vector3
var base_mm: int
## Movement characteristic, inches.
var movement: float
## Id of the placed model, set by apply().
var placed_model_id: int = -1


func _init(
	p_player: int, p_position: Vector3, p_base_mm: int, p_movement: float = 6.0
) -> void:
	player = p_player
	position = p_position
	base_mm = p_base_mm
	movement = p_movement


func validate(state: GameState) -> String:
	if player != 0 and player != 1:
		return "Player must be 0 or 1, got %d." % player
	if not BaseSizes.is_known(base_mm):
		return "Unknown base size: %d mm." % base_mm
	if movement < 0.0:
		return "Movement must not be negative, got %s." % movement

	var radius: float = BaseSizes.mm_to_inches(base_mm) / 2.0
	if (
		position.x - radius < -EPSILON
		or position.z - radius < -EPSILON
		or position.x + radius > state.table_width + EPSILON
		or position.z + radius > state.table_depth + EPSILON
		or position.y < -EPSILON
	):
		return "Base would lie outside the table."

	var height: float = BaseSizes.height_inches(base_mm)
	var field: HeightField = state.height_field()
	var at: Vector2 = Vector2(position.x, position.z)
	var standing: bool = false
	for surface: int in field.surfaces_matching(at, position.y):
		if field.stoppable(at, surface, radius, height):
			standing = true
	if not standing:
		return "The model must stand on a floor where it could end a move."
	for other: ModelState in state.models:
		if _cylinders_overlap(position, radius, height, other):
			return "Base would overlap model %d." % other.id
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	placed_model_id = state.add_model(player, position, base_mm, movement).id
	return []


static func _cylinders_overlap(
	pos: Vector3, radius: float, height: float, other: ModelState
) -> bool:
	var horizontal: float = Vector2(pos.x - other.position.x, pos.z - other.position.z).length()
	if horizontal >= radius + other.base_radius_inches() - EPSILON:
		return false
	var vertical_apart: bool = (
		pos.y + height <= other.position.y + EPSILON
		or other.position.y + other.height_inches() <= pos.y + EPSILON
	)
	return not vertical_apart
