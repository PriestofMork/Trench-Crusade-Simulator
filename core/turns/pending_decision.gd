class_name PendingDecision
extends RefCounted
## What core is waiting for: a choice only a player can make. Core never waits
## on the UI; it records this and resumes when a command answers it. Exactly
## one command type answers each kind, and it is rejected unless it comes from
## `player`.

enum Kind {
	## `player` picks who activates first this turn (ChooseFirstPlayerCommand).
	CHOOSE_FIRST_PLAYER,
	## The players roll off to see who chooses (RollOffCommand).
	ROLL_OFF,
	## Before the dice are rolled: spend something on the roll, such as
	## markers (RollChoiceCommand). See `choice`.
	ROLL_CHOICE,
	## An open move: `model_id` may move up to `budget` inches more, in one or
	## more steps (MoveCommand), or finish it (DeclineMoveCommand). Unlike the
	## others it does not hold the activation up: taking another action or
	## ending the activation finishes it, and what is left is lost.
	MOVE,
	## A charge reached base contact with distance to spare: `player` picks
	## where around the target's base it ends, from `positions`
	## (ChooseContactCommand); `default_index` is first contact.
	CHARGE_CONTACT,
}

## Means either player may answer.
const EITHER_PLAYER: int = -1

var kind: Kind
var player: int
var model_id: int = -1
## What the prompt says, without the player's name.
var prompt: String = ""
## ROLL_CHOICE: what is offered.
var choice: RollChoice = null
## MOVE: how far the model may move, inches.
var budget: float = 0.0
## MOVE: the action granting the move.
var action_id: StringName = &""
## CHARGE_CONTACT: where the charger may end (base centres, on their floors),
## and the one it ends on if nothing else is chosen.
var positions: Array[Vector3] = []
var default_index: int = 0
## CHARGE_CONTACT: per position, the ids of the enemies (Array[int]) it would
## count as charging.
var charged_ids: Array = []


func _init(p_kind: Kind, p_player: int, p_prompt: String = "") -> void:
	kind = p_kind
	player = p_player
	prompt = p_prompt


func is_for(p_player: int) -> bool:
	return player == EITHER_PLAYER or player == p_player


## The rejection for a command of `p_player` answering `p_kind`, or "".
static func check(state: GameState, p_kind: Kind, p_player: int) -> String:
	var pending: PendingDecision = state.pending
	if pending == null or pending.kind != p_kind:
		return "Nothing is waiting for that decision."
	if not pending.is_for(p_player):
		return "That decision is player %d's, not player %d's." % [pending.player + 1, p_player + 1]
	return ""
