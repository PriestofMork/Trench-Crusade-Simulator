class_name Ruleset
extends RefCounted
## The registries every rule plugs into: actions, roll modifier providers,
## pre-roll choices and roll reactions. The activation code and the roll
## pipeline only walk these lists. standard() builds the rules of this game
## from data/rules/core_rules.json plus the reactions written in code.
##
## Order matters for choices: they are asked in registration order (blood
## before blessing: the opponent decides first, ruling 7 of brief 005).

const RULES_FILE: String = "res://data/rules/core_rules.json"
const DECIDERS: Dictionary[String, MarkerSpendChoice.Decider] = {
	"owner": MarkerSpendChoice.Decider.OWNER,
	"opponent": MarkerSpendChoice.Decider.OPPONENT,
}
const ROLL_KINDS: Dictionary[String, RollRequest.Kind] = {
	"success": RollRequest.Kind.SUCCESS,
	"injury": RollRequest.Kind.INJURY,
	"d6": RollRequest.Kind.D6,
	"roll_off": RollRequest.Kind.ROLL_OFF,
}

static var _standard_data: Dictionary = {}

## In the order they are offered.
var actions: Array[ActionDef] = []
var modifier_providers: Array[RollModifierProvider] = []
var choice_providers: Array[RollChoiceProvider] = []
var reactions: Array[RollReaction] = []


func action(id: StringName) -> ActionDef:
	for definition: ActionDef in actions:
		if definition.id == id:
			return definition
	return null


func add_action(definition: ActionDef) -> void:
	actions.append(definition)


func add_modifier_provider(provider: RollModifierProvider) -> void:
	modifier_providers.append(provider)


func add_choice_provider(provider: RollChoiceProvider) -> void:
	choice_providers.append(provider)


func add_reaction(reaction: RollReaction) -> void:
	reactions.append(reaction)


## A new behaviour for a name an action entry can use.
static func behaviour(behaviour_name: String) -> ActionBehaviour:
	match behaviour_name:
		"move":
			return MoveBehaviour.new()
		"roll_then_move":
			return RollThenMoveBehaviour.new()
	push_error("Ruleset: unknown action behaviour '%s'" % behaviour_name)
	return ActionBehaviour.new()


static func standard() -> Ruleset:
	if _standard_data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_FILE))
		if not parsed is Dictionary:
			push_error("Ruleset: cannot read %s" % RULES_FILE)
			return Ruleset.new()
		_standard_data = parsed
	return from_data(_standard_data)


static func from_data(data: Dictionary) -> Ruleset:
	var rules: Ruleset = Ruleset.new()
	for entry: Dictionary in data.get("actions", []):
		rules.add_action(ActionDef.new(
			StringName(entry["id"]), String(entry["label"]), bool(entry.get("move_action", false)),
			bool(entry.get("risky", false)), behaviour(String(entry["behaviour"]))
		))
	for entry: Dictionary in data.get("marker_spending", []):
		rules.add_choice_provider(MarkerSpendChoice.new(
			StringName(entry["id"]), StringName(entry["marker"]), DECIDERS[String(entry["decider"])],
			int(entry.get("success_dice", 0)), int(entry.get("injury_dice", 0))
		))
	for entry: Dictionary in data.get("warband_flags", []):
		var kinds: Array[RollRequest.Kind] = []
		for kind: String in entry.get("roll_kinds", []):
			kinds.append(ROLL_KINDS[kind])
		rules.add_modifier_provider(WarbandFlagModifier.new(
			StringName(entry["flag"]), String(entry["label"]), kinds, int(entry.get("dice", 0)),
			bool(entry.get("makes_risky", false))
		))
	rules.add_reaction(RiskyFailureReaction.new())
	return rules
