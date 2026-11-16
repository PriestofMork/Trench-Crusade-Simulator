extends GutTest
## Moves with rolls in them, carried out in stages (MoveExecution): sheer
## climbs, gap jumps, drops and falls and their results, the events they
## make, undo in the middle and as a whole, and replay.

const R32: float = 0.62992126
const K = Transitions.Kind
const E = GameEvent.Kind

var state: GameState


func before_each() -> void:
	state = GameState.new(1)


func _piece(center: Vector2, size: Vector3, tag: TerrainPiece.Tag = TerrainPiece.Tag.NONE) -> void:
	assert_eq(state.execute(PlaceTerrainCommand.new(center, size, 0.0, 0.0, tag)), "")


func _place(pos: Vector3, movement: float = 6.0, player: int = 0) -> int:
	var command: PlaceModelCommand = PlaceModelCommand.new(player, pos, 32, movement)
	assert_eq(state.execute(command), "", "placing at %s" % str(pos))
	return command.placed_model_id


## The next rolls: a list of [dice rolled, kept, highest, low total, high total].
func _rig(rolls: Array) -> void:
	assert_true(DiceRig.rig_sequence(state, rolls), "a seed for %s" % str(rolls))


func _ok(command: Command) -> Array[GameEvent]:
	var result: CommandResult = state.submit(command)
	assert_eq(result.error, "", command.get_script().get_global_name())
	return result.events


## Grants `id` a move, rigs the dice for `rolls` (see _rig()) and sends the
## path; returns its events.
func _move(
	id: int, points: Array[Vector3], rolls: Array,
	mode: Transitions.DescentMode = Transitions.DescentMode.DROP
) -> Array[GameEvent]:
	TurnHelper.grant_move(state, id)
	_rig(rolls)
	return _ok(MoveCommand.new(state.get_model(id).player, id, points, mode))


func _kinds_of(events: Array[GameEvent]) -> Array[E]:
	return GameEvent.kinds(events)


func _find(events: Array[GameEvent], kind: E) -> GameEvent:
	for event: GameEvent in events:
		if event.kind == kind:
			return event
	return null


func _count(events: Array[GameEvent], kind: E) -> int:
	var n: int = 0
	for event: GameEvent in events:
		if event.kind == kind:
			n += 1
	return n


const SUCCESS: Array = [2, 2, true, 7, 12]
const FAILURE: Array = [2, 2, true, 2, 6]
## An injury roll at +1 die (3 dice, keep the highest 2).
const INJURY_PLUS1_BLOOD: Array = [3, 2, true, 2, 6]
const INJURY_PLUS1_DOWN: Array = [3, 2, true, 7, 8]
const INJURY_PLUS1_OUT: Array = [3, 2, true, 9, 12]


## A 4" block x 10..14, z 10..14; the model south of it at (12, 0, 16).
func _block(movement: float = 8.0) -> int:
	_piece(Vector2(12, 12), Vector3(4, 4, 4))
	return _place(Vector3(12, 0, 16), movement)


func _climb() -> Array[Vector3]:
	return [Vector3(12, 0, 14 + R32), Vector3(12, 4, 14), Vector3(12, 4, 13)]


func test_a_successful_sheer_climb_continues_with_the_height_paid() -> void:
	var id: int = _block()
	var events: Array[GameEvent] = _move(id, _climb(), [SUCCESS])
	assert_eq(_kinds_of(events), [
		E.MODEL_MOVED, E.MOVE_ROLL_POINT, E.ROLL_REQUESTED, E.ROLL_RESOLVED, E.MODEL_MOVED, E.DECISION_NEEDED,
	] as Array[E])
	var first: Array = events[0].data["path"]
	assert_eq(first[first.size() - 1], Vector3(12, 0, 14 + R32), "first to the wall, where the roll is made")
	assert_true(events[3].result.risky)
	assert_eq(state.get_model(id).position, Vector3(12, 4, 13))
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE)
	assert_almost_eq(state.pending.budget, 8.0 - 7.0, 0.0001, "2 to the wall, 4 up, 1 on top")
	assert_null(state.resolution)


func test_a_failed_sheer_climb_stays_at_the_foot_and_ends_the_activation() -> void:
	var id: int = _block()
	var events: Array[GameEvent] = _move(id, _climb(), [FAILURE])
	assert_eq(state.get_model(id).position, Vector3(12, 0, 14 + R32))
	assert_not_null(_find(events, E.MOVE_STOPPED))
	var ended: GameEvent = _find(events, E.ACTIVATION_ENDED)
	assert_not_null(ended)
	assert_eq(String(ended.data["reason"]), "failed risky roll")
	assert_eq(state.turn.active_model_id, -1)
	assert_null(state.resolution)
	assert_eq(_count(events, E.MODEL_MOVED), 1, "only the walk to the wall")


func test_a_failed_climb_where_it_cannot_stop_moves_to_the_closest_place() -> void:
	# A friend stands at the foot of the wall: the climber passes through it
	# to climb, but cannot stay there.
	var id: int = _block()
	var friend: int = _place(Vector3(12.9, 0, 14.75), 6.0)
	var events: Array[GameEvent] = _move(id, _climb(), [FAILURE])
	assert_eq(_count(events, E.MODEL_MOVED), 2, "to the wall, then out of the friend's base")
	var at: Vector3 = state.get_model(id).position
	var f: Vector3 = state.get_model(friend).position
	assert_true(Vector2(at.x, at.z).distance_to(Vector2(f.x, f.z)) >= 2.0 * R32 - 0.001, "not overlapping")
	assert_lt(Vector2(at.x, at.z).distance_to(Vector2(12, 14 + R32)), 1.5, "close by")


func test_climbing_down_a_sheer_surface() -> void:
	_piece(Vector2(12, 12), Vector3(4, 4, 4))
	var id: int = _place(Vector3(12, 4, 13), 8.0)
	var down: Array[Vector3] = [Vector3(12, 4, 14), Vector3(12, 0, 14 + R32), Vector3(12, 0, 16)]
	_move(id, down, [SUCCESS], Transitions.DescentMode.CLIMB_DOWN)
	assert_eq(state.get_model(id).position, Vector3(12, 0, 16))
	assert_almost_eq(state.pending.budget, 1.0, 0.0001, "1 + 4 + 2 of 8")
	before_each()
	_piece(Vector2(12, 12), Vector3(4, 4, 4))
	id = _place(Vector3(12, 4, 13), 8.0)
	_move(id, down, [FAILURE], Transitions.DescentMode.CLIMB_DOWN)
	assert_eq(state.get_model(id).position, Vector3(12, 4, 14), "it stays at the top")
	assert_eq(state.turn.active_model_id, -1)


## Platforms x 8..12 and x 14.5..18.5 (4" high, z 8..12); the model on the west one.
func _platforms(far_height: float = 4.0) -> int:
	_piece(Vector2(10, 10), Vector3(4, 4, 4))
	_piece(Vector2(16.5, 10), Vector3(4, far_height, 4))
	return _place(Vector3(11, 4, 10))


func test_a_successful_jump_lands_on_the_far_side_and_carries_on() -> void:
	var id: int = _platforms()
	var events: Array[GameEvent] = _move(id, [Vector3(12, 4, 10), Vector3(14.5, 4, 10), Vector3(15.5, 4, 10)], [SUCCESS])
	assert_eq(state.get_model(id).position, Vector3(15.5, 4, 10))
	var kinds: Array = events[events.size() - 2].data["kinds"]
	assert_eq(kinds[0], K.GAP_JUMP, "the leg after the roll starts with the jump")
	assert_almost_eq(state.pending.budget, 6.0 - 4.5, 0.0001)


func test_a_failed_jump_falls_into_the_gap_takes_the_injury_roll_and_ends() -> void:
	var id: int = _platforms()
	var events: Array[GameEvent] = _move(id, [Vector3(12, 4, 10), Vector3(14.5, 4, 10), Vector3(15.5, 4, 10)], [FAILURE, INJURY_PLUS1_BLOOD])
	var fell: GameEvent = _find(events, E.MODEL_FELL)
	assert_not_null(fell)
	assert_almost_eq(float(fell.data["height"]), 4.0, 0.0001)
	var at: Vector3 = state.get_model(id).position
	assert_almost_eq(at.y, 0.0, 0.0001, "on the first surface beneath: the table")
	assert_between(at.x, 12.0 + R32 - 0.001, 14.5 - R32 + 0.001, "in the gap")
	var injury: GameEvent = null
	for event: GameEvent in events:
		if event.kind == E.ROLL_RESOLVED and event.result.request.kind == RollRequest.Kind.INJURY:
			injury = event
	assert_not_null(injury, "a fall of 4\" makes the injury roll")
	assert_eq(injury.result.dice.size(), 3, "at +1 die")
	assert_eq(state.get_model(id).marker_count(Markers.BLOOD), 1)
	assert_eq(String(_find(events, E.ACTIVATION_ENDED).data["reason"]), "failed risky roll")
	assert_true(_kinds_of(events).find(E.ACTIVATION_ENDED) > _kinds_of(events).find(E.INJURY_APPLIED), "the fall is resolved first")


func test_a_jump_to_a_much_lower_far_side_takes_the_injury_roll_on_landing() -> void:
	var id: int = _platforms(1.0)
	var events: Array[GameEvent] = _move(id, [Vector3(12, 4, 10), Vector3(14.5, 1, 10), Vector3(15.5, 1, 10)], [SUCCESS, INJURY_PLUS1_BLOOD])
	assert_eq(_count(events, E.ROLL_RESOLVED), 2)
	assert_eq(state.get_model(id).position, Vector3(15.5, 1, 10), "standing: it carries on")
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE)


## A 5" platform x 8..12, z 8..12; the model on it.
func _high_platform() -> int:
	_piece(Vector2(10, 10), Vector3(4, 5, 4))
	return _place(Vector3(11, 5, 10), 6.0)


func _drop() -> Array[Vector3]:
	return [Vector3(12, 5, 10), Vector3(12 + R32, 0, 10), Vector3(14, 0, 10)]


func test_a_drop_takes_the_injury_roll_and_carries_on_standing() -> void:
	var id: int = _high_platform()
	var events: Array[GameEvent] = _move(id, _drop(), [INJURY_PLUS1_BLOOD])
	assert_eq(_kinds_of(events), [
		E.MODEL_MOVED, E.MOVE_ROLL_POINT, E.ROLL_REQUESTED, E.ROLL_RESOLVED, E.INJURY_APPLIED, E.MODEL_MOVED,
		E.DECISION_NEEDED,
	] as Array[E])
	var landed: Array = events[0].data["path"]
	assert_eq(landed[landed.size() - 1], Vector3(12 + R32, 0, 10), "the roll is made on landing")
	assert_eq(events[3].result.modifiers[0].source, &"fall")
	assert_eq(state.get_model(id).position, Vector3(14, 0, 10))
	assert_almost_eq(state.pending.budget, 6.0 - 3.0, 0.0001, "the drop costs nothing")


func test_a_drop_that_puts_the_model_down_ends_its_activation_there() -> void:
	var id: int = _high_platform()
	var events: Array[GameEvent] = _move(id, _drop(), [INJURY_PLUS1_DOWN])
	assert_true(state.get_model(id).down)
	assert_eq(state.get_model(id).position, Vector3(12 + R32, 0, 10))
	assert_eq(String(_find(events, E.ACTIVATION_ENDED).data["reason"]), "went Down")
	assert_null(state.resolution)


func test_a_drop_that_takes_the_model_out_of_action_removes_it() -> void:
	var id: int = _high_platform()
	_place(Vector3(40, 0, 40), 6.0, 1)
	var events: Array[GameEvent] = _move(id, _drop(), [INJURY_PLUS1_OUT])
	assert_true(state.get_model(id).out_of_action)
	assert_not_null(_find(events, E.MODEL_OUT_OF_ACTION))
	assert_eq(String(_find(events, E.ACTIVATION_ENDED).data["reason"]), "taken Out of Action")
	assert_eq(state.turn.player_to_act, 1)


func test_a_move_with_a_climb_and_a_drop_makes_the_expected_events() -> void:
	# Up the south face of the 4" block, across, and off the north face.
	var id: int = _block(13.0)
	var path: Array[Vector3] = [
		Vector3(12, 0, 14 + R32), Vector3(12, 4, 14), Vector3(12, 4, 10), Vector3(12, 0, 10 - R32), Vector3(12, 0, 8),
	]
	var events: Array[GameEvent] = _move(id, path, [SUCCESS, INJURY_PLUS1_BLOOD])
	assert_eq(_kinds_of(events), [
		E.MODEL_MOVED, E.MOVE_ROLL_POINT, E.ROLL_REQUESTED, E.ROLL_RESOLVED,
		E.MODEL_MOVED, E.MOVE_ROLL_POINT, E.ROLL_REQUESTED, E.ROLL_RESOLVED, E.INJURY_APPLIED,
		E.MODEL_MOVED, E.DECISION_NEEDED,
	] as Array[E])
	assert_eq(events[2].roll.request.kind, RollRequest.Kind.SUCCESS)
	assert_eq(events[6].roll.request.kind, RollRequest.Kind.INJURY)
	var over: Array = events[4].data["path"]
	assert_eq(over[over.size() - 1], Vector3(12, 0, 10 - R32), "climbed, crossed and dropped")
	assert_eq(state.get_model(id).position, Vector3(12, 0, 8))
	# 2 to the wall, 4 up, 4 across, R down (nothing for the height), 2 - R on.
	assert_almost_eq(state.pending.budget, 13.0 - (2.0 + 4.0 + 4.0 + R32 + 2.0 - R32), 0.0001)


func test_undo_in_the_middle_restores_the_pending_roll() -> void:
	var id: int = _block()
	_place(Vector3(40, 0, 40), 6.0, 1)
	TurnHelper.grant_move(state, id)
	state.get_model(id).set_markers(Markers.BLOOD, 2)
	_rig([SUCCESS])
	var before_move: int = state.history.size()
	var start: Vector3 = state.get_model(id).position
	var events: Array[GameEvent] = _ok(MoveCommand.new(0, id, _climb()))
	assert_eq(_kinds_of(events), [
		E.MODEL_MOVED, E.MOVE_ROLL_POINT, E.ROLL_REQUESTED, E.DECISION_NEEDED,
	] as Array[E], "the opponent is asked about blood markers first")
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE)
	assert_eq(state.pending.player, 1)
	assert_not_null(state.resolution)
	var at_wall: Vector3 = state.get_model(id).position
	var first: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 0))
	var first_result: String = _find(first, E.ROLL_RESOLVED).result.describe()
	var after: Vector3 = state.get_model(id).position
	# One step back: the prompt is waiting again, at the wall.
	assert_true(state.undo())
	assert_eq(state.pending.kind, PendingDecision.Kind.ROLL_CHOICE)
	assert_eq(state.pending.choice.provider_id, &"blood")
	assert_not_null(state.active_roll)
	assert_true(state.resolution is StagedMove)
	assert_eq((state.resolution as StagedMove).waiting, StagedMove.BEFORE)
	assert_eq(state.get_model(id).position, at_wall)
	assert_eq(state.get_model(id).marker_count(Markers.BLOOD), 2)
	# The same answer rolls the same dice and ends the same way.
	var again: Array[GameEvent] = _ok(RollChoiceCommand.new(1, 0))
	assert_eq(_find(again, E.ROLL_RESOLVED).result.describe(), first_result)
	assert_eq(state.get_model(id).position, after)
	# Redo after undo, too.
	assert_true(state.undo())
	assert_true(state.redo().ok())
	assert_eq(state.get_model(id).position, after)
	# And the whole move at once.
	assert_true(state.undo_to(before_move))
	assert_eq(state.get_model(id).position, start)
	assert_null(state.resolution)
	assert_null(state.active_roll)
	assert_eq(state.pending.kind, PendingDecision.Kind.MOVE)
	assert_almost_eq(state.pending.budget, 8.0, 0.0001)


## Builds a game, plays a move with a climb and a drop with markers to spend,
## and returns its event log and final state description.
func _play_once(seed_value: int) -> PackedStringArray:
	state = GameState.new(seed_value)
	var id: int = _block(13.0)
	_place(Vector3(40, 0, 40), 6.0, 1)
	var commands: Array[Command] = []
	var log: PackedStringArray = PackedStringArray()
	TurnHelper.grant_move(state, id)
	assert_eq(state.execute(SetMarkersOverride.new(id, Markers.BLOOD, 1)), "")
	assert_eq(state.execute(SetMarkersOverride.new(id, Markers.BLESSING, 1)), "")
	var path: Array[Vector3] = [
		Vector3(12, 0, 14 + R32), Vector3(12, 4, 14), Vector3(12, 4, 10), Vector3(12, 0, 10 - R32), Vector3(12, 0, 8),
	]
	commands.append(MoveCommand.new(0, id, path))
	for command: Command in commands:
		for event: GameEvent in state.submit(command).events:
			log.append(event.describe())
	for guard: int in 10:
		if state.pending == null or state.pending.kind != PendingDecision.Kind.ROLL_CHOICE:
			break
		for event: GameEvent in state.submit(RollChoiceCommand.new(state.pending.player, 1)).events:
			log.append(event.describe())
	var model: ModelState = state.get_model(id)
	log.append("at %s down %s out %s blood %d" % [str(model.position), model.down, model.out_of_action, model.marker_count(Markers.BLOOD)])
	return log


func test_the_same_seed_and_commands_give_the_same_result() -> void:
	var first: PackedStringArray = _play_once(11)
	var second: PackedStringArray = _play_once(11)
	assert_eq(second, first)
	# The log has the rolls in it, so this is not trivially equal.
	assert_true(" ".join(first).contains("ROLL_RESOLVED"))
	# Replaying the command log onto a fresh state gives the same state too.
	var recorded: Array[Command] = state.history.duplicate()
	var end: Vector3 = state.get_model(1).position
	var replay: GameState = GameState.new(11)
	for command: Command in recorded:
		assert_eq(replay.execute(command), "", command.get_script().get_global_name())
	assert_eq(replay.get_model(1).position, end)
	assert_eq(replay.get_model(1).marker_count(Markers.BLOOD), state.get_model(1).marker_count(Markers.BLOOD))
