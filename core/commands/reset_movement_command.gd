class_name ResetMovementCommand
extends Command
## TEMPORARY: restores a model's movement to its full Movement characteristic.
## Stands in for activations until brief 003 (turns and activations) replaces it.
## Remove it then.

var model_id: int


func _init(p_model_id: int) -> void:
	model_id = p_model_id


func validate(state: GameState) -> String:
	if state.get_model(model_id) == null:
		return "No model with id %d." % model_id
	return ""


func apply(state: GameState) -> void:
	var model: ModelState = state.get_model(model_id)
	model.movement_left = model.movement
