class_name MarkerSpendChoice
extends RollChoiceProvider
## Spending markers on a roll, configured by data (see
## data/rules/core_rules.json, "marker_spending"). One provider may cover
## several kinds that are spent the same way (blood and infection,
## docs/rules/markers.md): they are offered in one prompt with a count for
## each. On a success roll the markers are the rolling model's; on an injury
## roll, the target's. The marked model's owner or opponent decides, and each
## marker spent is worth `success_dice` or `injury_dice` dice.

enum Decider { OWNER, OPPONENT }

## The kinds offered, in prompt order.
var markers: Array[StringName] = []
var decider: Decider
var success_dice: int
var injury_dice: int


func _init(
	p_id: StringName, p_markers: Array[StringName], p_decider: Decider, p_success_dice: int, p_injury_dice: int
) -> void:
	id = p_id
	markers = p_markers
	decider = p_decider
	success_dice = p_success_dice
	injury_dice = p_injury_dice


func offer(state: GameState, request: RollRequest) -> RollChoice:
	var marked: ModelState = _marked(state, request)
	var per_marker: int = _dice_per_marker(request)
	if marked == null or per_marker == 0:
		return null
	var options: Array[RollChoice.Option] = []
	var names: PackedStringArray = PackedStringArray()
	for kind: StringName in markers:
		var count: int = marked.marker_count(kind)
		if count > 0:
			options.append(RollChoice.Option.new(kind, Markers.label(kind), count, per_marker))
			names.append(Markers.label(kind).to_lower())
	if options.is_empty():
		return null
	var player: int = marked.player if decider == Decider.OWNER else 1 - marked.player
	var label: String = "Spend %s markers of model %d (%+d die each)" % [" and ".join(names), marked.id, per_marker]
	return RollChoice.new(id, player, marked.id, label, options)


func spend_error(state: GameState, choice: RollChoice, amounts: Array[int]) -> String:
	var error: String = super(state, choice, amounts)
	if error != "":
		return error
	var marked: ModelState = state.get_model(choice.model_id)
	for i: int in choice.options.size():
		var kind: StringName = choice.options[i].key
		if marked == null or amounts[i] > marked.marker_count(kind):
			return "The model does not have %d %s markers." % [amounts[i], String(kind)]
	return ""


func spend(state: GameState, _request: RollRequest, choice: RollChoice, amounts: Array[int]) -> Array[RollModifier]:
	var result: Array[RollModifier] = []
	var marked: ModelState = state.get_model(choice.model_id)
	for i: int in choice.options.size():
		var amount: int = amounts[i]
		if amount <= 0:
			continue
		var option: RollChoice.Option = choice.options[i]
		marked.set_markers(option.key, marked.marker_count(option.key) - amount)
		var noun: String = option.label.to_lower() + (" marker" if amount == 1 else " markers")
		var label: String = "%d %s on model %d" % [amount, noun, marked.id]
		result.append(RollModifier.new(label, option.dice_per_unit * amount, false, id))
	return result


func _marked(state: GameState, request: RollRequest) -> ModelState:
	match request.kind:
		RollRequest.Kind.SUCCESS:
			return state.get_model(request.actor_id)
		RollRequest.Kind.INJURY:
			return state.get_model(request.target_id)
	return null


func _dice_per_marker(request: RollRequest) -> int:
	match request.kind:
		RollRequest.Kind.SUCCESS:
			return success_dice
		RollRequest.Kind.INJURY:
			return injury_dice
	return 0
