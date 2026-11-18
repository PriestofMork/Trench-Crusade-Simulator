class_name ChargeRouteCache
extends RefCounted
## Charge plans already worked out (brief 008c, ruling 2), per charger,
## target, route choice and descent mode, for one game state. Derived data
## only, like the height field: it is thrown away as soon as the state it was
## worked out for changes (a model moved, added or taken off, a model going
## Down or standing up, terrain added, an undo), so asking for the same
## charge again in the same state costs nothing, and the charge command finds
## the route the player was shown (ruling 7).
##
## A worker thread may fill it while the main thread reads it, so every
## access is under a mutex.

## How many route searches have been run (one per model a route was searched
## to, interposers included), for tests and reports.
var searches: int = 0

var _mutex: Mutex = Mutex.new()
var _signature: String = ""
var _plans: Dictionary[String, ChargePlan] = {}
## The floors a charger can get onto without a roll, per start floor and
## height field (see ChargePlanner.roll_free_levels()).
var _levels: Dictionary[String, Dictionary] = {}


## The plan cached under `key` for this state, or null.
func get_plan(state: GameState, key: String) -> ChargePlan:
	var signature: String = state_signature(state)
	_mutex.lock()
	_check(signature)
	var plan: ChargePlan = _plans.get(key, null)
	_mutex.unlock()
	return plan


func put_plan(state: GameState, key: String, plan: ChargePlan) -> void:
	var signature: String = state_signature(state)
	_mutex.lock()
	_check(signature)
	_plans[key] = plan
	_mutex.unlock()


## Forgets every plan (benchmarks: time searches from an empty cache).
func clear_plans() -> void:
	_mutex.lock()
	_plans.clear()
	_mutex.unlock()


func count_search() -> void:
	_mutex.lock()
	searches += 1
	_mutex.unlock()


## How many plans are cached for the current state.
func size(state: GameState) -> int:
	var signature: String = state_signature(state)
	_mutex.lock()
	_check(signature)
	var n: int = _plans.size()
	_mutex.unlock()
	return n


func get_levels(key: String) -> Variant:
	_mutex.lock()
	var levels: Variant = _levels.get(key, null)
	_mutex.unlock()
	return levels


func put_levels(key: String, levels: Dictionary) -> void:
	_mutex.lock()
	_levels[key] = levels
	_mutex.unlock()


func _check(signature: String) -> void:
	if signature != _signature:
		_signature = signature
		_plans.clear()


## What a charge route depends on in the state: every model on the table
## (where it is, its base, its player, Down or not), which model is acting
## and whether it stood up, and the terrain (the height field built for it).
static func state_signature(state: GameState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("t%d:%d" % [state.terrain.size(), state.height_field().get_instance_id()])
	parts.append("a%d:%s" % [state.turn.active_model_id, str(state.turn.stood_up)])
	for model: ModelState in state.models:
		if not model.on_table():
			continue
		parts.append("%d:%d:%d:%s:%s:%s" % [
			model.id, model.player, model.base_mm, str(model.down), str(model.movement), var_to_str(model.position)
		])
	return "|".join(parts)
