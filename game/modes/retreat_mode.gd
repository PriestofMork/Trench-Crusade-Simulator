class_name RetreatMode
extends InteractionMode
## Retreat (R or the Retreat button), in melee: lists the free attacks and
## asks for confirmation; once confirmed they are played, the enemy player
## picking their order if there are several (FREE_ATTACK_ORDER, the HUD's
## attacker buttons, which work whichever mode is active), then the move
## (in Move mode). Hover and clicks on the table are left to Move.

## FREE_ATTACK_ORDER: the attackers picked so far, in order.
var _attack_order: Array[int] = []


func _init(p_session: Session) -> void:
	super(p_session)
	session.sender.state_changed.connect(func() -> void: _attack_order.clear())
	session.sender.decision_needed.connect(func(decision: PendingDecision) -> void:
		if decision.kind == PendingDecision.Kind.FREE_ATTACK_ORDER:
			_attack_order.clear()
	)


func attack_order() -> Array[int]:
	return _attack_order


func enter_error() -> String:
	if session.is_busy():
		return "Wait for the move to finish."
	var error: String = session.action_error(&"retreat")
	if error != "":
		session.message(Session.bad("Retreat: %s" % error))
	return error


func enter() -> void:
	var state: GameState = session.state
	var model: ModelState = session.selection.model()
	var enemies: Array[int] = MeleeZone.enemy_ids_within(state, model)
	var names: PackedStringArray = PackedStringArray()
	for id: int in enemies:
		names.append("model %d" % id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Retreat model %d?[/b]" % model.id)
	lines.append("Free attacks first: %s%s." % [
		", ".join(names), " (%s picks the order)" % UiStyle.player_bb(1 - model.player) if enemies.size() > 1 else ""
	])
	lines.append("Then it moves up to %.1f\" and must end more than 1\" from every enemy." % TurnFlow.movement_budget(state, model))
	session.prompt.ask(&"retreat", "\n".join(lines), confirm, _cancel)


func exit() -> void:
	if session.prompt.kind == &"retreat":
		session.prompt.close()


func confirm() -> String:
	session.prompt.close()
	var model: ModelState = session.selection.model()
	session.leave_mode()
	if model == null:
		return "No model selected."
	return session.send(BeginActionCommand.new(model.player, model.id, &"retreat"))


func _cancel() -> void:
	session.prompt.close()
	session.message("Retreat cancelled.")
	session.leave_mode()


## FREE_ATTACK_ORDER: the enemy player picks the next attacker; once every
## attacker is picked the order is sent.
func pick_attacker(attacker_id: int) -> String:
	var pending: PendingDecision = session.state.pending
	if pending == null or pending.kind != PendingDecision.Kind.FREE_ATTACK_ORDER:
		return "No order to pick."
	if _attack_order.has(attacker_id) or not pending.model_ids.has(attacker_id):
		return "Not an attacker left to pick."
	_attack_order.append(attacker_id)
	if _attack_order.size() < pending.model_ids.size():
		session.refresh_all()
		return ""
	var order: Array[int] = _attack_order.duplicate()
	_attack_order.clear()
	return session.send(ChooseAttackOrderCommand.new(pending.player, order))
