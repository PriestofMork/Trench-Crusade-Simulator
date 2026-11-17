class_name GoingDown
extends RefCounted
## A Down result against a model, wherever it comes from (an injury roll, a
## free attack, later others): the one place it is applied
## (docs/rules/markers.md, "Down" and "Going Down next to a ledge"; rulings
## 12 and 13 of brief 008b).
##
## - A model already Down, or out of action, makes no ledge roll; what a Down
##   result does to a Down model (an extra blood marker) is the injury
##   table's business.
## - A standing model with any edge of its base within 1" of a ledge (a drop of
##   more than 1" at the edge of its floor; HeightField.ledge_near()) first
##   makes the ledge roll (LedgeRoll), then goes Down where it ends up.
## - Otherwise it goes Down where it is (TurnFlow.knock_down(): during its own
##   activation, that ends it).

## A ledge is a drop of more than this at the edge of the floor.
const LEDGE_DROP: float = 1.0
## The ledge roll is made when the edge of the base is within this of a ledge.
const LEDGE_DISTANCE: float = 1.0


## Applies a Down result to `model`. `done(state, events)` is called once it
## is applied (at once, or after the ledge roll and its fall); while roll
## reactions run, the roll that caused it is held instead (Interrupt).
## `ledge_roll` false skips the ledge roll (a Down from the injury roll of a
## ledge roll's own fall).
static func result(
	state: GameState, model: ModelState, events: Array[GameEvent], done: Callable = Callable(), ledge_roll: bool = true
) -> void:
	if model.down or not model.on_table():
		if done.is_valid():
			done.call(state, events)
		return
	var ledge: Dictionary = ledge_for(state, model) if ledge_roll else {}
	if ledge.is_empty():
		TurnFlow.knock_down(state, model, events)
		if done.is_valid():
			done.call(state, events)
		return
	var roll: LedgeRoll = LedgeRoll.new()
	roll.model_id = model.id
	roll.done = done
	roll.ledge_point = ledge["point"]
	roll.ledge_normal = ledge["normal"]
	roll.drop = ledge["drop"]
	roll.distance = ledge["distance"]
	Interrupt.push(state, roll, events)


## The nearest ledge within 1" of the edge of `model`'s base, or {} (see
## HeightField.ledge_near()).
static func ledge_for(state: GameState, model: ModelState) -> Dictionary:
	var field: HeightField = state.height_field()
	var p: Vector2 = Vector2(model.position.x, model.position.z)
	var surfaces: PackedInt32Array = field.surfaces_matching(p, model.position.y)
	var best: Dictionary = {}
	for surface: int in surfaces:
		var found: Dictionary = field.ledge_near(p, surface, model.base_radius_inches(), LEDGE_DISTANCE, LEDGE_DROP)
		if not found.is_empty() and (best.is_empty() or found["distance"] < best["distance"]):
			best = found
	return best
