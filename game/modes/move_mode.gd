class_name MoveMode
extends InteractionMode
## The default mode: select a model to preview it (its panel, and where Move
## would take it), and move it. The movement indicator is drawn from the
## selected model's reach field, built on a worker thread and kept in the
## session's caches. Left click inside the blue area: take the Move action
## there (or make the move a Dash granted); a move may be made in several
## clicks while it has distance left. Left click inside the orange area (only
## with rolls): the route and its rolls are pinned and wait for Confirm (or
## Enter); Escape cancels. Hovering an enemy shows the sight line to it.

## The action a click on the table takes.
const CLICK_ACTION: StringName = &"move"
const JOB: StringName = &"reach"
const CACHE: StringName = &"reach"

var _reach: ReachField
var _reach_key: String = ""
## An orange destination waiting for confirmation (ruling 7 of brief 006), or null.
var _pinned: Variant = null


func _init(p_session: Session) -> void:
	super(p_session)
	session.sender.slide_started.connect(_clear_reach)


func enter() -> void:
	_clear_reach()


func exit() -> void:
	_clear_reach()


func refresh() -> void:
	_refresh_reach()


func shows_zones() -> bool:
	return _reach_key != ""


## Whether the selected model's reach field is ready (it is built in the background).
func is_reach_ready() -> bool:
	var id: int = session.selection.id
	return id != -1 and _reach != null and _reach.model_id == id and not session.jobs.is_running(JOB)


## Whether the selected model shows a movement indicator.
func has_move_preview() -> bool:
	return _reach_key != ""


## Where a click on `point` (on a floor) would send the selected model, or null.
func destination_for(point: Vector3) -> Variant:
	return _destination_for(point)


## What a click on a destination does: a blue one moves at once; an orange
## one (only with rolls) is pinned with its route and rolls and waits for
## confirm_pinned() (ruling 7). Returns "" or why not.
func request_move_to(point: Vector3) -> String:
	if session.selection.id == -1 or _reach == null or session.is_busy():
		return "No model selected."
	if not _reach.is_reachable(point):
		return "Out of reach."
	if _reach.needs_rolls(point):
		_pin(point)
		return ""
	_unpin()
	return move_selected_to(point)


## The pinned orange destination, or null.
func pinned_destination() -> Variant:
	return _pinned


## Makes the pinned move.
func confirm_pinned() -> String:
	if _pinned == null:
		return "Nothing to confirm."
	var point: Vector3 = _pinned
	_unpin()
	return move_selected_to(point)


func cancel_pinned() -> void:
	_unpin()
	session.message("Move cancelled.")


func _pin(point: Vector3) -> void:
	_pinned = point
	var labels: PackedStringArray = PackedStringArray()
	for roll: Dictionary in _reach.rolls_to(point):
		labels.append(String(roll["label"]))
	session.prompt.ask(&"move", "[b]This move needs rolls[/b]\n%s\n%.1f\" of %.1f\"" % [
		"  -  ".join(labels), _reach.cost_to(point), _reach.budget
	], confirm_pinned, cancel_pinned)


func _unpin() -> void:
	_pinned = null
	if session.prompt.kind == &"move":
		session.prompt.close()


## Moves the selected model to `point` along the reach field's path: answers
## a pending move, or takes the Move action first. Orange destinations move
## without asking here (request_move_to() asks). Returns "" or why not.
func move_selected_to(point: Vector3) -> String:
	var id: int = session.selection.id
	if id == -1 or _reach == null or session.is_busy():
		return "No model selected."
	var path: Array[Vector3] = _reach.path_to(point)
	if path.is_empty():
		return "Out of reach."
	var state: GameState = session.state
	var model: ModelState = state.get_model(id)
	if not _move_pending_for(id):
		var error: String = session.send(BeginActionCommand.new(model.player, model.id, CLICK_ACTION))
		if error != "":
			return error
	return session.send(MoveCommand.new(state.pending.player, model.id, path, _reach.descent_mode))


func _move_pending_for(id: int) -> bool:
	var pending: PendingDecision = session.state.pending
	return pending != null and pending.kind == PendingDecision.Kind.MOVE and pending.model_id == id


## How far the selected model could move now: the pending move's budget, or
## what the Move action would give if it may take it, else -1.
func _move_budget(id: int) -> float:
	var state: GameState = session.state
	var model: ModelState = state.get_model(id)
	if model == null:
		return -1.0
	if _move_pending_for(id):
		return state.pending.budget
	if TurnFlow.activation_error(state, model.player, model) != "":
		return -1.0
	if BeginActionCommand.unavailable_reason(state, model, CLICK_ACTION) != "":
		return -1.0
	return state.rules.action(CLICK_ACTION).behaviour.move_budget_preview(state, model)


func _refresh_reach() -> void:
	var id: int = session.selection.id
	var budget: float = _move_budget(id) if id != -1 else -1.0
	if budget < 0.0:
		_clear_reach()
		return
	var state: GameState = session.state
	var model: ModelState = state.get_model(id)
	var mode: Transitions.DescentMode = session.selection.descent_mode()
	var zones: EnemyZones = state.pending.zones if _move_pending_for(id) else null
	var key: String = "%d|%.3f|%s|%d|%s" % [id, budget, str(model.position), mode, zones.describe() if zones != null else ""]
	if key == _reach_key:
		return
	_clear_reach()
	_reach_key = key
	if session.caches.has(CACHE, key):
		var cached: Array = session.caches.lookup(CACHE, key)
		_reach = cached[0]
		session.indicator.mesh = cached[2]
		print("Reach field for model %d (%.1f\", %s): from the cache" % [id, budget, Selection.descent_name(mode)])
		return
	# A stale build is waited for and dropped by start().
	# The height field is shared; build it here so the worker only reads it.
	state.height_field()
	session.jobs.start(JOB, key, _build_reach.bind(id, budget, mode, zones), _on_reach_built, func() -> String: return _reach_key)


func _clear_reach() -> void:
	_unpin()
	_reach = null
	_reach_key = ""
	session.indicator.show_field(null)
	session.preview.hide_all()
	session.distance_label.visible = false


## On a worker thread: only reads positions and terrain, which do not change
## while a field is being built (sending a command waits for it).
func _build_reach(id: int, budget: float, mode: Transitions.DescentMode, zones: EnemyZones = null) -> Array:
	var field: ReachField = ReachField.new(session.state, id, budget, ReachField.CELL_SIZE, mode, zones)
	var layers: Array[ReachField.Layer] = field.contour_layers()
	return [field, layers]


func _on_reach_built(job: BackgroundJobs.Job) -> void:
	var built: Array = job.result
	var field: ReachField = built[0]
	var layers: Array[ReachField.Layer] = built[1]
	var computed: int = Time.get_ticks_usec()
	_reach = field
	session.indicator.show_field(field, layers)
	session.caches.store(CACHE, _reach_key, [field, layers, session.indicator.mesh])
	print("Reach field for model %d (%.1f\", %s): %d states, %.1f ms on a worker, indicator mesh %.1f ms" % [
		field.model_id, field.budget, Selection.descent_name(field.descent_mode), field.state_count(),
		(computed - job.started_usec) / 1000.0, (Time.get_ticks_usec() - computed) / 1000.0
	])


func click(screen_position: Vector2) -> bool:
	var selection: Selection = session.selection
	var picked: int = selection.pick_model(screen_position)
	if picked != -1:
		session.select_model(picked)
		return true
	if selection.id == -1:
		return true
	if _reach == null:
		session.deselect()
		return true
	var destination: Variant = _destination_for(selection.floor_point(screen_position))
	if destination != null:
		request_move_to(destination)
	elif _pinned != null:
		cancel_pinned()
	else:
		session.deselect()
	return true


func hover() -> bool:
	var selection: Selection = session.selection
	if session.sight.update_hover(_pinned == null and selection.hover_override == null):
		return true
	if _reach == null:
		return true
	var preview: PathPreview = session.preview
	var label: Label = session.distance_label
	var point: Variant = selection.hover_override
	if _pinned != null:
		point = _pinned
	elif point == null:
		var mouse: Vector2 = selection.mouse()
		if selection.pick_model(mouse) != -1 or selection.over_ui(mouse):
			preview.hide_all()
			label.visible = false
			return true
		point = selection.floor_point(mouse)
	if point == null:
		preview.hide_all()
		label.visible = false
		return true
	var target: Vector3 = point
	var model: ModelState = selection.model()
	var path: Array[Vector3] = []
	var destination: Variant = _destination_for(point)
	if destination != null:
		target = destination
		path = _reach.path_to(target)
	var shown: Array[Vector3] = []
	var rolls: Array[Dictionary] = []
	if not path.is_empty():
		shown = _display_path(model.position, path)
		shown.remove_at(0)
		rolls = _reach.rolls_to(target)
	preview.show_preview(
		model.position, shown, target, model.base_radius_inches(), _floor_normal(target), not rolls.is_empty()
	)
	var roll_points: Array[Vector3] = []
	var labels: PackedStringArray = PackedStringArray()
	for roll: Dictionary in rolls:
		roll_points.append(roll["at"])
		labels.append(String(roll["label"]))
	preview.show_roll_points(roll_points)
	if path.is_empty():
		label.visible = false
		return true
	var cost: float = _reach.cost_to(target)
	var surcharge: float = _reach.surcharge_at(target)
	label.text = "%.1f\" of %.1f\"" % [cost, _reach.budget]
	if surcharge > 0.0:
		label.text += "  (incl. %.1f\" to stop on the obstacle)" % surcharge
	if not labels.is_empty():
		label.text = "  -  ".join(labels) + "\n" + label.text
		if _pinned == null:
			label.text += "   (click to confirm)"
	label.position = session.camera.unproject_position(target) + Vector2(18, -34)
	label.visible = true
	return true


## The path as it is drawn in the preview: see ModelView.shown_path(), with
## the kinds of its segments from the reach field.
func _display_path(start: Vector3, path: Array[Vector3]) -> Array[Vector3]:
	var points: Array[Vector3] = [start]
	points.append_array(path)
	var kinds: Array = []
	for i: int in range(1, points.size()):
		kinds.append(_reach.segment_kind(points[i - 1], points[i]))
	return ModelView.shown_path(points, kinds)


## Up direction of the floor a destination is on: the tilt core gives a
## model standing there (SightCylinder.tilt_at()).
func _floor_normal(point: Vector3) -> Vector3:
	return SightCylinder.tilt_at(session.state, point)


## Where the selected model's centre goes for a point on a floor: the closest
## valid centre within a base radius, since the indicator shows where the base
## edge can reach. Null if there is none (or `point` is null).
func _destination_for(point: Variant) -> Variant:
	if point == null or _reach == null:
		return null
	return _reach.closest_destination(point, _reach.base_radius())
