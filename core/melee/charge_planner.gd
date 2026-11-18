class_name ChargePlanner
extends RefCounted
## Works out charges for one charger (docs/rules/movement.md, "Charge" and
## "Details (confirmed)"; brief 007 as corrected by briefs 008b and 008c).
## Following "Compute on demand" (docs/design.md), the two questions are
## asked separately:
##
## - Declaring (008c ruling 1, cheap): target_error(). An enemy model on the
##   table within 12", edge to edge in a straight line between the cylinders,
##   ignoring terrain, that the charger can see (GameState.rules.sight; brief
##   008). Every one of them can be declared, even one no D6 result reaches.
##   No route is worked out for this.
## - The route (rulings 3 to 5), only for one target when asked: plan(). A
##   goal-directed search (ReachField with a ReachGoal: the same steps,
##   crossings and legality as a Move) to that target, with the route choice
##   (with "allow climbs and jumps" off the shortest roll-free route, with it
##   on the shortest of any kind; ruling 2 of 008b) and the Drop / Climb down
##   choice. Every enemy 1" zone is open on the way (bases still block).
##   There is no distance limit beyond the table (ruling 4).
##   - The route ends at the cheapest position in base contact with the target
##     (ruling 7 of 008b: the bases touch seen from above and the cylinders
##     overlap in height) where the charger can stop. If no contact position
##     can be reached at all (the target on a pillar no wider than its base,
##     on a floor that needs a climb when climbs are off, or walled in), it
##     ends at the position closest to the target, edge to edge, where the
##     charger can stop (ruling 6 of 008b).
##   - Interposing (ruling 5; ruling 9 of 007): if the route comes within 1"
##     of another enemy before it comes within 1" of the target, that model
##     is charged instead and the search is run again to it. The model in the
##     way needs neither sight nor range.
##   - The D6 needed: the smallest result whose Movement + D6, halved as a
##     whole after standing up, covers the route; CANNOT_REACH if none does.
##   Plans are cached on the state (ChargeRouteCache) per charger, target,
##   route choice and descent mode, so the same charge asked for again (by
##   the game, or by the charge command when it is declared) is not searched
##   again until the state changes.
##
## Pure core: the game may plan on a worker thread.

## Targets are within this distance, edge to edge.
const RANGE_INCHES: float = 12.0
## The charge die.
const DIE_SIDES: int = 6
## Angles tried around the target's base for the closest contact point; the
## best is then refined between its neighbours.
const CONTACT_SAMPLES: int = 72
const REFINE_STEPS: int = 6
## How many of the contact points the search priced are priced again for the best.
const CONTACT_SHORTLIST: int = 8
## Spacing of the points checked along a route for interposing models.
const PATH_STEP: float = 0.05
const EPSILON: float = 0.0001
## The reason given for an enemy in range the charger cannot see.
const NOT_VISIBLE_ERROR: String = "The charger cannot see model %d."
## Ruling 6, the search for the closest place to the target: the rings of
## positions tried around it (how far apart, how far out at most), how many
## grid positions are tried at the end, how finely the edge is found, and how
## much closer counts (else the cheaper wins).
const CLOSEST_RING_STEP: float = 0.125
const CLOSEST_RING_LIMIT: float = 6.0
const CLOSEST_CANDIDATES: int = 24
const CLOSEST_HALVINGS: int = 9
const CLOSE_TIE: float = 0.01
## How close two floors' footprints must come for a climb or step between
## them (inches; more than any base radius plus the reach field's wall reach).
const LEVEL_NEAR: float = 1.5

var state: GameState
var charger: ModelState
## How drops of 3" or more are taken on the route (the Drop / Climb down choice).
var descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
## The longest charge the charger could make now (Movement + 6, halved after
## standing up).
var max_distance: float = 0.0
## The field of the last route searched (for reports).
var last_field: ReachField = null
## How many states the searches of this planner have taken, in all (for reports).
var states_taken: int = 0
## The angle round the target of each point of the last contact goal.
var _goal_angles: Array[float] = []


func _init(p_state: GameState, charger_id: int, p_descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP) -> void:
	state = p_state
	charger = state.get_model(charger_id)
	descent_mode = p_descent_mode
	if charger != null:
		max_distance = distance_for(DIE_SIDES)


## How far the charger charges on a D6 result of `roll`.
func distance_for(roll: int) -> float:
	return TurnFlow.movement_budget(state, charger, charger.movement + roll)


## The charge settings for moves along a charge route: every zone open.
static func zones() -> EnemyZones:
	return EnemyZones.charge()


## A legality for the charger with the charge settings and a route choice.
static func legality_for(
	p_state: GameState, model: ModelState, allow_rolls: bool = false,
	p_descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
) -> MoveLegality:
	var legality: MoveLegality = MoveLegality.new(p_state, model, null, zones())
	legality.allow_rolls = allow_rolls
	legality.descent_mode = p_descent_mode
	return legality


## The reach field's route choice for a charge route choice.
static func route_choice(allow_rolls: bool) -> ReachField.RouteChoice:
	return ReachField.RouteChoice.SHORTEST if allow_rolls else ReachField.RouteChoice.SAFE_ONLY


# --- Declaring (ruling 1) -------------------------------------------------------


## Why `target` cannot be declared as the target (not an enemy, too far, not
## seen), or "". Range is checked before sight, so an enemy in range that
## cannot be seen is told apart (not_visible()). Whether a D6 can reach does
## not matter. Cheap: no route is worked out.
func target_error(target: ModelState) -> String:
	if target == null:
		return "No such model to charge."
	if charger == null or not charger.on_table():
		return "The charger is not on the table."
	if target.player == charger.player:
		return "Only an enemy model can be charged."
	if not target.on_table():
		return "Model %d is Out of Action." % target.id
	if MeleeZone.gap(charger, target) > RANGE_INCHES + EPSILON:
		return "Model %d is more than %d\" away." % [target.id, int(RANGE_INCHES)]
	if not state.rules.sight.can_see(state, charger, target):
		return NOT_VISIBLE_ERROR % target.id
	return ""


## Whether `target` is an enemy in range that the charger cannot see.
func not_visible(target: ModelState) -> bool:
	return target != null and target_error(target) == NOT_VISIBLE_ERROR % target.id


## Enemy models on the table within 12", seen or not: what charge mode labels.
func in_range() -> Array[ModelState]:
	var result: Array[ModelState] = []
	if charger == null or not charger.on_table():
		return result
	for other: ModelState in state.models:
		if other.player != charger.player and other.on_table() and MeleeZone.gap(charger, other) <= RANGE_INCHES + EPSILON:
			result.append(other)
	return result


## The declaration check for every enemy in range: target id -> "" if it can
## be declared, else why not (not visible). What charge mode works out when
## it opens.
func declarations() -> Dictionary[int, String]:
	var result: Dictionary[int, String] = {}
	for other: ModelState in in_range():
		result[other.id] = target_error(other)
	return result


## The models the charger may declare a charge against.
func candidates() -> Array[ModelState]:
	var result: Array[ModelState] = []
	for other: ModelState in state.models:
		if other.player != charger.player and target_error(other) == "":
			result.append(other)
	return result


# --- The route (rulings 2 to 5) --------------------------------------------------


## The charge against `target_id` with both route choices: [rolls not
## allowed, rolls allowed]. Searches both (the game asks for one at a time).
func plans(target_id: int) -> Array[ChargePlan]:
	return [plan(target_id, false), plan(target_id, true)]


## Whether the plan for `target_id` with a route choice is already worked out
## for the current state.
func is_planned(target_id: int, allow_rolls: bool = false) -> bool:
	return state.charge_routes().get_plan(state, _key(target_id, allow_rolls)) != null


## The charge against `target_id` with a route choice: interposing applied,
## its route and the D6 it needs. The plan's error is set if it cannot be
## declared (then nothing is searched). Cached per state (see the class notes).
func plan(target_id: int, allow_rolls: bool = false) -> ChargePlan:
	var key: String = _key(target_id, allow_rolls)
	var cache: ChargeRouteCache = state.charge_routes()
	var cached: ChargePlan = cache.get_plan(state, key)
	if cached != null:
		return cached
	var result: ChargePlan = _plan_with(target_id, allow_rolls, target_error(state.get_model(target_id)))
	cache.put_plan(state, key, result)
	return result


func _key(target_id: int, allow_rolls: bool) -> String:
	return "%d>%d:%d:%d:%s" % [charger.id if charger != null else -1, target_id, int(allow_rolls), descent_mode, str(max_distance)]


func _plan_with(target_id: int, allow_rolls: bool, error: String) -> ChargePlan:
	var result: ChargePlan = ChargePlan.new()
	result.charger_id = charger.id if charger != null else -1
	result.declared_id = target_id
	result.target_id = target_id
	result.allow_rolls = allow_rolls
	result.descent_mode = descent_mode
	result.error = error
	if result.error != "":
		result.not_visible = result.error == NOT_VISIBLE_ERROR % target_id
		return result
	var visited: Dictionary[int, bool] = {}
	var current: int = target_id
	var legality: MoveLegality = null
	while true:
		visited[current] = true
		result.target_id = current
		var route: Dictionary = route_to(state.get_model(current), allow_rolls)
		result.path = route.get("path", [] as Array[Vector3])
		result.length = route.get("length", INF)
		result.contact = route.get("contact", false)
		legality = route.get("legality", null)
		if result.path.is_empty():
			break
		var interposer: int = interposing(result.path, current)
		if interposer == -1 or visited.has(interposer):
			break
		result.interposers.append(interposer)
		current = interposer
	if result.path.is_empty():
		result.needed = ChargePlan.CANNOT_REACH
		return result
	for segment: MoveSegment in legality.segments_for(charger.position, result.path):
		result.rolls.append_array(segment.rolls())
	result.needed = needed_roll(result.length)
	var target: ModelState = state.get_model(result.target_id)
	result.ends_in_melee = MeleeZone.is_within(MeleeZone.gap(charger, target, result.end()))
	return result


## The smallest D6 result whose charge distance covers `length`: 0 if no die
## is needed, 1 to 6, or ChargePlan.CANNOT_REACH.
func needed_roll(length: float) -> int:
	for roll: int in DIE_SIDES + 1:
		if distance_for(roll) + EPSILON >= length:
			return roll
	return ChargePlan.CANNOT_REACH


## The route to `target` with a route choice: {"path", "length", "contact",
## "legality"}, or {} if the charger cannot move anywhere. One goal-directed
## search to base contact; if no contact position can be reached, the closest
## position (ruling 6 of 008b).
func route_to(target: ModelState, allow_rolls: bool) -> Dictionary:
	state.charge_routes().count_search()
	var legality: MoveLegality = legality_for(state, charger, allow_rolls, descent_mode)
	var levels: Variant = null if allow_rolls else roll_free_levels(legality)
	var found: Dictionary = {}
	var goal: ReachGoal = _contact_goal(target, legality, levels)
	var reach: ReachField = null
	if not goal.is_empty():
		reach = _search(goal, allow_rolls)
		if reach.goal_reached():
			found = _best_contact(reach, target)
	if found.is_empty() and (reach == null or reach.goal_reached()):
		# No contact position (or none on a floor it can get onto): search
		# towards the closest places instead. If the contact search ran out
		# of places to go, it has already searched everywhere it can.
		reach = _search(_closest_goal(target, legality, levels), allow_rolls)
	if found.is_empty():
		found = _closest_position(target, reach)
	if not found.is_empty():
		found["legality"] = reach.legality
	return found


func _search(goal: ReachGoal, allow_rolls: bool) -> ReachField:
	var reach: ReachField = ReachField.new(
		state, charger.id, -1.0, ReachField.CELL_SIZE, descent_mode, zones(), allow_rolls, goal
	)
	reach.set_route_choice(route_choice(allow_rolls))
	last_field = reach
	states_taken += reach.expanded
	return reach


## The goal for base contact: the contact positions around the target where
## the charger could stop, on floors it could get onto (`levels`, null for
## any).
func _contact_goal(target: ModelState, legality: MoveLegality, levels: Variant) -> ReachGoal:
	var center: Vector2 = Vector2(target.position.x, target.position.z)
	var goal: ReachGoal = ReachGoal.new(center, charger.base_radius_inches() + target.base_radius_inches())
	_goal_angles.clear()
	var field: HeightField = state.height_field()
	var step: float = TAU / CONTACT_SAMPLES
	for k: int in CONTACT_SAMPLES:
		for point: Vector3 in contact_points(target, k * step):
			var p: Vector2 = Vector2(point.x, point.z)
			for s: int in field.surfaces_at(p):
				if absf(field.surface_height(s, p) - point.y) > EPSILON:
					continue
				if levels != null and not (levels as Dictionary).has(s):
					continue
				if legality.point_result(p, s) == MoveLegality.Result.OK:
					goal.add(point, s)
					_goal_angles.append(k * step)
	return goal


## Ruling 6: the goal for the closest place. Rings of positions round the
## target, a step apart and out to CLOSEST_RING_LIMIT, on every floor there
## the charger could get onto and stop on; the goal is those with the least
## gap to the target (edge to edge, in 3D), within the tie. Empty if there is
## none (the search then goes everywhere it can).
func _closest_goal(target: ModelState, legality: MoveLegality, levels: Variant) -> ReachGoal:
	var center: Vector2 = Vector2(target.position.x, target.position.z)
	var contact: float = charger.base_radius_inches() + target.base_radius_inches()
	var field: HeightField = state.height_field()
	var radius: float = charger.base_radius_inches()
	var height: float = charger.height_inches()
	var found: Array[Array] = []
	var least: float = INF
	var step: float = TAU / CONTACT_SAMPLES
	var d: float = 0.0
	# The gap is never less than the gap on the table plane, so rings further
	# out than the least gap found cannot do better.
	while d <= CLOSEST_RING_LIMIT and d <= least + CLOSE_TIE:
		for k: int in CONTACT_SAMPLES:
			var p: Vector2 = center + Vector2(cos(k * step), sin(k * step)) * (contact + d)
			for s: int in field.surfaces_at(p):
				if levels != null and not (levels as Dictionary).has(s):
					continue
				if legality.point_result(p, s) != MoveLegality.Result.OK:
					continue
				var at: Vector3 = legality.on_surface(p, s)
				var gap: float = MeleeZone.cylinder_gap(at, radius, height, target.position, target.base_radius_inches(), target.height_inches())
				least = minf(least, gap)
				found.append([gap, at, s, contact + d])
		d += CLOSEST_RING_STEP
	var nearest: float = INF
	for entry: Array in found:
		if entry[0] <= least + CLOSEST_RING_STEP:
			nearest = minf(nearest, entry[3])
	var goal: ReachGoal = ReachGoal.new(center, nearest if nearest < INF else contact)
	for entry: Array in found:
		if entry[0] <= least + CLOSEST_RING_STEP:
			goal.add(entry[1], entry[2])
	return goal


## The floors (surface indices -> true) the charger could get onto without
## a roll from where it stands. A cheap, generous check on the floors alone
## (it may say yes where the way is blocked, never no where there is one):
## two floors are linked if they join, or if their footprints come within
## LEVEL_NEAR and the least height between them could be crossed with no
## roll (Transitions: an open climb, a ladder, a step onto a low obstacle,
## a hop down). Contact positions on any other floor cannot be reached with
## climbs and jumps off, so the route search does not look for them.
func roll_free_levels(legality: MoveLegality) -> Dictionary:
	var field: HeightField = legality.field
	var key: String = "%d:%s" % [field.get_instance_id(), str(legality.start_surfaces)]
	var cache: ChargeRouteCache = state.charge_routes()
	var cached: Variant = cache.get_levels(key)
	if cached != null:
		return cached
	var reached: Dictionary = {}
	var queue: Array[int] = []
	for s: int in legality.start_surfaces:
		reached[s] = true
		queue.append(s)
	while not queue.is_empty():
		var a: int = queue.pop_back()
		for b: int in field.surface_count():
			if reached.has(b) or not _roll_free_link(field, a, b):
				continue
			reached[b] = true
			queue.append(b)
	cache.put_levels(key, reached)
	return reached


## Whether a model might get from floor `a` onto floor `b` with no roll (see
## roll_free_levels()).
static func _roll_free_link(field: HeightField, a: int, b: int) -> bool:
	if field.same_level(a, b) or field.joined_surfaces(a).has(b):
		return true
	var sa: HeightField.Surface = field.surfaces[a]
	var sb: HeightField.Surface = field.surfaces[b]
	var apart: Vector2 = (sb.bounds_min - sa.bounds_max).max(sa.bounds_min - sb.bounds_max)
	if apart.x > LEVEL_NEAR or apart.y > LEVEL_NEAR:
		return false
	# The floors are planes: over the corners of both footprints, the least
	# height between them (0 if they cross).
	var low: float = INF
	var high: float = -INF
	var corners: PackedVector2Array = PackedVector2Array()
	corners.append_array(sa.polygon)
	corners.append_array(sb.polygon)
	for p: Vector2 in corners:
		var rise: float = field.surface_height(b, p) - field.surface_height(a, p)
		low = minf(low, rise)
		high = maxf(high, rise)
	if low <= HeightField.TOLERANCE and high >= -HeightField.TOLERANCE:
		return true
	var going_up: bool = low > 0.0
	var wall: float = low if going_up else -high
	var piece: TerrainPiece = sb.piece if going_up else sa.piece
	var tag: TerrainPiece.Tag = piece.tag if piece != null else TerrainPiece.Tag.NONE
	var kind: Transitions.Kind = Transitions.roll_free_wall_kind(going_up, wall, tag, going_up and field.is_low_obstacle(b))
	return kind != Transitions.Kind.NONE


## The first other enemy whose 1" zone the route from the charger's position
## through `path` enters before it enters `target_id`'s, or -1.
func interposing(path: Array[Vector3], target_id: int) -> int:
	var target: ModelState = state.get_model(target_id)
	# Only enemies whose 1" zone comes near the route on the table plane (a
	# cheap test first; the gap in 3D is never less than that on the plane).
	var others: Array[ModelState] = []
	var reach: float = charger.base_radius_inches() + MeleeZone.DISTANCE + 0.01
	for other: ModelState in state.models:
		if other.player == charger.player or not other.on_table() or other.id == target_id:
			continue
		var centre: Vector2 = Vector2(other.position.x, other.position.z)
		var previous: Vector2 = Vector2(charger.position.x, charger.position.z)
		var near: float = INF
		for point: Vector3 in path:
			var next: Vector2 = Vector2(point.x, point.z)
			near = minf(near, centre.distance_to(PlanarGeometry.closest_point_on_segment(centre, previous, next)))
			previous = next
		if near <= reach + other.base_radius_inches():
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


## The base centre positions in base contact with `target` at `angle` around
## it (ruling 7 of 008b): on every floor there where the charger's cylinder
## would overlap the target's in height. Whether it can stop there is the
## reach field's to say.
func contact_points(target: ModelState, angle: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var r: float = charger.base_radius_inches() + target.base_radius_inches()
	var p: Vector2 = Vector2(target.position.x, target.position.z) + Vector2(cos(angle), sin(angle)) * r
	var height_field: HeightField = state.height_field()
	for s: int in height_field.surfaces_at(p):
		var h: float = height_field.surface_height(s, p)
		if MeleeZone.heights_overlap(h, charger.height_inches(), target.position.y, target.height_inches()):
			result.append(Vector3(p.x, h, p.y))
	return result


## The cheapest route in `reach` to base contact with `target`: {"path",
## "length", "contact": true}, or {} if there is none. Of the sampled angles
## around the target (the contact goal's points), the cheapest is refined
## between its neighbouring samples and priced exactly.
func _best_contact(reach: ReachField, target: ModelState) -> Dictionary:
	var best_cost: float = INF
	var best_point: Vector3 = Vector3.INF
	var best_angle: float = 0.0
	var step: float = TAU / CONTACT_SAMPLES
	# The contact points the search priced, cheapest first: the few best are
	# priced again as the field offers them (any-angle).
	var order: Array[Vector2] = []
	for i: int in reach.goal_costs.size():
		if reach.goal_costs[i] < INF:
			order.append(Vector2(reach.goal_costs[i], i))
	order.sort()
	for entry: Vector2 in order.slice(0, CONTACT_SHORTLIST):
		var i: int = int(entry.y)
		var cost: float = reach.estimate_cost(reach.goal.points[i])
		if cost < best_cost:
			best_cost = cost
			best_point = reach.goal.points[i]
			best_angle = _goal_angles[i]
	if best_cost == INF:
		return {}
	var span: float = step
	for _refine: int in REFINE_STEPS:
		span *= 0.5
		for angle: float in [best_angle - span, best_angle + span]:
			for point: Vector3 in contact_points(target, angle):
				var cost: float = reach.estimate_cost(point)
				if cost < best_cost - EPSILON:
					best_cost = cost
					best_point = point
					best_angle = angle
	var path: Array[Vector3] = reach.path_to(best_point)
	if path.is_empty():
		return {}
	return {"path": path, "length": reach.cost_to(best_point), "contact": true}


## Ruling 6 of 008b: the route to the position closest to `target`, edge to
## edge, where the charger can stop (the fewer inches on a tie), among the
## positions `reach` searched. {} if the charger can reach nowhere.
func _closest_position(target: ModelState, reach: ReachField) -> Dictionary:
	var radius: float = charger.base_radius_inches()
	var height: float = charger.height_inches()
	var safe: bool = reach.route_choice == ReachField.RouteChoice.SAFE_ONLY
	# The grid positions searched, closest first; the least gap of those it
	# may stop on, then the cheapest positions within a cell of it (so of
	# several equally close sides, the near one).
	var by_gap: Array[Vector2] = []
	for k: int in reach.state_count():
		var cost: float = reach.state_cost(k) if safe else reach.state_cost_with_rolls(k)
		if cost == INF:
			continue
		var gap: float = MeleeZone.cylinder_gap(
			reach.state_position(k), radius, height, target.position, target.base_radius_inches(), target.height_inches()
		)
		by_gap.append(Vector2(gap, k))
	by_gap.sort()
	var least: float = INF
	var near: Array[Vector2] = []
	for entry: Vector2 in by_gap:
		if entry.x > least + reach.cell_size:
			break
		var k: int = int(entry.y)
		if not (reach.is_state_safe(k) if safe else reach.is_state_reachable(k)):
			continue
		least = minf(least, entry.x)
		near.append(Vector2(reach.state_cost(k) if safe else reach.state_cost_with_rolls(k), k))
	if near.is_empty():
		return {}
	near.sort()
	# Each is then moved straight towards the target, on its floor, as far as
	# it can still stop (the edge found by halving), and the closest end
	# wins; of equally close ones (within CLOSE_TIE), the cheaper.
	var aim: Vector2 = Vector2(target.position.x, target.position.z)
	var point: Vector3 = Vector3.INF
	var point_key: Vector2 = Vector2(INF, INF)
	for entry: Vector2 in near.slice(0, CLOSEST_CANDIDATES):
		var k: int = int(entry.y)
		var at: Vector3 = reach.state_position(k)
		var surface: int = reach.state_surface(k)
		var inside: Vector2 = Vector2(at.x, at.z)
		var outside: Vector2 = aim
		for _halve: int in CLOSEST_HALVINGS:
			var middle: Vector2 = (inside + outside) * 0.5
			if reach.is_reachable(reach.legality.on_surface(middle, surface)):
				inside = middle
			else:
				outside = middle
		var end: Vector3 = reach.legality.on_surface(inside, surface)
		var gap: float = MeleeZone.cylinder_gap(end, radius, height, target.position, target.base_radius_inches(), target.height_inches())
		var key: Vector2 = Vector2(snappedf(gap, CLOSE_TIE), reach.estimate_cost(end))
		if key < point_key:
			point_key = key
			point = end
	var path: Array[Vector3] = reach.path_to(point)
	if path.is_empty():
		return {}
	return {"path": path, "length": reach.cost_to(point), "contact": false}
