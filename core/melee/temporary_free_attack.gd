class_name TemporaryFreeAttack
extends FreeAttackHook
## TEMPORARY (brief 007): attacks do not exist yet, so a free attack only
## reports that it would happen (FREE_ATTACK, "temporary": true) and is over
## at once. Brief 009 replaces it with a real melee attack.


func resolve(state: GameState, attacker_id: int, target_id: int, events: Array[GameEvent], done: Callable) -> void:
	var attacker: ModelState = state.get_model(attacker_id)
	events.append(GameEvent.new(GameEvent.Kind.FREE_ATTACK, attacker.player if attacker != null else -1, attacker_id, {
		"target_id": target_id, "temporary": true,
	}))
	done.call(state, events)
