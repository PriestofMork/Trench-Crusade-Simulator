class_name DownResultOverride
extends OverrideCommand
## Applies a Down result to a model by hand, as a rule would: through
## GoingDown.result(), so a standing model next to a ledge makes the ledge
## roll first (brief 008b). For trying the Down rules before attacks exist.
## Only while nothing else is being resolved.

var model_id: int


func _init(p_model_id: int) -> void:
	model_id = p_model_id


func validate(state: GameState) -> String:
	var model: ModelState = state.get_model(model_id)
	if model == null:
		return "No model with id %d." % model_id
	if not model.on_table():
		return "Model %d is Out of Action." % model_id
	if state.pending != null or state.active_roll != null or state.resolution != null or not state.interrupts.is_empty():
		return "Finish what is under way first."
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = _override_event(model_id, "Model %d suffers a Down result" % model_id)
	GoingDown.result(state, state.get_model(model_id), events)
	return events
