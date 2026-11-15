class_name RollChoice
extends RefCounted
## A pre-roll offer from a choice provider: `player` may spend some of one or
## more things at once (one prompt, a separate count for each option), such
## as blood and infection markers, each unit worth its option's dice.


## One thing on offer: spend 0..maximum of it, each unit worth dice_per_unit.
class Option:
	extends RefCounted
	## What is spent (a marker kind).
	var key: StringName
	## For the prompt ("Blood").
	var label: String
	var maximum: int
	var dice_per_unit: int

	func _init(p_key: StringName, p_label: String, p_maximum: int, p_dice_per_unit: int) -> void:
		key = p_key
		label = p_label
		maximum = p_maximum
		dice_per_unit = p_dice_per_unit


## Id of the provider that made it.
var provider_id: StringName
## Who decides.
var player: int
## The model whose markers (or other resource) would be spent, or -1.
var model_id: int = -1
## What may be spent, in prompt order; an answer gives one count per option.
var options: Array[Option] = []
## The first option's limit and worth (for one-option choices).
var maximum: int = 0
var dice_per_unit: int = 0
## What the prompt offers ("Spend blood markers on model 3").
var label: String


func _init(
	p_provider_id: StringName, p_player: int, p_model_id: int, p_label: String, p_options: Array[Option]
) -> void:
	provider_id = p_provider_id
	player = p_player
	model_id = p_model_id
	label = p_label
	options = p_options
	if not options.is_empty():
		maximum = options[0].maximum
		dice_per_unit = options[0].dice_per_unit


## Why `amounts` (one per option) is not a valid answer, or "".
func amounts_error(amounts: Array[int]) -> String:
	if amounts.size() != options.size():
		return "Give one count for each of the %d options." % options.size()
	for i: int in options.size():
		if amounts[i] < 0 or amounts[i] > options[i].maximum:
			return "%s: choose between 0 and %d." % [options[i].label, options[i].maximum]
	return ""
