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
	## Pick one path for `model_id` within `budget` inches, or decline
	## (MoveCommand, DeclineMoveCommand).
	MOVE,
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
