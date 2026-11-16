class_name ChargePlanner
extends RefCounted
## Works out charges for one charger (docs/rules/movement.md, "Charge";
## rulings of brief 007):
## - targets (ruling 11, 12): enemy models on the table that the charger can
##   see (GameState.rules.sight) and that are within 12", edge to edge in a
##   straight line between the cylinders, ignoring terrain;
## - the charge path (ruling 3): the shortest legal path to base contact,
##   with every enemy 1" zone open (bases still block) and no rolls on the way
##   (ruling 5: walks, open climbs, ladders, low obstacles and drops under 3");
## - base contact (ruling 6): the charger's base touching the target's seen
##   from above, on a floor no more than the low obstacle height above or
##   below the target's, somewhere it can stop;
## - interposing (ruling 4): if the path comes within 1" of another enemy
##   before it comes within 1" of the target, that model is charged instead
##   and the path is worked out again to it;
## - the D6 needed (ruling 2): the smallest result whose Movement + D6,
##   halved as a whole after standing up, covers the path.
##
## One reach field (with the charge settings, as far as the longest charge
## can go) serves every target of the charger. Pure core: the game may build
## a planner on a worker thread.

## Ruling 12: targets are within this distance, edge to edge.
const RANGE_INCHES: float = 12.0
## The charge die.
const DIE_SIDES: int = 6
## Angles tried around the target's base for the closest contact point; the
## best is then refined between its neighbours.
const CONTACT_SAMPLES: int = 72
const REFINE_STEPS: int = 6
## Spacing of the points checked along a path for interposing models.
const PATH_STEP: float = 0.05
const EPSILON: float = 0.0001

var state: GameState
var charger: ModelState
## The longest charge the charger could make now (Movement + 6, halved after
## standing up).
var max_distance: float = 0.0
## Where the charge paths come from (built when first needed).
var _field: ReachField = null


func _init(p_state: GameState, charger_id: int) -> void:
	state = p_state
	charger = state.get_model(charger_id)
	if charger != null:
		max_distance = distance_for(DIE_SIDES)


## How far the charger charges on a D6 result of `roll` (ruling 2).
func distance_for(roll: int) -> float:
	return TurnFlow.movement_budget(state, charger, charger.movement + roll)


## The charge settings for moves and checks along a charge path.
static func zones() -> EnemyZones:
	return EnemyZones.charge()


## A legality for the charger with the charge settings.
static func legality_for(p_state: GameState, model: ModelState) -> MoveLegality:
	var legality: MoveLegality = MoveLegality.new(p_state, model, null, zones())
	legality.allow_rolls = false
	return legality


## The reach field of charge paths (open zones, no rolls, up to max_distance).
func field() -> ReachField:
	if _field == null:
		_field = ReachField.new(
			state, charger.id, max_distance, ReachField.CELL_SIZE, Transitions.DescentMode.DROP, zones(), false
		)
	return _field


## Why `target` cannot be declared as the target before any path is looked
## at (not an enemy, not seen, too far), or "".
func target_error(target: ModelState) -> String:
	if target == null:
		return "No such model to charge."
	if charger == null or not charger.on_table():
		return "The charger is not on the table."
	if target.player == charger.player:
		return "Only an enemy model can be charged."
	if not target.on_table():
		return "Model %d is Out of Action." % target.id
	if not state.rules.sight.can_see(state, charger, target):
		return "The charger cannot see model %d." % target.id
	if MeleeZone.gap(charger, target) > RANGE_INCHES + EPSILON:
		return "Model %d is more than %d\" away." % [target.id, int(RANGE_INCHES)]
	return ""


## The models the charger may declare a charge against (whatever the path).
func candidates() -> Array[ModelState]:
	var result: Array[ModelState] = []
	for other: ModelState in state.models:
		if other.player != charger.player and target_error(other) == "":
			result.append(other)
	return result


## The charge against `target_id`: interposing applied, its path and the D6
## it needs. The plan's error is set if it cannot be declared.
func plan(target_id: int) -> ChargePlan:
	var result: ChargePlan = ChargePlan.new()
	result.charger_id = charger.id if charger != null else -1
	result.declared_id = target_id
	result.target_id = target_id
	result.error = target_error(state.get_model(target_id))
	if result.error != "":
		return result
	var visited: Dictionary[int, bool] = {}
	var current: int = target_id
	while true:
		visited[current] = true
		result.target_id = current
		var best: Array = _best_contact(state.get_model(current))
		if best.is_empty():
			result.path = []
			result.length = INF
			result.needed = ChargePlan.OUT_OF_REACH
			result.error = "Out of reach: no path to base contact with model %d without a roll within %.1f\"." % [
				current, max_distance
			]
			return result
		result.path = best[0]
		result.length = best[1]
		var interposer: int = interposing(result.path, current)
		if interposer == -1 or visited.has(interposer):
			break
		result.interposers.append(interposer)
		current = interposer
	result.needed = needed_roll(result.length)
	if result.needed == ChargePlan.OUT_OF_REACH:
		result.error = "Out of reach: the charge path is %.1f\", more than the longest charge (%.1f\")." % [
			result.length, max_distance
		]
	return result


## The smallest D6 result whose charge distance covers `length`: 0 if no die
## is needed, 1 to 6, or ChargePlan.OUT_OF_REACH.
func needed_roll(length: float) -> int:
	for roll: int in DIE_SIDES + 1:
		if distance_for(roll) + EPSILON >= length:
			return roll
	return ChargePlan.OUT_OF_REACH


## The first other enemy whose 1" zone the path from the charger's position
## through `path` enters before it enters `target_id`'s, or -1 (ruling 4).
func interposing(path: Array[Vector3], target_id: int) -> int:
	var target: ModelState = state.get_model(target_id)
	var others: Array[ModelState] = []
	for other: ModelState in state.models:
		if other.player != charger.player and other.on_table() and other.id != target_id:
			others.append(other)
	if others.is_empty():
		return -1
	for point: Vector3 in sample_path(charger.position, path, PATH_STEP):
		if MeleeZone.is_within(MeleeZone.gap(charger, target, point)):
			return -1
		var found: int = -1
		var closest: float = INF
		for other: ModelState in others:
			var gap: float = MeleeZone.gap(charger, other, point)
			if MeleeZone.is_within(gap) and gap < closest:
				closest = gap
				found = other.id
		if found != -1:
			return found
	return -1


## Points along a path from `start` through `points`, no more than `step`
## apart, both ends included.
static func sample_path(start: Vector3, points: Array[Vector3], step: float) -> Array[Vector3]:
	var result: Array[Vector3] = [start]
	var previous: Vector3 = start
	for point: Vector3 in points:
		var count: int = maxi(ceili(previous.distance_to(point) / step), 1)
		for j: int in range(1, count + 1):
			result.append(previous.lerp(point, float(j) / count))
		previous = point
	return result


## The base centre positions in contact with `target` that the charger could
## stand on, at `angle` around it (ruling 6): on each floor there within the
## low obstacle height of the target's.
func contact_points(target: ModelState, angle: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var r: float = charger.base_radius_inches() + target.base_radius_inches()
	var p: Vector2 = Vector2(target.position.x, target.position.z) + Vector2(cos(angle), sin(angle)) * r
	var height_field: HeightField = state.height_field()
	for s: int in height_field.surfaces_at(p):
		var h: float = height_field.surface_height(s, p)
		if absf(h - target.position.y) <= TerrainRules.LOW_OBSTACLE_HEIGHT + Transitions.HEIGHT_SLACK:
			result.append(Vector3(p.x, h, p.y))
	return result


## Whether the floor of a charger standing at `at` is close enough in height
## to `target`'s for base contact (ruling 6).
static func heights_allow_contact(at: Vector3, target: ModelState) -> bool:
	return absf(at.y - target.position.y) <= TerrainRules.LOW_OBSTACLE_HEIGHT + Transitions.HEIGHT_SLACK


## The cheapest path to base contact with `target`: [waypoints, cost], or
## empty if there is none within max_distance.
func _best_contact(target: ModelState) -> Array:
	var reach: ReachField = field()
	var best_cost: float = INF
	var best_point: Vector3 = Vector3.INF
	var best_angle: float = 0.0
	var step: float = TAU / CONTACT_SAMPLES
	for k: int in CONTACT_SAMPLES:
		var angle: float = k * step
		for point: Vector3 in contact_points(target, angle):
			var cost: float = reach.cost_to(point)
			if cost < best_cost:
				best_cost = cost
				best_point = point
				best_angle = angle
	if best_cost == INF:
		return []
	# Refine between the neighbouring samples.
	var span: float = step
	for _refine: int in REFINE_STEPS:
		span *= 0.5
		for angle: float in [best_angle - span, best_angle + span]:
			for point: Vector3 in contact_points(target, angle):
				var cost: float = reach.cost_to(point)
				if cost < best_cost - EPSILON:
					best_cost = cost
					best_point = point
					best_angle = angle
	return [reach.path_to(best_point), best_cost]
