class_name InjuryResultReaction
extends RollReaction
## Applies an injury roll's result to its target (docs/rules/attacks.md,
## Injury roll; rulings 1 to 4 of brief 006). The results are a data table
## (core_rules.json, "injury_results"): for each band of totals, how many
## blood markers are placed, and whether the target goes Down or is taken
## Out of Action. A Down result on a model already Down places
## `down_on_down_blood` extra blood markers instead. Markers stop at the cap.
## Going Down or Out of Action during the model's own activation ends it.


## One band of the table: totals min..max (max -1: no upper end).
class Band:
	extends RefCounted
	var min_total: int
	var max_total: int
	var blood: int
	var down: bool
	var out_of_action: bool

	func _init(p_min: int, p_max: int, p_blood: int, p_down: bool, p_out: bool) -> void:
		min_total = p_min
		max_total = p_max
		blood = p_blood
		down = p_down
		out_of_action = p_out

	func covers(total: int) -> bool:
		return total >= min_total and (max_total < 0 or total <= max_total)


var bands: Array[Band] = []
var down_on_down_blood: int = 1


func _init(p_bands: Array[Band], p_down_on_down_blood: int) -> void:
	id = &"injury_result"
	bands = p_bands
	down_on_down_blood = p_down_on_down_blood


## The band for a total, or null if the table has none.
func band_for(total: int) -> Band:
	for band: Band in bands:
		if band.covers(total):
			return band
	return null


func react(state: GameState, result: RollResult, events: Array[GameEvent]) -> void:
	var request: RollRequest = result.request
	if request.kind != RollRequest.Kind.INJURY:
		return
	var target: ModelState = state.get_model(request.target_id)
	if target == null or not target.on_table():
		return
	var band: Band = band_for(result.total)
	if band == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	var blood: int = band.blood
	var went_down: bool = false
	if band.down and not band.out_of_action:
		if target.down:
			blood += down_on_down_blood
			parts.append("already Down")
		else:
			went_down = true
	var before: int = target.marker_count(Markers.BLOOD)
	if blood > 0 and not band.out_of_action:
		target.set_markers(Markers.BLOOD, before + blood)
		var placed: int = target.marker_count(Markers.BLOOD) - before
		var text: String = "%d blood marker%s" % [placed, "" if placed == 1 else "s"]
		if placed < blood:
			text += " (at the cap of %d)" % Markers.CAP
		parts.insert(0, text)
	if band.out_of_action:
		parts.append("Out of Action")
	elif went_down:
		parts.append("goes Down")
	var summary: String = ", ".join(parts)
	events.append(GameEvent.new(GameEvent.Kind.INJURY_APPLIED, target.player, target.id, {
		"text": "Model %d: %s" % [target.id, summary], "short": summary.left(1).to_upper() + summary.substr(1),
		"blood": target.marker_count(Markers.BLOOD) - before, "down": went_down, "out_of_action": band.out_of_action,
	}))
	if band.out_of_action:
		TurnFlow.take_out_of_action(state, target, events)
	elif went_down:
		# Through the one Down step: the ledge roll first if there is a ledge
		# (not for the injury roll of a ledge roll's own fall).
		GoingDown.result(state, target, events, Callable(), not request.context.get(LedgeRoll.NO_LEDGE_ROLL, false))
