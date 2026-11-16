class_name ChargeExecution
extends RefCounted
## Carries out a declared charge (ChargePlan) in stages, on the same
## machinery as staged moves (brief 006):
##
## 1. Declared (ruling 1): CHARGE_DECLARED, and a ChargeResolution on
##    GameState.resolution. The plain D6 is started through the roll pipeline
##    (shown in the tray; nothing is spent on it).
## 2. Its on_resolved callback (_on_roll) reads the charge back from the state
##    and works out the distance: Movement + D6, halved as a whole after
##    standing up (ruling 2).
##    - Enough: the charger moves along the charge path to first contact.
##      If distance is left, the places around the target's base it could
##      slide to (ruling 8) are offered as a CHARGE_CONTACT decision, first
##      contact by default; ChooseContactCommand answers it.
##    - Not enough (ruling 7): it moves along the path as far as the distance
##      allows and stops at the last position on it where it may stop outside
##      every enemy's 1" zone.
## 3. In contact: every enemy within 1" of where it ends counts as charged
##    and is recorded on the activation (TurnState.charged); CHARGED.
##
## Everything is on the GameState and runs inside commands, so undo, redo and
## replay work as for any command. The roll resolver knows nothing of this.

## Spacing of the positions offered around the target's base.
const ARC_STEP: float = 0.1
## Spacing of the points tried along the path when a charge falls short.
const STOP_STEP: float = 0.05
const EPSILON: float = 0.0001


## Declares the charge `plan` describes and rolls its D6.
static func start(state: GameState, model: ModelState, action: ActionDef, plan: ChargePlan, events: Array[GameEvent]) -> void:
	var legality: MoveLegality = ChargePlanner.legality_for(state, model)
	var path_cost: float = 0.0
	for segment: MoveSegment in legality.segments_for(model.position, plan.path):
		path_cost += segment.cost
	var charge: ChargeResolution = ChargeResolution.new()
	charge.model_id = model.id
	charge.player = model.player
	charge.action_id = action.id
	charge.declared_id = plan.declared_id
	charge.target_id = plan.target_id
	charge.path = plan.path
	charge.path_cost = path_cost
	charge.length = plan.length
	charge.waiting = ChargeResolution.ROLL
	state.resolution = charge
	events.append(GameEvent.new(GameEvent.Kind.CHARGE_DECLARED, model.player, model.id, {
		"declared_id": plan.declared_id, "target_id": plan.target_id, "interposed": plan.interposed(),
		"interposers": plan.interposers.duplicate(), "path": plan.path.duplicate(), "length": plan.length,
		"needed": plan.needed,
	}))
	var request: RollRequest = RollRequest.d6(model.player, model.id, plan.target_id, action.id, "Charge")
	request.on_resolved = _on_roll
	RollPipeline.start(state, request, events)


static func _on_roll(state: GameState, result: RollResult, events: Array[GameEvent]) -> void:
	var charge: ChargeResolution = state.resolution as ChargeResolution
	if charge == null:
		return
	var model: ModelState = state.get_model(charge.model_id)
	charge.distance = TurnFlow.movement_budget(state, model, model.movement + result.total)
	var reaches: bool = charge.distance + EPSILON >= charge.length
	events.append(GameEvent.new(GameEvent.Kind.CHARGE_DISTANCE, charge.player, charge.model_id, {
		"roll": result.total, "distance": charge.distance, "length": charge.length, "reaches": reaches,
	}))
	if reaches:
		_reach_contact(state, charge, events)
	else:
		_fall_short(state, charge, events)


## To first contact, then the contact choice if there is distance to slide.
static func _reach_contact(state: GameState, charge: ChargeResolution, events: Array[GameEvent]) -> void:
	var model: ModelState = state.get_model(charge.model_id)
	var legality: MoveLegality = ChargePlanner.legality_for(state, model)
	var segments: Array[MoveSegment] = legality.segments_for(model.position, charge.path)
	var shown: Array[Vector3] = [model.position]
	var kinds: Array[Transitions.Kind] = []
	for segment: MoveSegment in segments:
		shown.append(segment.to)
		kinds.append(segment.kind)
	model.position = _on_floor(legality, charge.path[charge.path.size() - 1])
	shown[shown.size() - 1] = model.position
	events.append(GameEvent.new(GameEvent.Kind.MODEL_MOVED, charge.player, charge.model_id, {
		"path": shown, "kinds": kinds, "cost": charge.length, "left": maxf(charge.distance - charge.length, 0.0),
	}))
	var options: Dictionary = contact_options(state, model, state.get_model(charge.target_id), charge.distance - charge.path_cost)
	var positions: Array[Vector3] = options["positions"]
	if positions.size() <= 1:
		_finish(state, charge, events)
		return
	charge.waiting = ChargeResolution.CONTACT
	var decision: PendingDecision = PendingDecision.new(
		PendingDecision.Kind.CHARGE_CONTACT, charge.player,
		"Choose where the charger ends around model %d's base." % charge.target_id
	)
	decision.model_id = charge.model_id
	decision.action_id = charge.action_id
	decision.positions = positions
	decision.charged_ids = options["charged"]
	decision.default_index = options["default_index"]
	TurnFlow.ask(state, decision, events)


## Answers CHARGE_CONTACT: slides around the target's base to option `index`.
static func choose_contact(state: GameState, index: int, events: Array[GameEvent]) -> void:
	var charge: ChargeResolution = state.resolution as ChargeResolution
	var decision: PendingDecision = state.pending
	state.pending = null
	var model: ModelState = state.get_model(charge.model_id)
	var target: ModelState = state.get_model(charge.target_id)
	var to: Vector3 = decision.positions[index]
	if index != decision.default_index:
		var shown: Array[Vector3] = arc_points(model.position, to, target)
		var legality: MoveLegality = MoveLegality.new(state, model)
		var cost: float = 0.0
		for i: int in range(1, shown.size()):
			cost += Vector2(shown[i - 1].x, shown[i - 1].z).distance_to(Vector2(shown[i].x, shown[i].z))
		var kinds: Array[Transitions.Kind] = []
		for i: int in shown.size() - 1:
			kinds.append(Transitions.Kind.WALK)
		model.position = _on_floor(legality, to)
		shown[shown.size() - 1] = model.position
		events.append(GameEvent.new(GameEvent.Kind.MODEL_MOVED, charge.player, charge.model_id, {
			"path": shown, "kinds": kinds, "cost": cost, "left": 0.0, "slide": true,
		}))
	_finish(state, charge, events)


## The charger is in contact where it is: record who it charged.
static func _finish(state: GameState, charge: ChargeResolution, events: Array[GameEvent]) -> void:
	state.resolution = null
	var model: ModelState = state.get_model(charge.model_id)
	var charged: Array[int] = MeleeZone.enemy_ids_within(state, model)
	for id: int in charged:
		if not state.turn.charged.has(id):
			state.turn.charged.append(id)
	events.append(GameEvent.new(GameEvent.Kind.CHARGED, charge.player, charge.model_id, {
		"target_id": charge.target_id, "charged": charged, "at": model.position,
	}))
	if charge.end_reason != "" and state.turn.active_model_id == charge.model_id:
		TurnFlow.end_activation(state, events, charge.end_reason)


## Ruling 7: as far along the path as the distance allows, back to the last
## place there it may stop outside every enemy's 1" zone.
static func _fall_short(state: GameState, charge: ChargeResolution, events: Array[GameEvent]) -> void:
	var model: ModelState = state.get_model(charge.model_id)
	var stop: Array = stop_short(state, model, charge.path, charge.distance)
	var shown: Array[Vector3] = stop[0]
	var kinds: Array[Transitions.Kind] = stop[1]
	var cost: float = stop[2]
	state.resolution = null
	if shown.size() >= 2:
		model.position = shown[shown.size() - 1]
		events.append(GameEvent.new(GameEvent.Kind.MODEL_MOVED, charge.player, charge.model_id, {
			"path": shown, "kinds": kinds, "cost": cost, "left": 0.0,
		}))
	events.append(GameEvent.new(GameEvent.Kind.CHARGE_FAILED, charge.player, charge.model_id, {
		"target_id": charge.target_id, "at": model.position, "distance": charge.distance, "length": charge.length,
	}))
	if charge.end_reason != "" and state.turn.active_model_id == charge.model_id:
		TurnFlow.end_activation(state, events, charge.end_reason)


## Where a charge along `path` that only gets `distance` far stops (ruling 7):
## [the path moved (start first), its segment kinds, its cost]. Positions are
## tried along walks every STOP_STEP and at the ends of other segments
## (climbs are never split), from the furthest the distance allows back to
## the start; the first where the model may stop under the normal rules
## (outside every 1" zone), with any low obstacle surcharge within the
## distance, is taken.
static func stop_short(state: GameState, model: ModelState, path: Array[Vector3], distance: float) -> Array:
	var charge_legality: MoveLegality = ChargePlanner.legality_for(state, model)
	var normal: MoveLegality = MoveLegality.new(state, model)
	var segments: Array[MoveSegment] = charge_legality.segments_for(model.position, path)
	# Candidates: [point, cost there, index of the segment it is on (or -1 at the start)].
	var candidates: Array = [[model.position, 0.0, -1]]
	var spent: float = 0.0
	for i: int in segments.size():
		var segment: MoveSegment = segments[i]
		if segment.kind == Transitions.Kind.WALK:
			var count: int = maxi(ceili(segment.from.distance_to(segment.to) / STOP_STEP), 1)
			for j: int in range(1, count + 1):
				var t: float = float(j) / count
				candidates.append([segment.from.lerp(segment.to, t), spent + segment.cost * t, i])
		else:
			candidates.append([segment.to, spent + segment.cost, i])
		spent += segment.cost
	var chosen: int = 0
	for k: int in range(candidates.size() - 1, 0, -1):
		var point: Vector3 = candidates[k][0]
		var cost: float = candidates[k][1]
		if cost > distance + EPSILON:
			continue
		var surcharge: float = normal.stop_surcharge(point)
		if surcharge == INF or cost + surcharge > distance + EPSILON:
			continue
		chosen = k
		break
	var shown: Array[Vector3] = [model.position]
	var kinds: Array[Transitions.Kind] = []
	if chosen == 0:
		return [shown, kinds, 0.0]
	var on: int = candidates[chosen][2]
	for i: int in on:
		shown.append(segments[i].to)
		kinds.append(segments[i].kind)
	shown.append(_on_floor(normal, candidates[chosen][0]))
	kinds.append(segments[on].kind)
	var end_cost: float = candidates[chosen][1] + normal.stop_surcharge(candidates[chosen][0])
	return [shown, kinds, end_cost]


## The places the charger, in first contact with `target` where it stands,
## may end its charge with `left` inches to slide around the target's base
## (ruling 8): {"positions": Array[Vector3], "charged": Array of Array[int]
## per position, "default_index": first contact}. Positions run from one end
## of the reachable arc to the other, ARC_STEP apart along it.
##
## Sliding keeps the base touching the target's: the centre runs on the
## circle of contact, checked in short straight steps as walks (terrain,
## other bases, the table edge; enemy zones are open, the target is left out
## since the circle keeps clear of it). Each step stays on floors of one
## level within the low obstacle height of the target's; a step that is not a
## walk (onto or off a low obstacle) ends the slide that way. A position is
## offered where the model may stop, with any low obstacle surcharge within
## what is left.
static func contact_options(state: GameState, model: ModelState, target: ModelState, left: float) -> Dictionary:
	var zones: EnemyZones = EnemyZones.charge()
	zones.ignored_ids = [target.id]
	var legality: MoveLegality = MoveLegality.new(state, model, null, zones)
	legality.allow_rolls = false
	var first: Vector3 = model.position
	var centre: Vector2 = Vector2(target.position.x, target.position.z)
	var radius: float = model.base_radius_inches() + target.base_radius_inches()
	var start_angle: float = (Vector2(first.x, first.z) - centre).angle()
	var step_angle: float = ARC_STEP / radius
	var sides: Array = []
	for direction: int in [-1, 1]:
		var found: Array[Vector3] = []
		var spent: float = 0.0
		var previous: Vector3 = first
		var k: int = 1
		while k * step_angle <= PI - step_angle * 0.5:
			var angle: float = start_angle + direction * k * step_angle
			k += 1
			var p: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
			var best: Vector3 = Vector3.INF
			var best_cost: float = INF
			for s: int in legality.field.surfaces_at(p):
				var q: Vector3 = Vector3(p.x, legality.field.surface_height(s, p), p.y)
				if not ChargePlanner.heights_allow_contact(q, target):
					continue
				var cost: float = legality.walk_cost(previous, q)
				if cost < best_cost:
					best_cost = cost
					best = q
			if best_cost == INF or spent + best_cost > left + EPSILON:
				break
			spent += best_cost
			previous = best
			var surcharge: float = legality.stop_surcharge(best)
			if surcharge != INF and spent + surcharge <= left + EPSILON:
				found.append(best)
		sides.append(found)
	var positions: Array[Vector3] = []
	var low_side: Array[Vector3] = sides[0]
	for i: int in range(low_side.size() - 1, -1, -1):
		positions.append(low_side[i])
	var default_index: int = positions.size()
	positions.append(first)
	positions.append_array(sides[1])
	var charged: Array = []
	for position: Vector3 in positions:
		charged.append(MeleeZone.enemy_ids_within(state, model, position))
	return {"positions": positions, "charged": charged, "default_index": default_index}


## Points on the circle of contact around `target` from `from` to `to`, the
## short way round, ARC_STEP apart (both ends included).
static func arc_points(from: Vector3, to: Vector3, target: ModelState) -> Array[Vector3]:
	var centre: Vector2 = Vector2(target.position.x, target.position.z)
	var a: Vector2 = Vector2(from.x, from.z) - centre
	var b: Vector2 = Vector2(to.x, to.z) - centre
	var radius: float = a.length()
	var sweep: float = a.angle_to(b)
	var count: int = maxi(ceili(absf(sweep) * radius / ARC_STEP), 1)
	var result: Array[Vector3] = []
	for j: int in count + 1:
		var t: float = float(j) / count
		var angle: float = a.angle() + sweep * t
		var p: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
		result.append(Vector3(p.x, lerpf(from.y, to.y, t), p.y))
	result[result.size() - 1] = to
	return result


## `point` exactly on its floor, so small errors never build up.
static func _on_floor(legality: MoveLegality, point: Vector3) -> Vector3:
	var surfaces: PackedInt32Array = legality.surfaces_at(point)
	if surfaces.is_empty():
		return point
	return legality.on_surface(Vector2(point.x, point.z), surfaces[0])
