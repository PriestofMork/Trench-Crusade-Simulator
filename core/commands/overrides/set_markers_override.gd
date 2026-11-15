class_name SetMarkersOverride
extends OverrideCommand
## Sets one kind of marker on a model to `count` (0..Markers.CAP).

var model_id: int
var marker: StringName
var count: int


func _init(p_model_id: int, p_marker: StringName, p_count: int) -> void:
	model_id = p_model_id
	marker = p_marker
	count = p_count


func validate(state: GameState) -> String:
	if state.get_model(model_id) == null:
		return "No model with id %d." % model_id
	if not Markers.KINDS.has(marker):
		return "Unknown marker kind '%s'." % marker
	if count < 0 or count > Markers.CAP:
		return "Markers must be between 0 and %d, got %d." % [Markers.CAP, count]
	return ""


func apply(state: GameState) -> Array[GameEvent]:
	state.get_model(model_id).set_markers(marker, count)
	return _override_event(model_id, "Model %d: %s markers set to %d" % [model_id, marker, count])
