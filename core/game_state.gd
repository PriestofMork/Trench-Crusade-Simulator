class_name GameState
extends RefCounted
## The whole state of a game. Plain data; changed only by applying commands
## through execute() or submit().

const DEFAULT_TABLE_SIZE_INCHES: float = 48.0

## The table spans x in [0, table_width] and z in [0, table_depth], inches.
## The tabletop is the plane y = 0.
var table_width: float
var table_depth: float
var models: Array[ModelState] = []
var terrain: Array[TerrainPiece] = []
var dice: Dice
## The rules in play: actions, roll modifiers, choices and reactions.
var rules: Ruleset
var turn: TurnState = TurnState.new()
## Warband-wide state, indexed by player.
var warbands: Array[WarbandState] = [WarbandState.new(0), WarbandState.new(1)]
## What core is waiting for, or null.
var pending: PendingDecision = null
## The roll under way (waiting for pre-roll choices), or null.
var active_roll: ActiveRoll = null
## What a model is in the middle of across several commands (a move with
## rolls in it), or null. See Resolution.
var resolution: Resolution = null
## Every command applied, in order: with the seed, this is the whole game.
var history: Array[Command] = []
## The events of the last command applied.
var last_events: Array[GameEvent] = []

## Undo (not a rule command; it sits beside the command log): the state
## before each command applied since the game started, and the commands
## undone, newest last, for redo.
var _undo_snapshots: Array[GameSnapshot] = []
var _redo_commands: Array[Command] = []

var _next_model_id: int = 1
var _next_terrain_id: int = 1
## The height field for the current terrain, built when first asked for.
## Derived data only: dropped whenever terrain is added.
var _height_field: HeightField = null


func _init(
	seed_value: int = 0,
	p_table_width: float = DEFAULT_TABLE_SIZE_INCHES,
	p_table_depth: float = DEFAULT_TABLE_SIZE_INCHES
) -> void:
	dice = Dice.new(seed_value)
	rules = Ruleset.standard()
	table_width = p_table_width
	table_depth = p_table_depth


## Validates and, if valid, applies a command. Returns "" on success or the
## reason the command was rejected; the events are in last_events.
func execute(command: Command) -> String:
	return submit(command).error


## Validates and, if valid, applies a command, returning the rejection or the
## events of what happened, in order.
func submit(command: Command) -> CommandResult:
	var result: CommandResult = CommandResult.new()
	result.error = command.validate(self)
	if result.error != "":
		last_events = []
		return result
	# Set-up and the start of the game are not undone: undo goes back to turn 1.
	if turn.turn > 0:
		_undo_snapshots.append(GameSnapshot.take(self))
	_redo_commands.clear()
	result.events = command.apply(self)
	history.append(command)
	last_events = result.events
	return result


func can_undo() -> bool:
	return not _undo_snapshots.is_empty()


func can_redo() -> bool:
	return not _redo_commands.is_empty()


## Takes the last command back, restoring the state before it, dice included,
## so doing the same again rolls the same. Returns false if there is nothing
## to undo.
func undo() -> bool:
	if _undo_snapshots.is_empty():
		return false
	var command: Command = history[history.size() - 1]
	var redo_stack: Array[Command] = _redo_commands.duplicate()
	_undo_snapshots.pop_back().restore(self)
	redo_stack.append(command)
	_redo_commands = redo_stack
	last_events = []
	return true


## Applies the last undone command again (it rolls the same dice). Returns its
## result, with an error if there is nothing to redo.
func redo() -> CommandResult:
	if _redo_commands.is_empty():
		var nothing: CommandResult = CommandResult.new()
		nothing.error = "Nothing to redo."
		return nothing
	var redo_stack: Array[Command] = _redo_commands.duplicate()
	var command: Command = redo_stack.pop_back()
	var result: CommandResult = submit(command)
	_redo_commands = redo_stack
	return result


## Models still on the table (not Out of Action).
func models_on_table() -> Array[ModelState]:
	var result: Array[ModelState] = []
	for model: ModelState in models:
		if model.on_table():
			result.append(model)
	return result


## Takes back commands until the command log is `size` long (a whole move
## with rolls in it, say). Returns false if that is not possible.
func undo_to(size: int) -> bool:
	if size < 0 or size > history.size():
		return false
	while history.size() > size:
		if not undo():
			return false
	return true


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


## The terrain as layered floors. Built from `terrain` on first use and kept
## until the terrain changes; never changed by callers.
func height_field() -> HeightField:
	if _height_field == null:
		_height_field = HeightField.new(self)
	return _height_field


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
	_height_field = null
	return piece
