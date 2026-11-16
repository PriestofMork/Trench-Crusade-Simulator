class_name EnemyZones
extends RefCounted
## How a move treats enemy models' 1" zones (docs/rules/movement.md, brief
## 007). Normally no point of a move may come within 1" of an enemy, and so it
## may not end there either. Two moves are different:
## - a charge (ruling 3): every zone is open, so the path may pass and end in
##   them; enemy bases still block (touching is allowed);
## - a retreat (ruling 10): the zones of the enemies the model was in melee
##   with are open for passing, but the move must end outside every zone, and
##   it may not come within 1" of any other enemy.
## A zone can also be ignored altogether, base included: sliding around the
## charge target's base (ruling 8) keeps to the circle of contact by
## construction, so the target is left out of the check.
##
## Plain data, never changed once made, so pending decisions and staged moves
## may share one.

## The zone distance for an enemy that is not considered at all.
const IGNORED: float = -1.0
## The zone distance for an open zone: only the base blocks.
const OPEN: float = 0.0

## Enemies whose zone may be passed through (bases still block).
var open_ids: Array[int] = []
## Every zone is open.
var all_open: bool = false
## Whether a move may also end inside the open zones (a charge).
var stop_in_open: bool = false
## Enemies left out of every check, base included.
var ignored_ids: Array[int] = []


## A charge: every zone open, for passing and for ending.
static func charge() -> EnemyZones:
	var zones: EnemyZones = EnemyZones.new()
	zones.all_open = true
	zones.stop_in_open = true
	return zones


## A retreat from the enemies `ids`: their zones may be passed, every zone
## holds for where the move ends.
static func retreat(ids: Array[int]) -> EnemyZones:
	var zones: EnemyZones = EnemyZones.new()
	zones.open_ids = ids.duplicate()
	return zones


## The zone distance (inches, edge to edge) the move keeps from enemy
## `enemy_id` while passing: the normal 1", OPEN or IGNORED.
func pass_distance(enemy_id: int, normal: float) -> float:
	if ignored_ids.has(enemy_id):
		return IGNORED
	if all_open or open_ids.has(enemy_id):
		return OPEN
	return normal


## The same for where the move ends.
func stop_distance(enemy_id: int, normal: float) -> float:
	var passing: float = pass_distance(enemy_id, normal)
	if passing == IGNORED:
		return IGNORED
	if passing == OPEN and stop_in_open:
		return OPEN
	return normal


## A short description for logs and tests.
func describe() -> String:
	if all_open:
		return "charge (zones open)"
	return "open %s, ignored %s" % [str(open_ids), str(ignored_ids)]
