class_name SetDownOverride
extends OverrideCommand
## Sets or clears a model's Down state.

var model_id: int
var down: bool


func _init(p_model_id: int, p_down: bool) -> void:
	model_id = p_model_id
	down = p_down


func validate(state: GameState) -> String:
	if state.get_model(model_id) == null:
		return "No model with id %d." % model_id
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	state.get_model(model_id).down = down
	return _override_event(model_id, "Model %d %s" % [model_id, "is Down" if down else "is standing"])
