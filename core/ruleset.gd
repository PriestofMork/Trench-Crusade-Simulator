class_name Ruleset
extends RefCounted
## The registries every rule plugs into: actions, roll modifier providers,
## pre-roll choices, roll reactions and activation-start rules. The activation code and the roll
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
const MELEE: Dictionary[String, ActionDef.Melee] = {
	"any": ActionDef.Melee.ANY,
	"forbidden": ActionDef.Melee.FORBIDDEN,
	"required": ActionDef.Melee.REQUIRED,
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
## Run at the start of every activation, in order.
var activation_rules: Array[ActivationRule] = []
## Whether one model can see another (brief 007: a temporary always-yes
## implementation until brief 008).
var sight: Sight = TemporarySight.new()


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


func add_activation_rule(rule: ActivationRule) -> void:
	activation_rules.append(rule)


## The first registered reaction or provider with this id, or null.
func reaction(id: StringName) -> RollReaction:
	for entry: RollReaction in reactions:
		if entry.id == id:
			return entry
	return null


func modifier_provider(id: StringName) -> RollModifierProvider:
	for entry: RollModifierProvider in modifier_providers:
		if entry.id == id:
			return entry
	return null


## A new behaviour for a name an action entry can use.
static func behaviour(behaviour_name: String) -> ActionBehaviour:
	match behaviour_name:
		"move":
			return MoveBehaviour.new()
		"roll_then_move":
			return RollThenMoveBehaviour.new()
		"charge":
			return ChargeBehaviour.new()
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
			bool(entry.get("risky", false)), behaviour(String(entry["behaviour"])),
			MELEE[String(entry.get("melee", "any"))]
		))
	for entry: Dictionary in data.get("marker_spending", []):
		var kinds: Array[StringName] = []
		for kind: String in entry.get("markers", [entry.get("marker", "")]):
			kinds.append(StringName(kind))
		rules.add_choice_provider(MarkerSpendChoice.new(
			StringName(entry["id"]), kinds, DECIDERS[String(entry["decider"])],
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
	for entry: Dictionary in data.get("context_dice", []):
		var kinds: Array[RollRequest.Kind] = []
		for kind: String in entry.get("roll_kinds", []):
			kinds.append(ROLL_KINDS[kind])
		rules.add_modifier_provider(ContextStepModifier.new(
			StringName(entry["id"]), StringName(entry["context"]), String(entry["label"]), kinds,
			float(entry["step"]), int(entry["dice"])
		))
	for entry: Dictionary in data.get("activation_start", []):
		match String(entry["rule"]):
			"marker_growth":
				rules.add_activation_rule(MarkerGrowthRule.new(StringName(entry["marker"]), int(entry.get("amount", 1))))
			_:
				push_error("Ruleset: unknown activation rule '%s'" % entry["rule"])
	rules.add_reaction(RiskyFailureReaction.new())
	if data.has("injury_results"):
		var table: Dictionary = data["injury_results"]
		var bands: Array[InjuryResultReaction.Band] = []
		for band: Dictionary in table.get("bands", []):
			bands.append(InjuryResultReaction.Band.new(
				int(band["min"]), int(band.get("max", -1)), int(band.get("blood", 0)),
				bool(band.get("down", false)), bool(band.get("out_of_action", false))
			))
		rules.add_reaction(InjuryResultReaction.new(bands, int(table.get("down_on_down_blood", 1))))
	return rules
