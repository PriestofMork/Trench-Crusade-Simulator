class_name RollChoice
extends RefCounted
## A pre-roll offer from a choice provider: `player` may spend 0..`maximum`
## of something, each unit worth `dice_per_unit` dice on the roll.

## Id of the provider that made it.
var provider_id: StringName
## Who decides.
var player: int
## The model whose markers (or other resource) would be spent, or -1.
var model_id: int = -1
var maximum: int
var dice_per_unit: int
## What the prompt offers ("Spend blood markers on model 3").
var label: String


func _init(
	p_provider_id: StringName, p_player: int, p_model_id: int, p_maximum: int, p_dice_per_unit: int, p_label: String
) -> void:
	provider_id = p_provider_id
	player = p_player
	model_id = p_model_id
	maximum = p_maximum
	dice_per_unit = p_dice_per_unit
	label = p_label
