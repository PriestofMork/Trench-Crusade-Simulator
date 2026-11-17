class_name Falling
extends RefCounted
## Falling (docs/rules/movement.md, "Falling"): the one place a model is made
## to fall, whatever made it fall (a failed jump, a failed ledge roll). The
## model is moved to the closest place it can stop on the first floor
## beneath the point it fell from; a fall of the free drop height (3") or
## more is an injury roll against it at +1 die per full 3" (the dice come from
## the "fall" context modifier in core_rules.json, not from here).


## Makes `model` fall from `over` (a point in the air at the height it fell
## from): moves it to where it lands and reports it (MODEL_FELL). Returns
## how far it fell.
static func fall(state: GameState, model: ModelState, over: Vector3, events: Array[GameEvent], why: String = "") -> float:
	var legality: MoveLegality = MoveLegality.new(state, model)
	var over_2d: Vector2 = Vector2(over.x, over.z)
	var below: int = legality.surface_below(over_2d, over.y)
	var landing: Vector3 = model.position
	if below != -1:
		var spot: Variant = legality.closest_stop(over_2d, below)
		landing = spot if spot != null else legality.on_surface(over_2d, below)
	var height: float = maxf(over.y - landing.y, 0.0)
	var data: Dictionary = {"from": model.position, "over": over, "to": landing, "height": height}
	if why != "":
		data["reason"] = why
	events.append(GameEvent.new(GameEvent.Kind.MODEL_FELL, model.player, model.id, data))
	model.position = landing
	return height


## Whether a fall of `height` inches calls for an injury roll.
static func hurts(height: float) -> bool:
	return Transitions.is_fall(height)


## The injury roll for `model` falling (or dropping) `height` inches; `what`
## says why, for the breakdown ("falling 4.0\""). Rolled by the opponent.
## `context` adds situation facts for providers and reactions.
static func injury_request(model: ModelState, height: float, what: String, context: Dictionary = {}) -> RollRequest:
	var request: RollRequest = RollRequest.injury(1 - model.player, -1, model.id)
	request.label = "Injury roll (%s)" % what
	var facts: Dictionary = {&"fall_inches": height}
	facts.merge(context)
	request.context = facts
	return request
