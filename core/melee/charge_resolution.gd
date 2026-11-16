class_name ChargeResolution
extends Resolution
## A charge under way (see ChargeExecution): declared, waiting for its D6,
## then, if it reached with distance to spare, for the choice of where around
## the target's base it ends. Lives on GameState.resolution; undo snapshots
## copy it.

## Waiting for the charge D6.
const ROLL: StringName = &"roll"
## Waiting for the contact choice (PendingDecision CHARGE_CONTACT).
const CONTACT: StringName = &"contact"

var player: int = -1
var action_id: StringName = &""
var declared_id: int = -1
var target_id: int = -1
## Waypoints to first contact (shared, never changed), what they cost
## without and with the stop at first contact, and the charge distance once
## rolled.
var path: Array[Vector3] = []
var path_cost: float = 0.0
var length: float = 0.0
var distance: float = 0.0
var waiting: StringName = ROLL


func copy() -> Resolution:
	var result: ChargeResolution = ChargeResolution.new()
	copy_into(result)
	result.player = player
	result.action_id = action_id
	result.declared_id = declared_id
	result.target_id = target_id
	result.path = path
	result.path_cost = path_cost
	result.length = length
	result.distance = distance
	result.waiting = waiting
	return result
