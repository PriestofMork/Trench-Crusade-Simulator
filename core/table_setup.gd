class_name TableSetup
extends RefCounted
## Reads a table set-up (terrain and models) from a JSON data file and turns it
## into the commands that build it. Used by the game and by tests, so both see
## the same table.
##
## Format: {"terrain": [...], "models": [...]}.
## Terrain: "center" [x, z], "size" [own x, height, own z], optional "base"
## (underside height), "turn" (degrees), "tag" (none, sheer, ladder,
## impassable), "shape" (box, ramp).
## Models: "player", "at" [x, y, z] (y is the floor height), "base" (mm),
## "movement" (inches).

const TAGS: Dictionary[String, TerrainPiece.Tag] = {
	"none": TerrainPiece.Tag.NONE,
	"sheer": TerrainPiece.Tag.SHEER,
	"ladder": TerrainPiece.Tag.LADDER,
	"impassable": TerrainPiece.Tag.IMPASSABLE,
}
const SHAPES: Dictionary[String, TerrainPiece.Shape] = {
	"box": TerrainPiece.Shape.BOX,
	"ramp": TerrainPiece.Shape.RAMP,
}


## The parsed file, or an empty dictionary (with an error pushed) if it cannot be read.
static func load_file(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("TableSetup: cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("TableSetup: %s is not a JSON object" % path)
		return {}
	return parsed


## Commands that place the terrain, then (unless include_models is false) the
## models, in file order.
static func commands(data: Dictionary, include_models: bool = true) -> Array[Command]:
	var result: Array[Command] = []
	for entry: Dictionary in data.get("terrain", []):
		var center: Array = entry["center"]
		var size: Array = entry["size"]
		result.append(PlaceTerrainCommand.new(
			Vector2(center[0], center[1]),
			Vector3(size[0], size[1], size[2]),
			deg_to_rad(float(entry.get("turn", 0.0))),
			float(entry.get("base", 0.0)),
			TAGS[String(entry.get("tag", "none"))],
			SHAPES[String(entry.get("shape", "box"))]
		))
	if not include_models:
		return result
	for entry: Dictionary in data.get("models", []):
		var at: Array = entry["at"]
		result.append(PlaceModelCommand.new(
			int(entry["player"]), Vector3(at[0], at[1], at[2]), int(entry["base"]), float(entry["movement"])
		))
	return result


## Builds the table from a file into `state`. Returns the errors of any
## commands that were rejected (empty if all went well).
static func apply_file(state: GameState, path: String, include_models: bool = true) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	for command: Command in commands(load_file(path), include_models):
		var error: String = state.execute(command)
		if error != "":
			errors.append(error)
	return errors
