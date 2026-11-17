class_name ChargeExecution
extends RefCounted
## Carries out a declared charge (ChargePlan). The charge itself never moves
## the model: it works out which segments to move along and hands them to the
## one movement process, MoveExecution, which walks them and makes the rolls
## on the way, exactly as for a Move (brief 008b, "one movement process").
##
## 1. Declared (ruling 3 of 008b): CHARGE_DECLARED with the target and route
##    choice, and a ChargeResolution on GameState.resolution. The plain D6 is
##    started through the roll pipeline.
## 2. Its on_resolved callback (_on_roll) works out the distance: Movement +
##    D6, halved as a whole after standing up.
##    - Enough: the whole route.
##    - Not enough (ruling 4): the route as far as the distance allows, back to
##      the last position on it where the model may stop outside every enemy's
##      1" zone; a climb or jump it cannot complete is not started
##      (stop_short()).
##    Those segments go to MoveExecution as a StagedMove with this charge as
##    its parent and _on_route_end as its hook.
## 3. Sheer climbs, gap jumps and drops on the route are rolled as the model
##    gets there (ruling 1), with the usual marker prompts and results. A
##    failed roll (or going Down on the way) stops the move as in a Move, the
##    activation ends, and the charge has failed (CHARGE_FAILED).
## 4. At the end of a full route in base contact: if distance is left, the
##    places around the target's base it could slide to (ruling 8: in contact
##    the whole way, levels may change, no rolls) are offered as a
##    CHARGE_CONTACT decision, first contact by default; ChooseContactCommand
##    answers it and the slide is again a StagedMove for MoveExecution.
##    At the end of a route with no contact (ruling 6), the charge succeeds if
##    the charger is within 1" of the target.
## 5. In melee: every enemy within 1" of where it ends counts as charged and
##    is recorded on the activation (TurnState.charged); CHARGED.
##
## Everything is on the GameState and runs inside commands, so undo, redo and
## replay work as for any command. The roll resolver knows nothing of this.

## Spacing of the positions offered around the target's base.
const ARC_STEP: float = 0.1
## Spacing of the points tried along the route when a charge falls short.
const STOP_STEP: float = 0.05
const EPSILON: float = 0.0001


## Declares the charge `plan` describes and rolls its D6.
static func start(state: GameState, model: ModelState, action: ActionDef, plan: ChargePlan, events: Array[GameEvent]) -> void:
	var charge: ChargeResolution = ChargeResolution.new()
	charge.model_id = model.id
	charge.player = model.player
	charge.action_id = action.id
	charge.declared_id = plan.declared_id
	charge.target_id = plan.target_id
	charge.allow_rolls = plan.allow_rolls
	charge.descent_mode = plan.descent_mode
	charge.path = plan.path
	charge.length = plan.length
	charge.contact = plan.contact
	charge.waiting = ChargeResolution.ROLL
	state.resolution = charge
	events.append(GameEvent.new(GameEvent.Kind.CHARGE_DECLARED, model.player, model.id, {
		"declared_id": plan.declared_id, "target_id": plan.target_id, "interposed": plan.interposed(),
		"interposers": plan.interposers.duplicate(), "path": plan.path.duplicate(), "length": plan.length,
		"needed": plan.needed, "allow_rolls": plan.allow_rolls, "rolls": plan.rolls.duplicate(), "contact": plan.contact,
		"label": plan.label(),
	}))
	var request: RollRequest = RollRequest.d6(model.player, model.id, plan.target_id, action.id, "Charge")
	request.on_resolved = _on_roll
	RollPipeline.start(state, request, events)


## The segments of `charge`'s route from where the charger stands.
static func route_segments(state: GameState, charge: ChargeResolution) -> Array[MoveSegment]:
	if charge.path.is_empty():
		return []
	var model: ModelState = state.get_model(charge.model_id)
	var legality: MoveLegality = ChargePlanner.legality_for(state, model, charge.allow_rolls, charge.descent_mode)
	return legality.segments_for(model.position, charge.path)


static func _on_roll(state: GameState, result: RollResult, events: Array[GameEvent]) -> void:
	var charge: ChargeResolution = state.resolution as ChargeResolution
	if charge == null:
		return
	var model: ModelState = state.get_model(charge.model_id)
	charge.distance = TurnFlow.movement_budget(state, model, model.movement + result.total)
	var segments: Array[MoveSegment] = route_segments(state, charge)
	charge.reaches = not segments.is_empty() and charge.distance + EPSILON >= charge.length
	events.append(GameEvent.new(GameEvent.Kind.CHARGE_DISTANCE, charge.player, charge.model_id, {
		"roll": result.total, "distance": charge.distance, "length": charge.length, "reaches": charge.reaches,
	}))
	var staged: StagedMove = _staged_for(charge, charge.distance)
	if charge.reaches:
		staged.segments = segments
		var cost: float = 0.0
		for segment: MoveSegment in segments:
			cost += segment.cost
		staged.surcharge = maxf(charge.length - cost, 0.0)
	else:
		var short: Dictionary = stop_short(state, model, segments, charge.distance)
		staged.segments = short["segments"]
		staged.surcharge = short["surcharge"]
	charge.waiting = ChargeResolution.MOVING
	staged.on_end = _on_route_end
	staged.event_data = {"charge": true}
	MoveExecution.run(state, staged, events)


## A move for the charger within `budget`, part of `charge`.
static func _staged_for(charge: ChargeResolution, budget: float) -> StagedMove:
	var staged: StagedMove = StagedMove.new()
	staged.model_id = charge.model_id
	staged.player = charge.player
	staged.action_id = charge.action_id
	staged.budget = budget
	staged.zones = ChargePlanner.zones()
	staged.parent = charge
	return staged


## StagedMove.on_end of the route.
static func _on_route_end(state: GameState, staged: StagedMove, stopped: bool, events: Array[GameEvent]) -> void:
	var charge: ChargeResolution = staged.parent as ChargeResolution
	charge.end_reason = staged.end_reason
	var model: ModelState = state.get_model(charge.model_id)
	if stopped:
		# A roll on the way failed (or the charger went Down): MoveExecution
		# ends the activation after this.
		_failed(state, charge, events, "a roll on the way failed" if model.on_table() and not model.down else "the charger did not stay standing", false)
		return
	if not charge.reaches:
		_failed(state, charge, events, "not far enough")
		return
	if not charge.contact:
		# Ruling 6: no contact position; in melee if within 1" of the target.
		if MeleeZone.is_within(MeleeZone.gap(model, state.get_model(charge.target_id))):
			_finish(state, charge, events)
		else:
			_failed(state, charge, events, "no base contact and not within 1\"")
		return
	var options: Dictionary = contact_options(state, model, state.get_model(charge.target_id), staged.left(), charge.descent_mode)
	var positions: Array[Vector3] = options["positions"]
	if positions.size() <= 1:
		_finish(state, charge, events)
		return
	charge.distance = staged.left()
	charge.waiting = ChargeResolution.CONTACT
	state.resolution = charge
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
	if index == decision.default_index:
		_finish(state, charge, events)
		return
	var model: ModelState = state.get_model(charge.model_id)
	var options: Dictionary = contact_options(state, model, state.get_model(charge.target_id), charge.distance, charge.descent_mode)
	var slides: Array = options["slides"]
	var slide: Dictionary = slides[index]
	var staged: StagedMove = _staged_for(charge, charge.distance)
	staged.segments = slide["segments"]
	staged.surcharge = slide["surcharge"]
	staged.on_end = _on_slide_end
	staged.event_data = {"charge": true, "slide": true}
	charge.waiting = ChargeResolution.SLIDING
	MoveExecution.run(state, staged, events)


## StagedMove.on_end of the slide (no rolls, so it is never stopped).
static func _on_slide_end(state: GameState, staged: StagedMove, _stopped: bool, events: Array[GameEvent]) -> void:
	var charge: ChargeResolution = staged.parent as ChargeResolution
	if staged.end_reason != "":
		charge.end_reason = staged.end_reason
	_finish(state, charge, events)


## The charger is in melee where it is: record who it charged.
static func _finish(state: GameState, charge: ChargeResolution, events: Array[GameEvent]) -> void:
	state.resolution = null
	var model: ModelState = state.get_model(charge.model_id)
	var charged: Array[int] = MeleeZone.enemy_ids_within(state, model)
	for id: int in charged:
		if not state.turn.charged.has(id):
			state.turn.charged.append(id)
	events.append(GameEvent.new(GameEvent.Kind.CHARGED, charge.player, charge.model_id, {
		"target_id": charge.target_id, "charged": charged, "at": model.position, "contact": charge.contact,
	}))
	if charge.end_reason != "" and state.turn.active_model_id == charge.model_id:
		TurnFlow.end_activation(state, events, charge.end_reason)


## The charge has failed. `end` ends the activation if something asked for
## that (MoveExecution does it itself after a stopped move).
static func _failed(state: GameState, charge: ChargeResolution, events: Array[GameEvent], why: String, end: bool = true) -> void:
	state.resolution = null
	var model: ModelState = state.get_model(charge.model_id)
	events.append(GameEvent.new(GameEvent.Kind.CHARGE_FAILED, charge.player, charge.model_id, {
		"target_id": charge.target_id, "at": model.position, "distance": charge.distance, "length": charge.length,
		"reason": why,
	}))
	if end and charge.end_reason != "" and state.turn.active_model_id == charge.model_id:
		TurnFlow.end_activation(state, events, charge.end_reason)


## Ruling 4: how far along `segments` (a route from the model's position) a
## charge of `distance` gets: {"segments": the segments to move along, the
## last one cut short where needed, "surcharge": paid for stopping there}.
## Positions are tried along walks every STOP_STEP and at the ends of other
## segments (a climb or jump is never split, so one that cannot be completed
## is not started), from the furthest the distance allows back to the start;
## the first where the model may stop under the normal rules (outside every
## 1" zone), with any low obstacle surcharge within the distance, is taken.
## Where nothing is, the model stays put.
static func stop_short(state: GameState, model: ModelState, segments: Array[MoveSegment], distance: float) -> Dictionary:
	var normal: MoveLegality = MoveLegality.new(state, model)
	# Candidates: [point, cost there, index of the segment it is on, fraction of it].
	var candidates: Array = []
	var spent: float = 0.0
	for i: int in segments.size():
		var segment: MoveSegment = segments[i]
		if segment.kind == Transitions.Kind.WALK:
			var count: int = maxi(ceili(segment.from.distance_to(segment.to) / STOP_STEP), 1)
			for j: int in range(1, count + 1):
				var t: float = float(j) / count
				candidates.append([segment.from.lerp(segment.to, t), spent + segment.cost * t, i, t])
		else:
			candidates.append([segment.to, spent + segment.cost, i, 1.0])
		spent += segment.cost
	var result: Array[MoveSegment] = []
	for k: int in range(candidates.size() - 1, -1, -1):
		var point: Vector3 = candidates[k][0]
		var cost: float = candidates[k][1]
		if cost > distance + EPSILON:
			continue
		var surcharge: float = normal.stop_surcharge(point)
		if surcharge == INF or cost + surcharge > distance + EPSILON:
			continue
		var on: int = candidates[k][2]
		var t: float = candidates[k][3]
		for i: int in on:
			result.append(segments[i])
		if t >= 1.0 - EPSILON:
			result.append(segments[on])
		else:
			var part: MoveSegment = MoveSegment.new()
			part.from = segments[on].from
			part.to = point
			part.kind = Transitions.Kind.WALK
			part.cost = segments[on].cost * t
			result.append(part)
		return {"segments": result, "surcharge": surcharge}
	return {"segments": result, "surcharge": 0.0}


## The places the charger, in first contact with `target` where it stands,
## may end its charge with `left` inches to slide around the target's base
## (ruling 8 of brief 008b): {"positions": Array[Vector3], "charged": Array of
## Array[int] per position, "slides": per position {"segments", "surcharge"}
## (the way there; empty at first contact), "default_index": first contact}.
## Positions run from one end of the reachable arc to the other, ARC_STEP
## apart along it.
##
## Sliding keeps the bases in contact (ruling 7) the whole way: the centre runs
## on the circle of contact, in short steps, each a walk on one level or a
## roll-free change of level where the circle crosses a wall
## (MoveLegality.level_change_cost(), over no more arc than the base takes to
## cross the wall). Every position stepped to has the
## cylinders overlapping in height; enemy zones are open and the target is
## left out of the checks, since the circle keeps clear of it. A position is
## offered where the model may stop, with any low obstacle surcharge within
## what is left.
static func contact_options(
	state: GameState, model: ModelState, target: ModelState, left: float,
	descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
) -> Dictionary:
	var zones: EnemyZones = EnemyZones.charge()
	zones.ignored_ids = [target.id]
	var legality: MoveLegality = MoveLegality.new(state, model, null, zones)
	legality.allow_rolls = false
	legality.descent_mode = descent_mode
	var first: Vector3 = model.position
	var centre: Vector2 = Vector2(target.position.x, target.position.z)
	var radius: float = model.base_radius_inches() + target.base_radius_inches()
	var start_angle: float = (Vector2(first.x, first.z) - centre).angle()
	var step_angle: float = ARC_STEP / radius
	# Where the circle meets a wall at a slant, the base is on the wall for
	# longer than a base radius of arc; two radii covers any slant but the
	# shallowest.
	var crossing: float = 2.0 * model.base_radius_inches() + ARC_STEP
	var sides: Array = []
	for direction: int in [-1, 1]:
		var found: Array = []
		var steps: Array[MoveSegment] = []
		var spent: float = 0.0
		var previous: Vector3 = first
		var previous_angle: float = start_angle
		var k: int = 1
		while k * step_angle <= PI - step_angle * 0.5:
			var angle: float = start_angle + direction * k * step_angle
			k += 1
			var p: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
			var best: Vector3 = Vector3.INF
			var best_cost: float = INF
			var best_kind: Transitions.Kind = Transitions.Kind.NONE
			var best_drop: float = 0.0
			var best_rise: float = 0.0
			for s: int in legality.field.surfaces_at(p):
				var q: Vector3 = Vector3(p.x, legality.field.surface_height(s, p), p.y)
				if not MeleeZone.in_base_contact(q, model.base_radius_inches(), model.height_inches(), target):
					continue
				var cost: float = legality.walk_cost(previous, q)
				var kind: Transitions.Kind = Transitions.Kind.WALK
				if cost == INF:
					cost = legality.level_change_cost(previous, q, crossing)
					kind = legality.last_kind
				if cost < best_cost:
					best_cost = cost
					best = q
					best_kind = kind
					best_drop = legality.last_drop if kind != Transitions.Kind.WALK else 0.0
					best_rise = legality.last_rise if kind != Transitions.Kind.WALK else 0.0
			if best_cost == INF:
				# Nowhere to be in contact here: on a wall, or the end of the slide.
				if absf(angle - previous_angle) * radius > crossing:
					break
				continue
			if spent + best_cost > left + EPSILON:
				break
			var segment: MoveSegment = MoveSegment.new()
			segment.from = previous
			segment.to = best
			segment.kind = best_kind
			segment.cost = best_cost
			segment.drop = best_drop
			segment.rise = best_rise
			steps.append(segment)
			spent += best_cost
			previous = best
			previous_angle = angle
			var surcharge: float = legality.stop_surcharge(best)
			if surcharge != INF and spent + surcharge <= left + EPSILON:
				found.append({"at": best, "segments": steps.duplicate(), "surcharge": surcharge})
		sides.append(found)
	var positions: Array[Vector3] = []
	var slides: Array = []
	var low_side: Array = sides[0]
	for i: int in range(low_side.size() - 1, -1, -1):
		positions.append(low_side[i]["at"])
		slides.append(low_side[i])
	var default_index: int = positions.size()
	positions.append(first)
	slides.append({"at": first, "segments": [] as Array[MoveSegment], "surcharge": 0.0})
	for entry: Dictionary in sides[1]:
		positions.append(entry["at"])
		slides.append(entry)
	var charged: Array = []
	for position: Vector3 in positions:
		charged.append(MeleeZone.enemy_ids_within(state, model, position))
	return {"positions": positions, "charged": charged, "slides": slides, "default_index": default_index}
