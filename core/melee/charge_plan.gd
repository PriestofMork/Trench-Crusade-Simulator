class_name ChargePlan
extends ActionPlan
## What a charge against one declared target means with one route choice,
## worked out before it is declared (ChargePlanner; brief 007 as corrected by
## brief 008b): who is actually charged after interposing, the route, its
## length, the rolls on it, and the D6 result the charge needs.
##
## `target_id` is the model actually charged; `declared_id` the one the
## player picked. A plan without an error can always be declared (ruling 5 of
## brief 008b), even when no D6 result reaches.

## No D6 result reaches the end of the route (ruling 5: "cannot reach").
const CANNOT_REACH: int = -1
## The name brief 007 used.
const OUT_OF_REACH: int = CANNOT_REACH

var charger_id: int = -1
var declared_id: int = -1
## The models that took the target's place, in order (ruling 9); the last is
## `target_id`.
var interposers: Array[int] = []
## The route choice (ruling 2): whether routes with climbs and jumps were
## allowed, and how drops of 3" or more are taken.
var allow_rolls: bool = false
var descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
## Waypoints from the charger's position (excluded) to where the route ends
## (last): base contact with the target, or, if no contact position can be
## reached at all, the closest position to it where the charger can stop
## (ruling 6). Empty only if the charger cannot move anywhere.
var path: Array[Vector3] = []
## What the route costs, with any low obstacle surcharge for stopping at its
## end; INF if there is no route.
var length: float = INF
## The rolls on the route, in order (MoveSegment.rolls()).
var rolls: Array[Dictionary] = []
## Whether the route ends in base contact with the target (ruling 7). False
## in the case of ruling 6.
var contact: bool = false
## Ruling 6: whether the end of the route is within 1" of the target.
var ends_in_melee: bool = false
## The smallest D6 result that reaches the end of the route: 0 if the
## Movement characteristic alone does, 1 to 6, or CANNOT_REACH.
var needed: int = CANNOT_REACH
## The declared target is in range but the charger cannot see it (brief 008):
## it cannot be charged.
var not_visible: bool = false


func interposed() -> bool:
	return not interposers.is_empty()


## Whether some D6 result reaches the end of the route.
func reachable() -> bool:
	return needed != CANNOT_REACH


## Whether every D6 result reaches.
func is_certain() -> bool:
	return needed == 0 or needed == 1


## How many risky rolls (climbs, jumps) the route makes.
func risky_rolls() -> int:
	var count: int = 0
	for roll: Dictionary in rolls:
		if roll.get("risky", false):
			count += 1
	return count


## How many injury rolls (drops and jumps down of 3" or more) it makes.
func injury_rolls() -> int:
	return rolls.size() - risky_rolls()


## Where the route ends (the charger's base centre), or Vector3.INF.
func end() -> Vector3:
	return path[path.size() - 1] if not path.is_empty() else Vector3.INF


## Where first contact is, as brief 007 named it (the end of the route).
func contact_point() -> Vector3:
	return end()


## "certain", "needs 4+", "needs 2+, 1 risky roll", "cannot reach" or "not
## visible", for the UI.
func label() -> String:
	if not_visible:
		return "not visible"
	var text: String
	if not reachable():
		text = "cannot reach"
	elif is_certain():
		text = "certain"
	else:
		text = "needs %d+" % needed
	var risky: int = risky_rolls()
	if risky > 0:
		text += ", %d risky roll%s" % [risky, "" if risky == 1 else "s"]
	var injuries: int = injury_rolls()
	if injuries > 0:
		text += ", %d injury roll%s" % [injuries, "" if injuries == 1 else "s"]
	if not contact and not path.is_empty():
		text += ", no base contact" + (" (in melee)" if ends_in_melee else "")
	return text
