class_name RetreatBehaviour
extends ActionBehaviour
## Retreat (docs/rules/movement.md, "Melee and Retreat"; ruling 10 of brief
## 007): a move action, only in melee (ActionDef.melee).
##
## 1. Every enemy within 1" makes a free melee attack against the model,
##    through GameState.rules.free_attack, in an order the enemy player
##    chooses when there is more than one (a FREE_ATTACK_ORDER decision,
##    answered by ChooseAttackOrderCommand).
## 2. Then, if the model is still standing, it moves like a normal Move (in
##    steps, the same budget), with the zones of those enemies open for
##    passing: it must end outside every enemy's 1" zone and may not come
##    within 1" of any other enemy (EnemyZones.retreat()).
## If an attack puts the model Down or out of action, the activation ends
## once the attacks are over (TurnFlow.end_activation_when_done()).


func begin(state: GameState, model: ModelState, action: ActionDef, events: Array[GameEvent], _plan: ActionPlan = null) -> void:
	var retreat: RetreatResolution = RetreatResolution.new()
	retreat.model_id = model.id
	retreat.player = model.player
	retreat.action_id = action.id
	retreat.enemies = MeleeZone.enemy_ids_within(state, model)
	state.resolution = retreat
	events.append(GameEvent.new(GameEvent.Kind.RETREAT_STARTED, model.player, model.id, {
		"enemies": retreat.enemies.duplicate(),
	}))
	if retreat.enemies.size() > 1:
		var decision: PendingDecision = PendingDecision.new(
			PendingDecision.Kind.FREE_ATTACK_ORDER, 1 - model.player,
			"Model %d retreats: choose the order of the free attacks against it." % model.id
		)
		decision.model_id = model.id
		decision.model_ids = retreat.enemies.duplicate()
		TurnFlow.ask(state, decision, events)
		return
	retreat.order = retreat.enemies.duplicate()
	_next_attack(state, events)


func move_budget_preview(state: GameState, model: ModelState) -> float:
	return TurnFlow.movement_budget(state, model)


## Answers FREE_ATTACK_ORDER.
static func set_order(state: GameState, order: Array[int], events: Array[GameEvent]) -> void:
	state.pending = null
	var retreat: RetreatResolution = state.resolution as RetreatResolution
	retreat.order = order.duplicate()
	_next_attack(state, events)


## Why `order` is not an order of the attackers waiting, or "".
static func order_error(state: GameState, order: Array[int]) -> String:
	var expected: Array[int] = state.pending.model_ids.duplicate()
	var given: Array[int] = order.duplicate()
	expected.sort()
	given.sort()
	if expected != given:
		return "The order must name each attacker once: %s." % str(state.pending.model_ids)
	return ""


## The next free attack, or the move once they are all made.
static func _next_attack(state: GameState, events: Array[GameEvent]) -> void:
	var retreat: RetreatResolution = state.resolution as RetreatResolution
	var model: ModelState = state.get_model(retreat.model_id)
	while retreat.next < retreat.order.size():
		var attacker: ModelState = state.get_model(retreat.order[retreat.next])
		retreat.next += 1
		if attacker == null or not attacker.on_table() or not model.on_table():
			continue
		state.rules.free_attack.resolve(state, attacker.id, model.id, events, _attack_done)
		return
	state.resolution = null
	var standing: bool = model.on_table() and not model.down
	if retreat.end_reason != "" or not standing:
		if state.turn.active_model_id == model.id:
			var reason: String = retreat.end_reason if retreat.end_reason != "" else "the model is not standing"
			TurnFlow.end_activation(state, events, reason)
		return
	TurnFlow.offer_move(state, model, retreat.action_id, events, EnemyZones.retreat(retreat.enemies))


## FreeAttackHook's `done`: on to the next attack.
static func _attack_done(state: GameState, events: Array[GameEvent]) -> void:
	if state.resolution is RetreatResolution:
		_next_attack(state, events)
