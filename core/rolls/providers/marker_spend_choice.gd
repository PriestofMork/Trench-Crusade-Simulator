class_name MarkerSpendChoice
extends RollChoiceProvider
## Spending one kind of marker on a roll, configured by data (see
## data/rules/core_rules.json, "marker_spending"). On a success roll the
## markers are the rolling model's; on an injury roll, the target's. The
## marked model's owner or opponent decides, and each marker spent is worth
## `success_dice` or `injury_dice` dice.

enum Decider { OWNER, OPPONENT }

var marker: StringName
var decider: Decider
var success_dice: int
var injury_dice: int


func _init(
	p_id: StringName, p_marker: StringName, p_decider: Decider, p_success_dice: int, p_injury_dice: int
) -> void:
	id = p_id
	marker = p_marker
	decider = p_decider
	success_dice = p_success_dice
	injury_dice = p_injury_dice


func offer(state: GameState, request: RollRequest) -> RollChoice:
	var marked: ModelState = _marked(state, request)
	var per_marker: int = _dice_per_marker(request)
	if marked == null or per_marker == 0:
		return null
	var count: int = marked.marker_count(marker)
	if count <= 0:
		return null
	var player: int = marked.player if decider == Decider.OWNER else 1 - marked.player
	var label: String = "Spend %s markers of model %d (%+d die each)" % [Markers.label(marker).to_lower(), marked.id, per_marker]
	return RollChoice.new(id, player, marked.id, count, per_marker, label)


func spend_error(state: GameState, choice: RollChoice, amount: int) -> String:
	var error: String = super(state, choice, amount)
	if error != "":
		return error
	var marked: ModelState = state.get_model(choice.model_id)
	if marked == null or amount > marked.marker_count(marker):
		return "The model does not have %d %s markers." % [amount, String(marker)]
	return ""


func spend(state: GameState, request: RollRequest, choice: RollChoice, amount: int) -> Array[RollModifier]:
	if amount <= 0:
		return []
	var marked: ModelState = state.get_model(choice.model_id)
	marked.set_markers(marker, marked.marker_count(marker) - amount)
	var noun: String = Markers.label(marker).to_lower() + (" marker" if amount == 1 else " markers")
	var label: String = "%d %s on model %d" % [amount, noun, marked.id]
	return [RollModifier.new(label, choice.dice_per_unit * amount, false, id)]


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
