class_name ChargePlanner
extends RefCounted
## Works out charges for one charger (docs/rules/movement.md, "Charge" and
## "Details (confirmed)"; brief 007 as corrected by brief 008b):
## - targets (ruling 5 of 008b): enemy models on the table within 12", edge to
##   edge in a straight line between the cylinders, ignoring terrain, that the
##   charger can see (GameState.rules.sight; brief 008). Every one of them can
##   be declared, even one that no D6 result reaches;
## - the route, for each route choice (ruling 2): with "allow climbs and
##   jumps" off the shortest roll-free route, with it on the shortest route of
##   any kind (sheer climbs, gap jumps, drops of 3" or more; ruling 1). Every
##   enemy 1" zone is open on the way (bases still block). The Drop / Climb
##   down choice applies as for a Move. The routes come from the reach field,
##   the same search a Move uses (ReachField: its tier 0 is the roll-free
##   search, so one field serves both choices);
## - the end of the route: the cheapest position in base contact with the
##   target (ruling 7: the bases touch seen from above and the cylinders
##   overlap in height) where the charger can stop. If none is within the
##   longest charge, the route is looked for further (EXTENDED_DISTANCE) so a
##   charge that cannot succeed still moves along it (rulings 4 and 5). If no
##   contact position can be reached at all (the target on a pillar no wider
##   than its base, or walled in), the route ends at the position closest to
##   the target, edge to edge, where the charger can stop (ruling 6);
## - interposing (ruling 9, unchanged from 007): if the route comes within 1"
##   of another enemy before it comes within 1" of the target, that model is
##   charged instead and the route is worked out again to it. The model in
##   the way needs neither sight nor range;
## - the D6 needed: the smallest result whose Movement + D6, halved as a whole
##   after standing up, covers the route; CANNOT_REACH if none does.
##
## Pure core: the game may build a planner on a worker thread.

## Targets are within this distance, edge to edge.
const RANGE_INCHES: float = 12.0
## The charge die.
const DIE_SIDES: int = 6
## Angles tried around the target's base for the closest contact point; the
## best is then refined between its neighbours.
const CONTACT_SAMPLES: int = 72
const REFINE_STEPS: int = 6
## Spacing of the points checked along a route for interposing models.
const PATH_STEP: float = 0.05
const EPSILON: float = 0.0001
## The reason given for an enemy in range the charger cannot see.
const NOT_VISIBLE_ERROR: String = "The charger cannot see model %d."
## How long a route may be when the longest charge does not reach contact:
## the second, coarser reach field goes this far (ruling 5).
const EXTENDED_DISTANCE: float = 18.0
const EXTENDED_CELL: float = 0.5
## Ruling 6, the search for the closest place to the target: how many grid
## positions are tried, how finely the edge is found, and how much closer
## counts (else the cheaper wins).
const CLOSEST_CANDIDATES: int = 24
const CLOSEST_HALVINGS: int = 9
const CLOSE_TIE: float = 0.01

var state: GameState
var charger: ModelState
## How drops of 3" or more are taken on the route (the Drop / Climb down choice).
var descent_mode: Transitions.DescentMode = Transitions.DescentMode.DROP
## The longest charge the charger could make now (Movement + 6, halved after
## standing up).
var max_distance: float = 0.0
## Where the routes come from (built when first needed): one field as far as
## the longest charge, one coarser and further for charges it does not reach.
var _field: ReachField = null
var _extended: ReachField = null
## Per field and target id, the best contact for both route choices
## ([rolls not allowed, rolls allowed]; {} where there is none), found in one
## pass.
var _contacts: Dictionary = {}


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


## The reach field of charge routes up to max_distance (rolls searched, so
## both route choices come from it).
func field() -> ReachField:
	if _field == null:
		_field = ReachField.new(state, charger.id, max_distance, ReachField.CELL_SIZE, descent_mode, zones(), true)
	return _field


## The coarser field for routes longer than the longest charge. Built with
## rolls only if a route with rolls is wanted (its tier 0 then also serves the
## roll-free choice); a roll-free one is cheaper.
func extended_field(allow_rolls: bool = true) -> ReachField:
	if _extended != null and (_extended.allow_rolls or not allow_rolls):
		return _extended
	_extended = ReachField.new(
		state, charger.id, maxf(EXTENDED_DISTANCE, max_distance), EXTENDED_CELL, descent_mode, zones(), allow_rolls
	)
	for key: Vector2i in _contacts.keys():
		if key.x == 1:
			_contacts.erase(key)
	return _extended


## Why `target` cannot be declared as the target (not an enemy, too far, not
## seen), or "". Range is checked before sight, so an enemy in range that
## cannot be seen is told apart (not_visible()). Whether a D6 can reach does
## not matter (ruling 5).
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


## The models the charger may declare a charge against.
func candidates() -> Array[ModelState]:
	var result: Array[ModelState] = []
	for other: ModelState in state.models:
		if other.player != charger.player and target_error(other) == "":
			result.append(other)
	return result


## The charge against `target_id` with both route choices: [rolls not
## allowed, rolls allowed].
func plans(target_id: int) -> Array[ChargePlan]:
	var error: String = target_error(state.get_model(target_id))
	return [_plan_with(target_id, false, error), _plan_with(target_id, true, error)]


## The charge against `target_id` with a route choice: interposing applied,
## its route and the D6 it needs. The plan's error is set if it cannot be
## declared.
func plan(target_id: int, allow_rolls: bool = false) -> ChargePlan:
	return _plan_with(target_id, allow_rolls, target_error(state.get_model(target_id)))


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
	while true:
		visited[current] = true
		result.target_id = current
		var route: Dictionary = route_to(state.get_model(current), allow_rolls)
		result.path = route.get("path", [] as Array[Vector3])
		result.length = route.get("length", INF)
		result.contact = route.get("contact", false)
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
	for segment: MoveSegment in field().legality.segments_for(charger.position, result.path):
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


## The route to `target` with a route choice: {"path", "length", "contact"},
## or {} if the charger cannot move anywhere. Base contact within the longest
## charge, else further (ruling 5), else the closest position (ruling 6).
func route_to(target: ModelState, allow_rolls: bool) -> Dictionary:
	var index: int = 1 if allow_rolls else 0
	var choice: ReachField.RouteChoice = route_choice(allow_rolls)
	var found: Dictionary = _contacts_in(field(), target)[index]
	if not found.is_empty():
		return found
	# Further than the longest charge, unless nothing further can be reached.
	var further: bool = field().reaches_beyond(choice)
	if further:
		found = _contacts_in(extended_field(allow_rolls), target)[index]
	if found.is_empty():
		found = _closest_position(target, choice, extended_field(allow_rolls) if further else field())
	return found


## The best contact routes in `reach` for both route choices (cached).
func _contacts_in(reach: ReachField, target: ModelState) -> Array:
	var key: Vector2i = Vector2i(1 if reach == _extended else 0, target.id)
	if not _contacts.has(key):
		_contacts[key] = _best_contacts(reach, target)
	return _contacts[key]


## The first other enemy whose 1" zone the route from the charger's position
## through `path` enters before it enters `target_id`'s, or -1.
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


## The base centre positions in base contact with `target` at `angle` around
## it (ruling 7): on every floor there where the charger's cylinder would
## overlap the target's in height. Whether it can stop there is the reach
## field's to say.
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


## The cheapest routes in `reach` to base contact with `target`, for both
## route choices: [rolls not allowed, rolls allowed], each {"path", "length",
## "contact": true}, or {} if there is none. The angles around the target are
## sampled once for both (ReachField.estimate_costs()), then each best is
## refined between its neighbouring samples and priced exactly.
func _best_contacts(reach: ReachField, target: ModelState) -> Array:
	var best_cost: Array[float] = [INF, INF]
	var best_point: Array[Vector3] = [Vector3.INF, Vector3.INF]
	var best_angle: Array[float] = [0.0, 0.0]
	var step: float = TAU / CONTACT_SAMPLES
	for k: int in CONTACT_SAMPLES:
		var angle: float = k * step
		for point: Vector3 in contact_points(target, angle):
			var costs: Vector2 = reach.estimate_costs(point)
			for i: int in 2:
				if costs[i] < best_cost[i]:
					best_cost[i] = costs[i]
					best_point[i] = point
					best_angle[i] = angle
	var result: Array = []
	for i: int in 2:
		if best_cost[i] == INF:
			result.append({})
			continue
		reach.set_route_choice(route_choice(i == 1))
		var span: float = step
		for _refine: int in REFINE_STEPS:
			span *= 0.5
			for angle: float in [best_angle[i] - span, best_angle[i] + span]:
				for point: Vector3 in contact_points(target, angle):
					var cost: float = reach.estimate_cost(point)
					if cost < best_cost[i] - EPSILON:
						best_cost[i] = cost
						best_point[i] = point
						best_angle[i] = angle
		var path: Array[Vector3] = reach.path_to(best_point[i])
		if path.is_empty():
			result.append({})
		else:
			result.append({"path": path, "length": reach.cost_to(best_point[i]), "contact": true})
	return result


## Ruling 6: the route to the position closest to `target`, edge to edge,
## where the charger can stop (the fewer inches on a tie), searched in
## `reach`: from the finer field if it reaches that position, else from
## `reach`. {} if the charger can reach nowhere.
func _closest_position(target: ModelState, choice: ReachField.RouteChoice, reach: ReachField) -> Dictionary:
	reach.set_route_choice(choice)
	var radius: float = charger.base_radius_inches()
	var height: float = charger.height_inches()
	var safe: bool = choice == ReachField.RouteChoice.SAFE_ONLY
	# The least gap any grid position reaches, then the cheapest position
	# within a cell of it (so of several equally close sides, the near one).
	var gaps: PackedFloat64Array = PackedFloat64Array()
	gaps.resize(reach.state_count())
	var least: float = INF
	for k: int in reach.state_count():
		gaps[k] = INF
		if not (reach.is_state_safe(k) if safe else reach.is_state_reachable(k)):
			continue
		gaps[k] = MeleeZone.cylinder_gap(
			reach.state_position(k), radius, height, target.position, target.base_radius_inches(), target.height_inches()
		)
		least = minf(least, gaps[k])
	if least == INF:
		return {}
	# The grid positions within a cell of it, cheapest first: each is then
	# moved straight towards the target, on its floor, as far as it can still
	# stop (the edge found by halving), and the closest end wins; of equally
	# close ones (within CLOSE_TIE), the cheaper.
	var near: Array[Vector2] = []
	for k: int in reach.state_count():
		if gaps[k] <= least + reach.cell_size:
			near.append(Vector2(reach.state_cost(k) if safe else reach.state_cost_with_rolls(k), k))
	near.sort()
	var fine: ReachField = field()
	fine.set_route_choice(choice)
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
			var q: Vector3 = reach.legality.on_surface(middle, surface)
			if fine.is_reachable(q) or reach.is_reachable(q):
				inside = middle
			else:
				outside = middle
		var end: Vector3 = reach.legality.on_surface(inside, surface)
		var gap: float = MeleeZone.cylinder_gap(end, radius, height, target.position, target.base_radius_inches(), target.height_inches())
		var cost: float = fine.estimate_cost(end)
		if cost == INF:
			cost = reach.estimate_cost(end)
		var key: Vector2 = Vector2(snappedf(gap, CLOSE_TIE), cost)
		if key < point_key:
			point_key = key
			point = end
	for source: ReachField in [fine, reach]:
		var path: Array[Vector3] = source.path_to(point)
		if not path.is_empty():
			return {"path": path, "length": source.cost_to(point), "contact": false}
	return {}
