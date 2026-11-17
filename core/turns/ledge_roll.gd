class_name LedgeRoll
extends Interrupt
## The ledge roll (docs/rules/markers.md, "Going Down next to a ledge"; ruling
## 13 of brief 008b): a standing model that suffers a Down result with its
## base within 1" of a ledge first makes a success roll, through the roll
## pipeline like any other (markers may be spent on it). It is made before
## the model is Down, so without the Down penalty, and it is not risky.
## - Success: the model goes Down where it is.
## - Failure: it falls over the nearest ledge (Falling: the closest place it
##   can stop on the floor beneath; the injury roll for a fall of 3" or more,
##   whose own Down result makes no second ledge roll) and is Down where it
##   lands.
## One ledge roll per Down result. See GoingDown and Interrupt.

## Waiting for the ledge roll, or for the injury roll of the fall.
const ROLL: StringName = &"roll"
const FALL_INJURY: StringName = &"fall_injury"
## Context ids on the requests: the ledge roll itself, and the fall's injury
## roll (whose Down result makes no further ledge roll).
const CONTEXT: StringName = &"ledge_roll"
const NO_LEDGE_ROLL: StringName = &"no_ledge_roll"
## How far past the ledge the edge of the base is when the model goes over.
const OVER_SLACK: float = 0.05

## The nearest ledge: a point on it at the floor's height, the direction off
## the floor, the drop there, and how far the base edge is from it.
var ledge_point: Vector3 = Vector3.ZERO
var ledge_normal: Vector2 = Vector2.ZERO
var drop: float = 0.0
var distance: float = 0.0
var waiting: StringName = ROLL


func copy() -> Resolution:
	var result: LedgeRoll = LedgeRoll.new()
	copy_into(result)
	result.ledge_point = ledge_point
	result.ledge_normal = ledge_normal
	result.drop = drop
	result.distance = distance
	result.waiting = waiting
	return result


## Why the roll is made, for the tray.
func reason() -> String:
	return "Model %d goes Down %.1f\" from a %.1f\" drop: a ledge roll to keep its footing, or it falls." % [
		model_id, maxf(distance, 0.0), drop
	]


func begin(state: GameState, events: Array[GameEvent]) -> void:
	var model: ModelState = state.get_model(model_id)
	events.append(GameEvent.new(GameEvent.Kind.LEDGE_ROLL, model.player, model.id, {
		"reason": reason(), "at": ledge_point, "drop": drop, "distance": distance,
	}))
	var request: RollRequest = RollRequest.success(model.player, model.id, &"", false, "Ledge roll")
	request.context = {CONTEXT: true}
	request.on_resolved = _on_roll
	RollPipeline.start(state, request, events)


static func _on_roll(state: GameState, result: RollResult, events: Array[GameEvent]) -> void:
	var roll: LedgeRoll = state.interrupts.back() as LedgeRoll
	var model: ModelState = state.get_model(roll.model_id)
	if result.is_success() or not model.on_table():
		_down_and_finish(state, roll, events)
		return
	var over_2d: Vector2 = (
		Vector2(roll.ledge_point.x, roll.ledge_point.z) + roll.ledge_normal * (model.base_radius_inches() + OVER_SLACK)
	)
	var over: Vector3 = Vector3(over_2d.x, roll.ledge_point.y, over_2d.y)
	var height: float = Falling.fall(state, model, over, events, "failed ledge roll")
	if not Falling.hurts(height):
		_down_and_finish(state, roll, events)
		return
	roll.waiting = FALL_INJURY
	var request: RollRequest = Falling.injury_request(model, height, "falling %.1f\" over a ledge" % height, {NO_LEDGE_ROLL: true})
	request.on_resolved = _on_fall_injury
	RollPipeline.start(state, request, events)


static func _on_fall_injury(state: GameState, _result: RollResult, events: Array[GameEvent]) -> void:
	_down_and_finish(state, state.interrupts.back() as LedgeRoll, events)


## Down where it is now (unless the fall's injury roll already saw to it, or
## took it out of action), then go on.
static func _down_and_finish(state: GameState, roll: LedgeRoll, events: Array[GameEvent]) -> void:
	var model: ModelState = state.get_model(roll.model_id)
	if model.on_table() and not model.down:
		TurnFlow.knock_down(state, model, events)
	Interrupt.finish(state, events)
