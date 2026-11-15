class_name GameEvent
extends RefCounted
## One thing that happened while a command was applied. Commands return their
## events in order; the game layer plays them back instead of comparing state
## to guess what changed.

enum Kind {
	TURN_STARTED,
	TURN_ENDED,
	FIRST_PLAYER_CHOSEN,
	PLAYER_TO_ACT,
	ACTIVATION_STARTED,
	MODEL_STOOD_UP,
	ACTION_STARTED,
	ROLL_REQUESTED,
	ROLL_CHOICE_MADE,
	ROLL_RESOLVED,
	DECISION_NEEDED,
	MODEL_MOVED,
	MOVE_FINISHED,
	ACTIVATION_ENDED,
	OVERRIDE_APPLIED,
	## A model gained markers from a rule ("marker", "count", "reason").
	MARKERS_GAINED,
	## An injury roll's result was applied ("text", "blood", "down", "out_of_action").
	INJURY_APPLIED,
	MODEL_WENT_DOWN,
	MODEL_OUT_OF_ACTION,
	## A model fell ("from", "to", "height": inches).
	MODEL_FELL,
	## A move reached a roll point and waits for its roll ("roll": label, "at").
	MOVE_ROLL_POINT,
	## A move with rolls in it stopped short of its end ("reason", "at").
	MOVE_STOPPED,
}

var kind: Kind
## The player the event is about, or -1.
var player: int = -1
## The model the event is about, or -1.
var model_id: int = -1
## Set on roll events.
var roll: ActiveRoll = null
## Set on ROLL_RESOLVED.
var result: RollResult = null
## Set on DECISION_NEEDED.
var decision: PendingDecision = null
## Anything else, by kind: "turn", "action_id", "reason", "path" (Array[Vector3],
## start first), "kinds" (per path segment, Transitions.Kind), "cost",
## "amount", "modifiers" (Array[RollModifier]), "text".
var data: Dictionary = {}


func _init(p_kind: Kind, p_player: int = -1, p_model_id: int = -1, p_data: Dictionary = {}) -> void:
	kind = p_kind
	player = p_player
	model_id = p_model_id
	data = p_data


func kind_name() -> String:
	return Kind.keys()[kind]


## One line for logs and tests.
func describe() -> String:
	var parts: PackedStringArray = PackedStringArray([kind_name()])
	if player != -1:
		parts.append("player %d" % player)
	if model_id != -1:
		parts.append("model %d" % model_id)
	if decision != null:
		parts.append(PendingDecision.Kind.keys()[decision.kind])
	if result != null:
		parts.append(result.describe())
	if data.has("reason"):
		parts.append(String(data["reason"]))
	return " ".join(parts)


static func kinds(events: Array[GameEvent]) -> Array[Kind]:
	var result_kinds: Array[Kind] = []
	for event: GameEvent in events:
		result_kinds.append(event.kind)
	return result_kinds
