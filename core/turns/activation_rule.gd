class_name ActivationRule
extends RefCounted
## A rule that acts at the start of a model's activation (after it stands
## up), such as infection markers growing. Register it in the Ruleset.

var id: StringName = &""


func on_activation_start(_state: GameState, _model: ModelState, _events: Array[GameEvent]) -> void:
	pass
