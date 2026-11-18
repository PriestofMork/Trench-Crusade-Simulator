class_name ChargeMode
extends InteractionMode
## Charge mode (briefs 007, 008b, 008c): on while the selected model picks a
## target (G or the Charge button). Opening it only runs the declaration
## check: every enemy in range is labelled "can charge" or why not. Hovering
## one only highlights it; clicking it works out its route alone, on a worker
## thread (the label says "…" until it is ready); core keeps it
## (GameState.charge_routes()), so clicking the same target again, or
## declaring it, searches nothing. The route is drawn, its risky parts
## orange, and the confirmation panel asks; once confirmed the D6 rolls and
## the charger moves. J (or the button) switches "allow climbs and jumps", C
## the descent mode. Esc leaves.

## The orange of risky routes, for rich text.
const GHOST_RISKY_HTML: String = "ff9933"
const JOB: StringName = &"charge"

## How long opening charge mode took (the declaration check), and the last
## route worked out (on the worker), ms.
var build_ms: float = 0.0
var route_ms: float = 0.0

## Enemy in range -> "" if it can be declared, else why not.
var _declarations: Dictionary[int, String] = {}
## "Allow climbs and jumps" (ruling 2 of brief 008b): off by default.
var _rolls: bool = false
## The selected target (the one whose route is shown and asked to
## confirm), or -1; its plan for the current route choice, null while it is
## being worked out.
var _target: int = -1
var _plan: ChargePlan = null
## The enemy highlighted under the cursor, or -1.
var _hover: int = -1


## Whether charge mode is open and no route is being worked out.
func is_ready() -> bool:
	return active and not session.jobs.is_running(JOB)


## Enemy in range -> "" if it can be declared, else why not.
func declarations() -> Dictionary[int, String]:
	return _declarations


## The selected target, or -1.
func target() -> int:
	return _target


## The selected target's plan for the current route choice, or null (none
## selected, or still being worked out).
func plan() -> ChargePlan:
	return _plan


## The text of the charge label over `id`, or "" if it has none.
func label_text(id: int) -> String:
	return session.melee_view.charge_label_text(id)


func is_rolls() -> bool:
	return _rolls


## The enemy highlighted under the cursor, or -1.
func hovered() -> int:
	return _hover


func shows_zones() -> bool:
	return true


func shows_sight() -> bool:
	return false


func enter_error() -> String:
	if session.is_busy():
		return "Wait for the move to finish."
	var error: String = session.action_error(&"charge")
	if error != "":
		session.message(Session.bad("Charge: %s" % error))
	return error


## The declaration check for every enemy in range (ruling 1 of brief 008c),
## then labels. No route yet.
func enter() -> void:
	var id: int = session.selection.id
	_rolls = false
	_target = -1
	_plan = null
	var started: int = Time.get_ticks_usec()
	_declarations = ChargePlanner.new(session.state, id, session.selection.descent_mode()).declarations()
	build_ms = (Time.get_ticks_usec() - started) / 1000.0
	print("Charge mode for model %d: %.1f ms (declaration check, %d enemies in range)" % [id, build_ms, _declarations.size()])
	_show_labels()
	var unseen: int = 0
	for enemy: int in _declarations:
		if _declarations[enemy] != "":
			unseen += 1
	session.message("Charge mode: %d enemies in range, %d not visible. Click one to see its route. J: climbs and jumps. Esc leaves." % [
		_declarations.size(), unseen
	])
	session.refresh_all()


func exit() -> void:
	session.jobs.wait(JOB)
	_declarations = {}
	_target = -1
	_plan = null
	_set_hover(-1)
	if session.prompt.kind == &"charge":
		session.prompt.close()
	session.melee_view.clear_charge_labels()
	session.preview.hide_all()
	session.distance_label.visible = false
	session.message("")


func key(event: InputEventKey) -> bool:
	if event.physical_keycode == KEY_ESCAPE:
		session.leave_mode()
		return true
	if event.physical_keycode == KEY_J and not event.ctrl_pressed:
		toggle_rolls()
		return true
	return false


## Clicking an enemy selects it (if it can be declared) and works out its
## route; clicking another friendly model or the table leaves charge mode.
func click(screen_position: Vector2) -> bool:
	var state: GameState = session.state
	var selected: int = session.selection.id
	var picked: int = session.selection.pick_model(screen_position)
	if picked != -1 and state.get_model(picked).player != state.get_model(selected).player:
		request(picked)
	elif picked == selected:
		pass
	else:
		session.leave_mode()
		if picked != -1:
			session.select_model(picked)
	return true


## Switches "allow climbs and jumps" (J). With a target selected, its route
## for the other choice is worked out (once; core keeps both).
func toggle_rolls() -> String:
	if not active:
		return "Not in charge mode."
	_rolls = not _rolls
	session.message("Charge routes: climbs and jumps %s." % ("allowed (the shortest route of any kind)" if _rolls else "not allowed (the shortest route with no roll)"))
	if _target != -1:
		_start_route()
	session.refresh_all()
	return ""


## The selected route depends on the descent mode: work it out for the new one.
func descent_changed() -> void:
	if _target != -1:
		_start_route()


## The labels of charge mode (ruling 6 of brief 008c): every enemy in range
## says whether it can be declared; the selected one what its route needs.
func _show_labels() -> void:
	session.melee_view.show_charge_declarations(session.state, _declarations, _target, _plan)


## Works out the selected target's route for the current route choice: at
## once if core already has it, else on a worker thread (the label says "…"
## until it is ready). A route already being worked out finishes first.
func _start_route() -> void:
	if session.prompt.kind == &"charge":
		session.prompt.close()
	_plan = null
	var state: GameState = session.state
	var id: int = session.selection.id
	var mode: Transitions.DescentMode = session.selection.descent_mode()
	var planner: ChargePlanner = ChargePlanner.new(state, id, mode)
	if planner.is_planned(_target, _rolls):
		_show_plan(planner.plan(_target, _rolls))
		return
	_show_labels()
	session.preview.hide_all()
	if session.jobs.is_running(JOB):
		return
	# The height field and the sight terrain are shared; build them here so
	# the worker only reads them.
	state.height_field()
	state.sight_terrain()
	session.jobs.start(JOB, _route_key(), _plan_route.bind(id, _target, _rolls, mode), _on_route_done)
	session.message("Charge mode: working out the route to model %d…" % _target)


func _route_key() -> String:
	return "%d:%s:%d" % [_target, str(_rolls), session.selection.descent_mode()]


## On a worker thread: only reads the state, which cannot change while it
## runs (sending a command, undo and redo wait for it). The plan is kept by
## core's cache, where the main thread then finds it.
func _plan_route(charger_id: int, target_id: int, allow_rolls: bool, mode: Transitions.DescentMode) -> void:
	ChargePlanner.new(session.state, charger_id, mode).plan(target_id, allow_rolls)


func _on_route_done(job: BackgroundJobs.Job) -> void:
	route_ms = job.ms()
	var id: int = session.selection.id
	print("Charge route for model %d -> %s: %.0f ms on a worker" % [id, job.key, route_ms])
	if not active or _target == -1:
		return
	if job.key != _route_key():
		# The selection or the route choice changed meanwhile.
		_start_route()
		return
	_show_plan(ChargePlanner.new(session.state, id, session.selection.descent_mode()).plan(_target, _rolls))


## Clicking an enemy selects it (if it can be declared) and works out its
## route; the charge is then confirmed or cancelled.
func request(target_id: int) -> String:
	if not active:
		return "Not in charge mode."
	if not _declarations.has(target_id):
		session.message("Model %d cannot be charged: it is not an enemy within 12\" ." % target_id)
		return "Not a target."
	var error: String = _declarations[target_id]
	if error != "":
		session.message(Session.bad(error))
		return error
	_target = target_id
	_start_route()
	session.refresh_all()
	return ""


## The selected target's route is ready: its label, the route drawn, and
## the confirmation panel.
func _show_plan(p_plan: ChargePlan) -> void:
	_plan = p_plan
	_show_labels()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Charge model %d?[/b]" % p_plan.declared_id)
	if p_plan.interposed():
		lines.append("[color=#%s]Model %d is in the way: the charge is against model %d instead.[/color]" % [
			UiStyle.GOLD_COLOUR.to_html(false), p_plan.interposers[0], p_plan.target_id
		])
	var model: ModelState = session.selection.model()
	if p_plan.path.is_empty():
		lines.append("No route: the charger cannot move anywhere (%s)." % p_plan.label())
	else:
		var to: String = "to base contact" if p_plan.contact else "to the closest place it can stop (no base contact)"
		lines.append("%.1f\" %s; Movement %s\" + D6 (%s)." % [p_plan.length, to, str(model.movement), p_plan.label()])
	if not p_plan.rolls.is_empty():
		var labels: PackedStringArray = PackedStringArray()
		for roll: Dictionary in p_plan.rolls:
			labels.append(String(roll["label"]))
		lines.append("[color=#%s]Rolls on the way: %s. A failed roll fails the charge.[/color]" % [
			GHOST_RISKY_HTML, "  -  ".join(labels)
		])
	if not p_plan.reachable():
		lines.append("[color=#%s]No D6 result reaches: it moves as far as it can and stops outside every enemy's 1\" zone.[/color]" % UiStyle.BAD_COLOUR.to_html(false))
	lines.append("Climbs and jumps %s. The D6 is rolled once it is declared; the declaration stands whatever the roll." % ("allowed" if _rolls else "not allowed"))
	session.prompt.ask(&"charge", "\n".join(lines), confirm, _cancel)
	session.message("Charge model %d: %s. Confirm or Cancel; another enemy to pick it instead." % [p_plan.declared_id, MeleeView.charge_text(p_plan)])


## Declares the charge waiting for confirmation: the D6 rolls in the tray.
## Core finds the route it was shown in its cache (ruling 7 of 008c).
func confirm() -> String:
	if _target == -1 or _plan == null:
		return "No charge to confirm."
	var model: ModelState = session.selection.model()
	var target_id: int = _target
	var rolls: bool = _rolls
	session.prompt.close()
	session.leave_mode()
	return session.send(BeginActionCommand.new(model.player, model.id, &"charge", target_id, rolls, session.selection.descent_mode()))


func _cancel() -> void:
	session.prompt.close()
	_target = -1
	_plan = null
	_show_labels()
	session.preview.hide_all()
	session.message("Charge not declared. Pick another target, or Esc to leave charge mode.")


## The enemy under the cursor (or the scripted hover point) is only
## highlighted; nothing is worked out for it (ruling 2 of brief 008c). The
## selected target's route is drawn once it is ready, with what it needs.
func hover() -> bool:
	var selection: Selection = session.selection
	var hovered_id: int = -1
	if selection.hover_override != null:
		hovered_id = selection.model_near(selection.hover_override)
	else:
		var mouse: Vector2 = selection.mouse()
		if not selection.over_ui(mouse):
			hovered_id = selection.pick_model(mouse)
	if hovered_id != -1 and not _declarations.has(hovered_id):
		hovered_id = -1
	_set_hover(hovered_id)
	var preview: PathPreview = session.preview
	var label: Label = session.distance_label
	var shown_plan: ChargePlan = _plan
	if _target == -1:
		preview.hide_all()
		label.visible = false
		return true
	var model: ModelState = selection.model()
	if shown_plan == null:
		preview.hide_all()
		label.text = "Charge model %d: working out the route…" % _target
	elif shown_plan.path.is_empty():
		preview.hide_all()
		label.text = "Model %d: %s" % [_target, shown_plan.label()]
	else:
		var drawn: Array = _display_path(model, shown_plan)
		var shown: Array[Vector3] = drawn[0]
		shown.remove_at(0)
		var risky_parts: Array[bool] = drawn[1]
		preview.show_preview(
			model.position, shown, shown_plan.end(), model.base_radius_inches(), Vector3.UP, not shown_plan.rolls.is_empty(),
			risky_parts, not shown_plan.reachable()
		)
		var roll_points: Array[Vector3] = []
		for roll: Dictionary in shown_plan.rolls:
			roll_points.append(roll["at"])
		preview.show_roll_points(roll_points)
		var text: String = "Charge model %d: %.1f\" - %s" % [_target, shown_plan.length, shown_plan.label()]
		if shown_plan.interposed():
			text = "Model %d is in the way of model %d: charges it instead\n%.1f\" - %s" % [shown_plan.interposers[0], _target, shown_plan.length, shown_plan.label()]
		label.text = text
	label.position = session.camera.unproject_position(session.state.get_model(_target).position) + Vector2(18, -60)
	label.visible = true
	return true


## Highlights the enemy under the cursor (-1: none).
func _set_hover(id: int) -> void:
	if id == _hover:
		return
	var views: Dictionary[int, ModelView] = session.views
	if _hover != -1 and views.has(_hover):
		views[_hover].set_highlighted(false)
	_hover = id
	if id != -1 and views.has(id):
		views[id].set_highlighted(true)


## A charge route as drawn: climbs straight up and down (see
## ModelView.shown_path()), and which drawn parts need a roll: [points,
## Array[bool] per drawn segment].
func _display_path(model: ModelState, p_plan: ChargePlan) -> Array:
	var legality: MoveLegality = ChargePlanner.legality_for(session.state, model, p_plan.allow_rolls, p_plan.descent_mode)
	var shown: Array[Vector3] = [model.position]
	var risky: Array[bool] = []
	var previous: Vector3 = model.position
	for point: Vector3 in p_plan.path:
		legality.segment_cost(previous, point)
		var part: Array[Vector3] = ModelView.shown_path([previous, point] as Array[Vector3], [legality.last_kind])
		var needs_roll: bool = Transitions.needs_roll(legality.last_kind)
		for i: int in range(1, part.size()):
			shown.append(part[i])
			risky.append(needs_roll)
		previous = point
	return [shown, risky]
