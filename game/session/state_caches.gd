class_name StateCaches
extends RefCounted
## Answers game/ worked out from the current state (built reach fields, sight
## checks), by kind and key. All of them are dropped in one place, clear(),
## whenever the state changes (CommandSender). Charge routes are kept by core
## (GameState.charge_routes()), which checks the state itself.

var _entries: Dictionary[StringName, Dictionary] = {}


func lookup(kind: StringName, key: String) -> Variant:
	var entries: Dictionary = _entries.get(kind, {})
	return entries.get(key)


func has(kind: StringName, key: String) -> bool:
	return _entries.has(kind) and _entries[kind].has(key)


func store(kind: StringName, key: String, value: Variant) -> void:
	if not _entries.has(kind):
		_entries[kind] = {}
	_entries[kind][key] = value


## How many entries are kept, of one kind or (kind &"") of all.
func count(kind: StringName = &"") -> int:
	if kind != &"":
		return (_entries.get(kind, {}) as Dictionary).size()
	var total: int = 0
	for entries: Dictionary in _entries.values():
		total += entries.size()
	return total


func clear() -> void:
	_entries.clear()
