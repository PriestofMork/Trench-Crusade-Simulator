class_name GameState
extends RefCounted
## The whole state of a game. Plain data; changed only by applying commands
## through execute().

const DEFAULT_TABLE_SIZE_INCHES: float = 48.0

## The table spans x in [0, table_width] and z in [0, table_depth], inches.
## The tabletop is the plane y = 0.
var table_width: float
var table_depth: float
var models: Array[ModelState] = []
var terrain: Array[TerrainPiece] = []
var dice: Dice

var _next_model_id: int = 1
var _next_terrain_id: int = 1


func _init(
	seed_value: int = 0,
	p_table_width: float = DEFAULT_TABLE_SIZE_INCHES,
	p_table_depth: float = DEFAULT_TABLE_SIZE_INCHES
) -> void:
	dice = Dice.new(seed_value)
	table_width = p_table_width
	table_depth = p_table_depth


## Validates and, if valid, applies a command. Returns "" on success or the
## reason the command was rejected.
func execute(command: Command) -> String:
	var error: String = command.validate(self)
	if error != "":
		return error
	command.apply(self)
	return ""


func get_model(id: int) -> ModelState:
	for model: ModelState in models:
		if model.id == id:
			return model
	return null


## Only for commands: adds a model and returns it.
func add_model(
	player: int, position: Vector3, base_mm: int, movement: float = 6.0
) -> ModelState:
	var model: ModelState = ModelState.new(_next_model_id, player, position, base_mm, movement)
	_next_model_id += 1
	models.append(model)
	return model


## Only for commands: adds a terrain piece and returns it.
func add_terrain(
	footprint_center: Vector2,
	footprint_size: Vector2,
	rotation: float,
	base_height: float,
	height: float,
	tag: TerrainPiece.Tag,
	shape: TerrainPiece.Shape
) -> TerrainPiece:
	var piece: TerrainPiece = TerrainPiece.new(
		_next_terrain_id, footprint_center, footprint_size, rotation, base_height, height, tag, shape
	)
	_next_terrain_id += 1
	terrain.append(piece)
	return piece
