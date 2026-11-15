class_name MoveExecution
extends RefCounted
## Carries out a checked path (MovePath) for MoveCommand, in stages where it
## makes rolls (brief 006):
##
## 1. The model moves along the path up to the next roll point and stops
##    there (MODEL_MOVED for that leg).
## 2. The roll is started through the roll pipeline: a risky success roll at
##    the wall or ledge before a sheer climb or gap jump, an injury roll after
##    landing from a drop or a jump down of 3" or more. Its pre-roll choices
##    (marker spending) are ordinary pending decisions, answered by
##    RollChoiceCommand.
## 3. When the roll is resolved, its on_resolved callback (_on_roll) reads the
##    move back from GameState.resolution (a StagedMove) and goes on:
##    - success / still standing: on along the path to the next roll point,
##      or to the end, where the move stays open with what is left;
##    - failed climb: the model stays at the foot (or top), moved to the
##      closest place it can stop if it cannot stop there, and the activation
##      ends;
##    - failed jump: the model falls into the gap from its middle, lands on
##      the first floor beneath at the closest place it can stop, takes the
##      injury roll if it fell 3" or more, and the activation ends;
##    - Down or Out of Action from an injury roll: the move stops and the
##      activation ends.
## Movement spent stays spent. The roll reactions that end an activation (a
## failed risky roll, going Down) only record it on the StagedMove while it
## is under way (TurnFlow.end_activation_when_done()); the move ends the
## activation itself once it has finished what it must.
##
## Everything here runs inside a command's apply(), and all its state is on
## the GameState, so undo (step by step, or as a whole with undo_to()), redo
## and replay from the seed and command list behave as for any command.
##
## The roll resolver knows nothing of this: the rolls are ordinary requests.


## Carries out `path` for the open move `decision` answered.
static func start(state: GameState, path: MovePath, decision: PendingDecision, events: Array[GameEvent]) -> void:
	var staged: StagedMove = StagedMove.new()
	staged.model_id = path.model_id
	staged.player = decision.player
	staged.action_id = decision.action_id
	staged.budget = decision.budget
	staged.segments = path.segments
	staged.surcharge = path.surcharge
	state.pending = null
	state.resolution = staged
	_advance(state, events)


## Moves on from where the staged move is to its next roll point or its end.
static func _advance(state: GameState, events: Array[GameEvent]) -> void:
	var staged: StagedMove = state.resolution as StagedMove
	var model: ModelState = state.get_model(staged.model_id)
	var leg: Array[Vector3] = [model.position]
	var kinds: Array[Transitions.Kind] = []
	var leg_cost: float = 0.0
	while staged.next < staged.segments.size():
		var segment: MoveSegment = staged.segments[staged.next]
		if segment.roll_before() and staged.waiting != StagedMove.CLEARED:
			_move_leg(state, staged, leg, kinds, leg_cost, events)
			staged.waiting = StagedMove.BEFORE
			_start_risky_roll(state, staged, segment, events)
			return
		staged.waiting = StagedMove.NOT_WAITING
		leg.append(segment.to)
		kinds.append(segment.kind)
		leg_cost += segment.cost
		staged.spent += segment.cost
		staged.next += 1
		var fall: float = segment.injury_drop()
		if fall > 0.0:
			_move_leg(state, staged, leg, kinds, leg_cost, events)
			staged.waiting = StagedMove.LANDING_INJURY
			_start_injury_roll(state, staged, fall, "landing from a %s of %.1f\"" % [
				"jump down" if segment.kind == Transitions.Kind.GAP_JUMP else "drop", fall
			], events)
			return
	staged.spent += staged.surcharge
	leg_cost += staged.surcharge
	_move_leg(state, staged, leg, kinds, leg_cost, events)
	_finish(state, staged, events)


## The roll's result: on along the path, or stop as the rules say.
static func _on_roll(state: GameState, result: RollResult, events: Array[GameEvent]) -> void:
	var staged: StagedMove = state.resolution as StagedMove
	if staged == null:
		return
	var model: ModelState = state.get_model(staged.model_id)
	match staged.waiting:
		StagedMove.BEFORE:
			if result.is_success() and staged.end_reason == "":
				staged.waiting = StagedMove.CLEARED
				_advance(state, events)
			else:
				_fail(state, staged, events)
		StagedMove.LANDING_INJURY:
			staged.waiting = StagedMove.NOT_WAITING
			if staged.end_reason != "" or not model.on_table() or model.down:
				_stop(state, staged, events, "the model did not land standing")
			else:
				_advance(state, events)
		StagedMove.FALL_INJURY:
			_stop(state, staged, events, "the model fell")


## A failed climb or jump.
static func _fail(state: GameState, staged: StagedMove, events: Array[GameEvent]) -> void:
	var segment: MoveSegment = staged.segments[staged.next]
	var model: ModelState = state.get_model(staged.model_id)
	var legality: MoveLegality = MoveLegality.new(state, model)
	if segment.kind != Transitions.Kind.GAP_JUMP:
		# It stays where it attempted the climb, if it can stop there.
		var here: Vector2 = Vector2(model.position.x, model.position.z)
		var surfaces: PackedInt32Array = legality.surfaces_at(model.position)
		if not surfaces.is_empty() and legality.stop_surcharge(model.position) == INF:
			var spot: Variant = legality.closest_stop(here, surfaces[0])
			if spot != null:
				_move_leg(state, staged, [model.position, spot] as Array[Vector3], [Transitions.Kind.WALK] as Array[Transitions.Kind], 0.0, events)
		_stop(state, staged, events, "the climb failed")
		return
	# It falls into the gap from over its middle.
	var over: Vector3 = segment.fall_point
	var over_2d: Vector2 = Vector2(over.x, over.z)
	var below: int = legality.surface_below(over_2d, over.y)
	var landing: Vector3 = model.position
	if below != -1:
		var spot: Variant = legality.closest_stop(over_2d, below)
		landing = spot if spot != null else legality.on_surface(over_2d, below)
	var height: float = maxf(over.y - landing.y, 0.0)
	var fell: GameEvent = GameEvent.new(GameEvent.Kind.MODEL_FELL, model.player, model.id, {
		"from": model.position, "over": over, "to": landing, "height": height,
	})
	events.append(fell)
	model.position = landing
	if Transitions.is_fall(height):
		staged.waiting = StagedMove.FALL_INJURY
		_start_injury_roll(state, staged, height, "falling %.1f\"" % height, events)
		return
	_stop(state, staged, events, "the jump failed")


## The move ends short of its path, and with it the activation.
static func _stop(state: GameState, staged: StagedMove, events: Array[GameEvent], why: String) -> void:
	state.resolution = null
	var model: ModelState = state.get_model(staged.model_id)
	events.append(GameEvent.new(GameEvent.Kind.MOVE_STOPPED, staged.player, staged.model_id, {
		"reason": why, "at": model.position, "spent": staged.spent,
	}))
	var reason: String = staged.end_reason if staged.end_reason != "" else why
	if state.turn.active_model_id == staged.model_id:
		TurnFlow.end_activation(state, events, reason)


## The whole path is carried out: the move stays open with what is left.
static func _finish(state: GameState, staged: StagedMove, events: Array[GameEvent]) -> void:
	state.resolution = null
	if staged.end_reason != "":
		if state.turn.active_model_id == staged.model_id:
			TurnFlow.end_activation(state, events, staged.end_reason)
		return
	TurnFlow.continue_move(state, state.get_model(staged.model_id), staged.action_id, staged.left(), events)


## Moves the model along `leg` (its position first) and reports it, if it goes anywhere.
static func _move_leg(
	state: GameState, staged: StagedMove, leg: Array[Vector3], kinds: Array[Transitions.Kind], cost: float,
	events: Array[GameEvent]
) -> void:
	if leg.size() < 2:
		return
	var model: ModelState = state.get_model(staged.model_id)
	var end: Vector3 = leg[leg.size() - 1]
	var legality: MoveLegality = MoveLegality.new(state, model)
	var surfaces: PackedInt32Array = legality.surfaces_at(end)
	if not surfaces.is_empty():
		# Exactly on the floor, so small errors never build up.
		end.y = legality.field.surface_height(surfaces[0], Vector2(end.x, end.z))
		leg[leg.size() - 1] = end
	model.position = end
	events.append(GameEvent.new(GameEvent.Kind.MODEL_MOVED, staged.player, staged.model_id, {
		"path": leg.duplicate(), "kinds": kinds.duplicate(), "cost": cost, "left": staged.left(),
	}))


static func _start_risky_roll(state: GameState, staged: StagedMove, segment: MoveSegment, events: Array[GameEvent]) -> void:
	var roll: Dictionary = segment.rolls()[0]
	var label: String = String(roll["label"]).replace(" (risky)", "")
	events.append(GameEvent.new(GameEvent.Kind.MOVE_ROLL_POINT, staged.player, staged.model_id, {
		"roll": roll["label"], "at": segment.from,
	}))
	var request: RollRequest = RollRequest.success(staged.player, staged.model_id, staged.action_id, true, label)
	request.context = {&"move_roll": roll["kind"]}
	request.on_resolved = _on_roll
	RollPipeline.start(state, request, events)


static func _start_injury_roll(
	state: GameState, staged: StagedMove, fall: float, what: String, events: Array[GameEvent]
) -> void:
	var model: ModelState = state.get_model(staged.model_id)
	events.append(GameEvent.new(GameEvent.Kind.MOVE_ROLL_POINT, staged.player, staged.model_id, {
		"roll": "Injury roll: %s" % what, "at": model.position,
	}))
	var request: RollRequest = RollRequest.injury(1 - model.player, -1, model.id)
	request.label = "Injury roll (%s)" % what
	request.context = {&"fall_inches": fall}
	request.on_resolved = _on_roll
	RollPipeline.start(state, request, events)
