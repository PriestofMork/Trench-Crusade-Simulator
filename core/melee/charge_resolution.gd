class_name ChargeResolution
extends Resolution
## A charge under way (see ChargeExecution): declared and waiting for its D6;
## then moving along its route (a StagedMove on GameState.resolution, with
## this as its parent); then, if it reached base contact with distance to
## spare, waiting for the choice of where around the target's base it ends,
## and sliding there. Undo snapshots copy it.

## Waiting for the charge D6.
const ROLL: StringName = &"roll"
## Moving along the route (the StagedMove is on GameState.resolution).
const MOVING: StringName = &"moving"
## Waiting for the contact choice (PendingDecision CHARGE_CONTACT).
const CONTACT: StringName = &"contact"
## Sliding around the target's base to the chosen position.
const SLIDING: StringName = &"sliding"

var player: int = -1
var action_id: StringName = &""
var declared_id: int = -1
var target_id: int = -1
## The route choice the charge was declared with (ruling 2 of brief 008b).
var allow_rolls: bool = false
var descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
## Waypoints of the route (shared, never changed), what it costs with any
## stop surcharge at its end, and whether it ends in base contact (else at
## the closest position to the target, ruling 6).
var path: Array[Vector3] = []
var length: float = 0.0
var contact: bool = true
## The charge distance once rolled, and whether it covers the route.
var distance: float = 0.0
var reaches: bool = false
var waiting: StringName = ROLL


func copy() -> Resolution:
	var result: ChargeResolution = ChargeResolution.new()
	copy_into(result)
	result.player = player
	result.action_id = action_id
	result.declared_id = declared_id
	result.target_id = target_id
	result.allow_rolls = allow_rolls
	result.descent_mode = descent_mode
	result.path = path
	result.length = length
	result.contact = contact
	result.distance = distance
	result.reaches = reaches
	result.waiting = waiting
	return result
