class_name CommandSender
extends RefCounted
## Sends commands to core and plays back the events it returns, in order:
## dice in the tray, models sliding, messages, the prompts of pending
## decisions. Also undo and redo, and what follows a restore. Never changes
## the state directly.

## The state changed (a command, undo or redo): game-side caches are gone.
signal state_changed
## A step was undone: the active mode is left and its previews dropped.
signal restored
## Core waits for a decision (after the event that raised it was played).
signal decision_needed(decision: PendingDecision)
## A model starts sliding along a path: the move preview is no longer valid.
signal slide_started

## Every event played, for logs and scripted checks.
var event_log: Array[GameEvent] = []

var _session: Session
## Events waiting to be played back, and whether one is playing (dice, a slide).
var _queue: Array[GameEvent] = []
var _playing: bool = false
## The free attacks of the retreat being played, as tray lines.
var _free_attack_lines: PackedStringArray = PackedStringArray()


func _init(session: Session) -> void:
	_session = session


## Runs a command and plays back its events. Returns "" or why it was rejected.
func send(command: Command) -> String:
	# Work on a worker reads the state: let it finish first.
	_session.jobs.wait_all()
	var result: CommandResult = _session.state.submit(command)
	if not result.ok():
		_session.message(Session.bad(result.error))
		_session.refresh_all()
		return result.error
	_state_changed()
	_session.message("")
	_queue.append_array(result.events)
	_pump()
	return ""


## Whether events are still being played back (input to the table waits).
func is_busy() -> bool:
	return _playing or not _queue.is_empty()


## Takes the last step back (not a rule command: core restores its snapshot).
## The views are brought back in line with the restored state.
func undo() -> String:
	var tray: DiceTray = _session.tray
	if tray.is_animating():
		tray.skip()
	if is_busy():
		return "Wait for the move to finish."
	_session.jobs.wait_all()
	if not _session.state.undo():
		_session.message("Nothing to undo.")
		return "Nothing to undo."
	_state_changed()
	_after_restore("Undone.")
	return ""


## Does the last undone step again; it plays back like any command.
func redo() -> String:
	var tray: DiceTray = _session.tray
	if tray.is_animating():
		tray.skip()
	if is_busy():
		return "Wait for the move to finish."
	_session.jobs.wait_all()
	if not _session.state.can_redo():
		_session.message("Nothing to redo.")
		return "Nothing to redo."
	var result: CommandResult = _session.state.redo()
	_state_changed()
	if not result.ok():
		_session.message(result.error)
		return result.error
	_session.message("Redone.")
	_queue.append_array(result.events)
	_pump()
	return ""


func _after_restore(message: String) -> void:
	_session.prompt.close()
	restored.emit()
	var tray: DiceTray = _session.tray
	tray.close()
	# A restored roll waiting on a marker prompt shows it again.
	var state: GameState = _session.state
	var pending: PendingDecision = state.pending
	if state.active_roll != null:
		tray.begin(state.active_roll)
		if pending != null and pending.kind == PendingDecision.Kind.ROLL_CHOICE:
			tray.ask_choice(pending)
	_session.message(message)
	_session.refresh_all()


## The state changed: game-side caches no longer hold, and the status line
## shows what core waits for now (even while events still play back).
func _state_changed() -> void:
	_session.caches.clear()
	state_changed.emit()
	_session.hud.refresh_status(_session.state)


func _pump() -> void:
	while not _playing and not _queue.is_empty():
		var event: GameEvent = _queue.pop_front()
		event_log.append(event)
		print("event: ", event.describe())
		_play(event)
	if not _playing and _queue.is_empty():
		_session.refresh_all()


func _resume() -> void:
	_playing = false
	_pump()


func _play(event: GameEvent) -> void:
	var hud: Hud = _session.hud
	var tray: DiceTray = _session.tray
	var views: Dictionary[int, ModelView] = _session.views
	match event.kind:
		GameEvent.Kind.TURN_STARTED:
			hud.show_message("Turn %d begins." % event.data["turn"])
		GameEvent.Kind.FIRST_PLAYER_CHOSEN:
			hud.show_message("%s activates first." % UiStyle.player_bb(event.player))
		GameEvent.Kind.ACTIVATION_STARTED:
			tray.close()
			if _session.selection.id != event.model_id:
				_session.select_model(event.model_id)
		GameEvent.Kind.MODEL_STOOD_UP:
			hud.show_message("Model %d stands up: half movement this activation." % event.model_id)
		GameEvent.Kind.ROLL_REQUESTED:
			tray.begin(event.roll)
		GameEvent.Kind.ROLL_CHOICE_MADE:
			tray.add_choice(event)
		GameEvent.Kind.DECISION_NEEDED:
			_on_decision(event.decision)
		GameEvent.Kind.ROLL_RESOLVED:
			_playing = true
			tray.show_result(event.result, _resume)
		GameEvent.Kind.MODEL_MOVED:
			_play_move(event)
		GameEvent.Kind.MODEL_FELL:
			_play_fall(event)
		GameEvent.Kind.MOVE_ROLL_POINT:
			hud.show_message("Model %d: %s" % [event.model_id, event.data.get("roll", "")])
		GameEvent.Kind.INJURY_APPLIED:
			tray.show_effect(String(event.data.get("short", "")))
			hud.show_message(String(event.data.get("text", "")))
		GameEvent.Kind.MODEL_WENT_DOWN:
			views[event.model_id].sync(_session.state.get_model(event.model_id))
		GameEvent.Kind.MODEL_OUT_OF_ACTION:
			views[event.model_id].visible = false
			if _session.selection.id == event.model_id:
				_session.deselect()
		GameEvent.Kind.MARKERS_GAINED:
			hud.show_message("Model %d: %s (+%d)" % [event.model_id, event.data.get("reason", ""), int(event.data.get("count", 0))])
		GameEvent.Kind.MOVE_STOPPED:
			hud.show_message("Model %d's move stops: %s." % [event.model_id, event.data.get("reason", "")])
		GameEvent.Kind.LEDGE_ROLL:
			tray.set_reason(String(event.data.get("reason", "")))
			hud.show_message(String(event.data.get("reason", "")))
		GameEvent.Kind.ACTIVATION_ENDED:
			var reason: String = event.data.get("reason", "")
			if reason in ["failed risky roll", "went Down", "taken Out of Action"]:
				tray.note_activation_ended()
				hud.show_message("Model %d %s: its activation ends." % [
					event.model_id, "failed a risky roll" if reason == "failed risky roll" else reason
				])
		GameEvent.Kind.OVERRIDE_APPLIED:
			hud.show_message("Override: %s" % event.data.get("text", ""))
		GameEvent.Kind.CHARGE_DECLARED:
			var text: String = "Model %d charges model %d" % [event.model_id, int(event.data["target_id"])]
			if event.data.get("interposed", false):
				text = "Model %d charges model %d (in the way of model %d)" % [
					event.model_id, int(event.data["target_id"]), int(event.data["declared_id"])
				]
			hud.show_message("%s: %s." % [text, event.data.get("label", "")])
		GameEvent.Kind.CHARGE_DISTANCE:
			var reaches: bool = event.data["reaches"]
			tray.show_effect("%s %.1f\" of %.1f\" needed" % [
				"Charge reaches:" if reaches else "Charge falls short:", float(event.data["distance"]), float(event.data["length"])
			])
		GameEvent.Kind.CHARGE_FAILED:
			var why: String = String(event.data.get("reason", ""))
			if why == "not far enough":
				tray.show_effect("Charge failed: %.1f\" of %.1f\"" % [float(event.data["distance"]), float(event.data["length"])])
				hud.show_message("Model %d's charge falls short; it stops outside every enemy's 1\" zone." % event.model_id)
			else:
				# A roll on the way (or going Down) stopped it: the roll in the tray failed the charge.
				tray.show_effect("charge failed")
				hud.show_message("Model %d's charge fails: %s." % [event.model_id, why])
		GameEvent.Kind.CHARGED:
			var charged: Array = event.data["charged"]
			hud.show_message("Model %d is in melee: charged %s." % [
				event.model_id, ", ".join(charged.map(func(id: int) -> String: return "model %d" % id))
			])
		GameEvent.Kind.RETREAT_STARTED:
			_free_attack_lines.clear()
			hud.show_message("Model %d retreats." % event.model_id)
		GameEvent.Kind.FREE_ATTACK:
			_free_attack_lines.append("Model %d makes a free melee attack against model %d." % [
				event.model_id, int(event.data["target_id"])
			])
			var lines: PackedStringArray = _free_attack_lines.duplicate()
			if event.data.get("temporary", false):
				lines.append("[color=#%s](Temporary: attacks are not in the game yet.)[/color]" % UiStyle.DIM_COLOUR.to_html(false))
			tray.show_notes("Free attacks", lines)
			_playing = true
			tray.get_tree().create_timer(0.7).timeout.connect(_resume)
		GameEvent.Kind.PLAYER_TO_ACT:
			pass


func _on_decision(decision: PendingDecision) -> void:
	match decision.kind:
		PendingDecision.Kind.ROLL_CHOICE:
			_session.tray.ask_choice(decision)
		PendingDecision.Kind.MOVE:
			if _session.selection.id != decision.model_id:
				_session.select_model(decision.model_id)
		PendingDecision.Kind.CHARGE_CONTACT:
			if _session.selection.id != decision.model_id:
				_session.select_model(decision.model_id)
			_session.message("Click a spot on the arc to end the charge there (Enter keeps first contact).")
	decision_needed.emit(decision)


func _play_move(event: GameEvent) -> void:
	var raw: Array = event.data["path"]
	var path: Array[Vector3] = []
	for point: Vector3 in raw:
		path.append(point)
	var shown: Array[Vector3] = ModelView.shown_path(path, event.data.get("kinds", []))
	slide_started.emit()
	_playing = true
	var end: Vector3 = path[path.size() - 1]
	var view: ModelView = _session.views[event.model_id]
	view.slide_along(shown, func() -> void:
		view.place_at(end)
		_resume()
	)


## A failed jump: up the arc to over the gap, straight down, and over to
## where it can stop.
func _play_fall(event: GameEvent) -> void:
	var from: Vector3 = event.data["from"]
	var over: Vector3 = event.data["over"]
	var to: Vector3 = event.data["to"]
	var shown: Array[Vector3] = [from]
	var far: Vector3 = from + (over - from) * 2.0
	shown.append_array(ModelView.jump_arc(from, far, true))
	shown.append(Vector3(over.x, to.y, over.z))
	shown.append(to)
	var cause: String = String(event.data.get("reason", ""))
	_session.message("Model %d falls %.1f\"%s." % [event.model_id, float(event.data["height"]), " (%s)" % cause if cause != "" else ""])
	slide_started.emit()
	_playing = true
	var view: ModelView = _session.views[event.model_id]
	view.slide_along(shown, func() -> void:
		view.place_at(to)
		_resume()
	)
