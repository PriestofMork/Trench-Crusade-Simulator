class_name StagedMove
extends Resolution
## A move step part-way through (see MoveExecution): every move of every
## action (Move, Dash, Retreat, Charge, sliding in contact) is one of these.
## Lives on GameState.resolution while the move waits for a roll; undo
## snapshots copy it, so stepping back restores it exactly.

## Waiting for nothing (between stages).
const NOT_WAITING: StringName = &""
## The risky roll before segment `next` (a sheer climb, a gap jump).
const BEFORE: StringName = &"before"
## That roll succeeded: segment `next` is carried out next.
const CLEARED: StringName = &"cleared"
## The injury roll after landing from segment `next` - 1 (a drop, a jump down).
const LANDING_INJURY: StringName = &"landing_injury"
## The injury roll of a fall after a failed jump; the move stops after it.
const FALL_INJURY: StringName = &"fall_injury"

var player: int
## The action whose move this is (an open move stays open with what is left).
var action_id: StringName
## The movement the step could use when it started.
var budget: float
## The path's segments, shared and never changed.
var segments: Array[MoveSegment] = []
## Paid for stopping at the end (a low obstacle), on top of the segments.
var surcharge: float = 0.0
## The next segment to carry out.
var next: int = 0
## Movement spent so far; it stays spent whatever happens.
var spent: float = 0.0
## What the move waits for (one of the constants above).
var waiting: StringName = NOT_WAITING
## How the move treats enemy 1" zones (a retreat), null for the normal rule.
var zones: EnemyZones = null
## What the move is part of, if it is not an ordinary move step (a charge),
## or null. Copied with it.
var parent: Resolution = null
## Called as on_end(state, staged, stopped: bool, events) when the move is
## over, instead of keeping an open move: `stopped` if a roll stopped it
## short (the activation then ends after the call, as for any move). A static
## function, so it may be kept across commands, undo and replay. Empty for an
## ordinary move step.
var on_end: Callable = Callable()
## Added to every MODEL_MOVED of the move, so the view can tell what it is
## ({"charge": true}, {"slide": true}).
var event_data: Dictionary = {}


func copy() -> Resolution:
	var result: StagedMove = StagedMove.new()
	copy_into(result)
	result.player = player
	result.action_id = action_id
	result.budget = budget
	result.segments = segments
	result.surcharge = surcharge
	result.next = next
	result.spent = spent
	result.waiting = waiting
	result.zones = zones
	result.parent = parent.copy() if parent != null else null
	result.on_end = on_end
	result.event_data = event_data
	return result


func left() -> float:
	return maxf(budget - spent, 0.0)
