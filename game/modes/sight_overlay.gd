class_name SightOverlay
extends RefCounted
## Brief 008, a helper the modes use rather than a mode: the sight line to
## the enemy under the cursor (Move), the overview (V: marks what the
## selected model sees, dims the rest) and the debug cylinders (L). Sight
## answers come from core and are kept in the session's caches until the
## state changes; never worked out by a view.

const CACHE: StringName = &"sight"

var _session: Session
## The overview (V) and the debug view (L).
var _overview: bool = false
var _debug: bool = false
## The enemy under the cursor while a model is selected, or -1.
var _hover: int = -1
## Whether the active mode shows sight (charge mode does not), as of the last refresh.
var _shown: bool = true


func _init(session: Session) -> void:
	_session = session


## Whether `viewer_id` can see `target_id` now, with the clear segment: from
## core, kept until the state changes.
func sight(viewer_id: int, target_id: int) -> SightResult:
	var key: String = "%d>%d" % [viewer_id, target_id]
	var cached: SightResult = _session.caches.lookup(CACHE, key)
	if cached != null:
		return cached
	var state: GameState = _session.state
	var result: SightResult = state.rules.sight.check(state, state.get_model(viewer_id), state.get_model(target_id))
	_session.caches.store(CACHE, key, result)
	return result


func is_overview() -> bool:
	return _overview


func is_debug() -> bool:
	return _debug


func toggle_overview() -> void:
	_overview = not _overview
	_session.message("Sight overview %s." % ("on: green rings mark the enemies the selected model can see" if _overview else "off"))
	_session.refresh_all()


func toggle_debug() -> void:
	_debug = not _debug
	_session.refresh_all()


## The enemy whose sight is shown on hover, or -1 (for scripted checks).
func hovered() -> int:
	return _hover


func view() -> SightView:
	return _session.sight_view


## Drops the hover line (the selection is gone).
func clear_hover() -> void:
	_hover = -1
	_session.sight_view.hide_line()


## The enemies of `viewer` on the table that it can and cannot see.
func _enemies_by_sight(viewer: ModelState) -> Array:
	var seen: Array[int] = []
	var unseen: Array[int] = []
	for model: ModelState in _session.state.models_on_table():
		if model.player == viewer.player:
			continue
		if sight(viewer.id, model.id).visible:
			seen.append(model.id)
		else:
			unseen.append(model.id)
	return [seen, unseen]


## The overview's hidden enemies of the selected model (empty when it is off).
func _overview_unseen() -> Array[int]:
	var selected: ModelState = _session.selection.model()
	if not _overview or selected == null or not selected.on_table() or not _shown:
		return [] as Array[int]
	return _enemies_by_sight(selected)[1]


## The overview marks, the dimming and the debug cylinders, from the state.
## `shown`: whether the active mode shows sight.
func refresh(shown: bool) -> void:
	_shown = shown
	var state: GameState = _session.state
	var sight_view: SightView = _session.sight_view
	var selected: ModelState = _session.selection.model()
	var seen: Array[int] = []
	var unseen: Array[int] = []
	if _overview and selected != null and selected.on_table() and _shown:
		var split: Array = _enemies_by_sight(selected)
		seen = split[0]
		unseen = split[1]
	for id: int in _session.views:
		_session.views[id].set_dimmed(unseen.has(id))
	sight_view.show_seen(state, seen)
	_show_not_visible_labels(unseen)
	if _debug:
		var cylinders: Array[SightCylinder] = []
		for model: ModelState in state.models_on_table():
			cylinders.append(SightCylinder.for_model(state, model))
		sight_view.show_cylinders(cylinders)
	else:
		sight_view.hide_cylinders()


## "not visible" over the overview's hidden enemies plus the hovered one.
func _show_not_visible_labels(unseen: Array[int]) -> void:
	var ids: Array[int] = unseen.duplicate()
	var selected_id: int = _session.selection.id
	if _hover != -1 and selected_id != -1 and _shown and not ids.has(_hover) and not sight(selected_id, _hover).visible:
		ids.append(_hover)
	_session.sight_view.show_not_visible(_session.state, ids)


## With a model selected, hovering an enemy shows the sight line to it or
## marks it not visible. `allowed`: whether hovering looks at models now (no
## pinned move, no scripted hover). Returns whether an enemy is hovered (the
## move preview then stays hidden).
func update_hover(allowed: bool) -> bool:
	var state: GameState = _session.state
	var selection: Selection = _session.selection
	var selected: ModelState = selection.model()
	var target: int = -1
	if allowed and selected != null and selected.on_table():
		var mouse: Vector2 = selection.mouse()
		if not selection.over_ui(mouse):
			var picked: int = selection.pick_model(mouse)
			if picked != -1 and state.get_model(picked).player != selected.player:
				target = picked
	if target != _hover:
		_hover = target
		_show_not_visible_labels(_overview_unseen())
	if target == -1:
		_session.sight_view.hide_line()
		return false
	_session.preview.hide_all()
	var result: SightResult = sight(selection.id, target)
	var label: Label = _session.distance_label
	if result.visible:
		_session.sight_view.show_line(result.from, result.to)
		label.text = "Model %d: visible" % target
	else:
		_session.sight_view.hide_line()
		label.text = "Model %d: not visible" % target
	label.position = _session.camera.unproject_position(state.get_model(target).position) + Vector2(18, -60)
	label.visible = true
	return true
