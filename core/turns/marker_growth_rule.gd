class_name MarkerGrowthRule
extends ActivationRule
## docs/rules/markers.md, infection markers: at the start of a model's
## activation, if it has at least one marker of `marker`, it gains `amount`
## more, up to the cap. Configured by data (core_rules.json, "activation_start").

var marker: StringName
var amount: int


func _init(p_marker: StringName, p_amount: int = 1) -> void:
	id = StringName("%s_growth" % p_marker)
	marker = p_marker
	amount = p_amount


func on_activation_start(_state: GameState, model: ModelState, events: Array[GameEvent]) -> void:
	var before: int = model.marker_count(marker)
	if before <= 0:
		return
	model.set_markers(marker, before + amount)
	var gained: int = model.marker_count(marker) - before
	if gained > 0:
		events.append(GameEvent.new(GameEvent.Kind.MARKERS_GAINED, model.player, model.id, {
			"marker": marker, "count": gained, "reason": "%s grows" % Markers.label(marker).to_lower()
		}))
