class_name RollRequest
extends RefCounted
## What is to be rolled, as data (docs/rules/rolls.md). Built by whatever rule
## needs a roll; the pipeline collects modifiers for it, asks the pre-roll
## choices, resolves it and calls `on_resolved`.

enum Kind {
	## 2d6 against 7+ (criticals only if `allows_critical`).
	SUCCESS,
	## Dice kept 2, or 3 for a Bloodbath; modifiers both ways; no outcome here.
	INJURY,
	## A plain die.
	D6,
	## One d6 per player; the higher wins, a tie is a draw.
	ROLL_OFF,
}

const SUCCESS_TARGET: int = 7
const CRITICAL_TARGET: int = 12

var kind: Kind
## How many dice are kept: 2 normally, 3 for a Bloodbath injury roll, 1 for a d6.
var dice_kept: int = 2
## Risky before modifiers (a modifier can also make it risky).
var risky: bool = false
## Whether a total of 12 or more counts as a critical.
var allows_critical: bool = false
## The player rolling, or -1 for both (a roll-off).
var roller: int = -1
## Context; unused parts are -1 or empty.
var actor_id: int = -1
var target_id: int = -1
var action_id: StringName = &""
var weapon_id: StringName = &""
## What is being rolled, for the breakdown ("Dash").
var label: String = ""
## Situation facts for modifier providers to read, by plain id (for example
## &"fall_inches" on the injury roll of a fall). Never changed after the
## roll starts.
var context: Dictionary = {}
## Called as on_resolved(state, result, events) after the reactions ran.
var on_resolved: Callable = Callable()


func _init(p_kind: Kind, p_roller: int, p_dice_kept: int = 2) -> void:
	kind = p_kind
	roller = p_roller
	dice_kept = p_dice_kept


## A success roll by `actor` (owned by `p_roller`) for an action.
static func success(
	p_roller: int, p_actor_id: int, p_action_id: StringName, p_risky: bool, p_label: String
) -> RollRequest:
	var request: RollRequest = RollRequest.new(Kind.SUCCESS, p_roller)
	request.actor_id = p_actor_id
	request.action_id = p_action_id
	request.risky = p_risky
	request.label = p_label
	return request


## An injury roll by `p_roller` against `p_target_id`.
static func injury(p_roller: int, p_actor_id: int, p_target_id: int, p_dice_kept: int = 2) -> RollRequest:
	var request: RollRequest = RollRequest.new(Kind.INJURY, p_roller, p_dice_kept)
	request.actor_id = p_actor_id
	request.target_id = p_target_id
	request.label = "Injury roll"
	return request


## A plain d6 by `p_roller` (a charge's distance): no outcome, just the total.
static func d6(
	p_roller: int, p_actor_id: int, p_target_id: int, p_action_id: StringName, p_label: String
) -> RollRequest:
	var request: RollRequest = RollRequest.new(Kind.D6, p_roller, 1)
	request.actor_id = p_actor_id
	request.target_id = p_target_id
	request.action_id = p_action_id
	request.label = p_label
	return request


static func roll_off() -> RollRequest:
	var request: RollRequest = RollRequest.new(Kind.ROLL_OFF, -1, 1)
	request.label = "Roll-off"
	return request


func kind_name() -> String:
	return Kind.keys()[kind]
