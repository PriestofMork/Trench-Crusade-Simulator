class_name ChargePlan
extends ActionPlan
## What a charge against one declared target means, worked out before it is
## declared (ChargePlanner, rulings 3 to 6 and 12 of brief 007): who is
## actually charged after interposing, the charge path to base contact, its
## length, and the D6 result the charge needs.
##
## `target_id` is the model actually charged; `declared_id` the one the
## player picked.

## No roll-free path to base contact within the longest possible charge.
const OUT_OF_REACH: int = -1

var charger_id: int = -1
var declared_id: int = -1
## The models that took the target's place, in order (ruling 4); the last is
## `target_id`.
var interposers: Array[int] = []
## Waypoints from the charger's position (excluded) to first contact (last).
var path: Array[Vector3] = []
## What the path costs, with any low obstacle surcharge for stopping at first
## contact; INF if there is none.
var length: float = INF
## The smallest D6 result that reaches: 0 if the Movement characteristic alone
## does, 1 to 6, or OUT_OF_REACH.
var needed: int = OUT_OF_REACH
## The declared target is in range but the charger cannot see it (brief 008):
## it cannot be charged.
var not_visible: bool = false


func interposed() -> bool:
	return not interposers.is_empty()


func reachable() -> bool:
	return needed != OUT_OF_REACH


## Whether any D6 result reaches.
func is_certain() -> bool:
	return needed == 0 or needed == 1


## Where first contact is (the charger's base centre), or the charger's
## position if there is no path.
func contact() -> Vector3:
	return path[path.size() - 1] if not path.is_empty() else Vector3.INF


## "certain", "needs 3+", "out of reach" or "not visible", for the UI.
func label() -> String:
	if not_visible:
		return "not visible"
	if not reachable():
		return "out of reach"
	if is_certain():
		return "certain"
	return "needs %d+" % needed
