class_name ContactMode
extends InteractionMode
## The end of a charge that reaches with distance to spare (core waits for a
## CHARGE_CONTACT decision): the places it may end are an arc around the
## target's base. Hover to see who else would be charged, click to pick;
## Enter keeps first contact. main.gd opens this mode while the decision is
## pending and leaves it once it is answered.

## The contact position under the cursor, or -1.
var _hover: int = -1


static func is_pending(state: GameState) -> bool:
	return state.pending != null and state.pending.kind == PendingDecision.Kind.CHARGE_CONTACT


## The contact position under the cursor, or -1 (for scripted checks).
func hovered() -> int:
	return _hover


func shows_zones() -> bool:
	return true


func refresh() -> void:
	session.melee_view.show_contact_arc(session.state.pending.positions)


func exit() -> void:
	session.melee_view.clear_contact_arc()
	_set_hover(-1)


## Answers the contact choice: the charger ends at position `index`.
func choose(index: int) -> String:
	if not is_pending(session.state):
		return "No contact to choose."
	return session.send(ChooseContactCommand.new(session.state.pending.player, index))


func key(event: InputEventKey) -> bool:
	if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
		choose(session.state.pending.default_index)
		return true
	return false


func click(_screen_position: Vector2) -> bool:
	if _hover != -1:
		choose(_hover)
	else:
		session.message("Click a spot on the arc around the target (Enter keeps first contact).")
	return true


## The arc position nearest the cursor, the base it would have there, and
## the enemies it would count as charging.
func hover() -> bool:
	var selection: Selection = session.selection
	var decision: PendingDecision = session.state.pending
	var point: Variant = selection.hover_override
	if point == null:
		var mouse: Vector2 = selection.mouse()
		point = null if selection.over_ui(mouse) else selection.floor_point(mouse)
	var best: int = -1
	if point != null:
		var at: Vector3 = point
		var best_distance: float = 0.8
		for i: int in decision.positions.size():
			var d: float = Vector2(at.x, at.z).distance_to(Vector2(decision.positions[i].x, decision.positions[i].z))
			if d < best_distance:
				best_distance = d
				best = i
	_set_hover(best)
	return true


func _set_hover(index: int) -> void:
	if index == _hover:
		return
	_hover = index
	for view: ModelView in session.views.values():
		view.set_highlighted(false)
	var label: Label = session.distance_label
	if index == -1 or not is_pending(session.state):
		session.melee_view.show_contact_hover(null, 0.0)
		label.visible = false
		return
	var decision: PendingDecision = session.state.pending
	var model: ModelState = session.state.get_model(decision.model_id)
	session.melee_view.show_contact_hover(decision.positions[index], model.base_radius_inches())
	var charged: Array = decision.charged_ids[index]
	for id: int in charged:
		session.views[id].set_highlighted(true)
	label.text = "Ends here: charges %s%s" % [
		", ".join(charged.map(func(id: int) -> String: return "model %d" % id)),
		"  (first contact)" if index == decision.default_index else ""
	]
	label.position = session.camera.unproject_position(decision.positions[index]) + Vector2(18, -34)
	label.visible = true
