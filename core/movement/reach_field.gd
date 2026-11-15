class_name ReachField
extends RefCounted
## Everywhere the centre of one model's base can legally get to with its
## remaining movement, across the floors of the table, and the path there.
##
## A grid of nodes covers the square around the model that its movement could
## reach, grown by the base radius (clipped to the table plus a small margin).
## The model's own position is exactly a node. At each node there is one
## *state* per floor (HeightField surface) the base may pass through there, so
## a spot under a bridge and the spot on it are separate states.
##
## A shortest-path search runs over the states. Its steps are exactly the
## segments MoveLegality accepts:
## - walks to a neighbouring node on the same surface (16 neighbours), made
##   any-angle with Lazy Theta*: a state takes a straight line from further back
##   as its parent when that line is a legal walk on the same surface;
## - a change to another surface at the same height (the foot of a ramp, a
##   ramp meeting a platform), at the exact point on the way where the two
##   surfaces meet;
## - wall crossings (Transitions): from a state near a wall, walk until the
##   base touches it and climb to the point on top above the touch point; or
##   from a state near the edge of its surface, step off and land touching the
##   wall below. The point arrived at is then joined to the nodes around it.
## Off-grid points the path runs through (meeting points, touch points,
## arrival points) are kept as *anchors*; a path is a chain of anchors plus a
## straight walk to its end.
##
## The search routes through passable states; a state is a destination only
## if the model may stop there (MoveLegality.point_result()) and its path cost
## plus any low obstacle surcharge fits the movement left. Every path returned
## is re-priced with MoveLegality.segment_cost() and stop_surcharge(), the
## functions MoveCommand uses, so a path this field returns is a path
## MoveCommand accepts, at the cost this field reports.

const CELL_SIZE: float = 0.25
## Nodes searched past the remaining movement so the outline can close and
## interpolate smoothly at its edge. They are never reported as reachable.
const MARGIN_CELLS: int = 3
const EPSILON: float = 0.0001
## Clearance is only needed near obstacles (for the step shortcut and the
## outline), so it is capped here to skip far obstacles. Must stay above the
## longest step.
const CLEARANCE_CAP: float = 2.0
const NO_NODE: int = -1
const NONE: int = -1
## Bisection steps when snapping to the closest destination (2^-11 of the step).
const SNAP_ITERATIONS: int = 11

## Neighbour steps: 4 straight, 4 diagonal and 8 knight's moves.
const _STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
	Vector2i(1, 2), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(-1, -2),
]


## What the indicator draws for one surface: contour values on a part of the
## node grid, and where the surface can be seen (to clip what is drawn).
class Layer:
	extends RefCounted
	var surface: int
	## The part of the node grid this layer covers.
	var ix0: int
	var iz0: int
	var size_x: int
	var size_z: int
	## Negative where the centre may end a move, positive outside, roughly in
	## inches from the edge.
	var values: PackedFloat32Array
	## Positive where the surface is not there or covered by terrain, in inches.
	var clip: PackedFloat32Array


var model_id: int
## The model's position when the field was computed.
var start: Vector3
var budget: float
var cell_size: float
## Table position (world x, z) of node (0, 0). Node (i, j) is at origin + (i, j) * cell_size.
var origin: Vector2
var size_x: int = 0
var size_z: int = 0
var field: HeightField
var legality: MoveLegality

var _start_2d: Vector2
var _start_node: int = NO_NODE
var _radius: float = 0.0
var _limit: float = 0.0
var _step_lengths: PackedFloat64Array = PackedFloat64Array()

# States: (node, surface) pairs where the base may pass. The states at node n
# are _node_first[n] .. _node_first[n + 1] - 1.
var _node_first: PackedInt32Array = PackedInt32Array()
var _state_node: PackedInt32Array = PackedInt32Array()
var _state_surface: PackedInt32Array = PackedInt32Array()
var _state_pos: PackedVector3Array = PackedVector3Array()
var _state_pos_2d: PackedVector2Array = PackedVector2Array()
var _clearance: PackedFloat64Array = PackedFloat64Array()
## Whether the model may stop on a state: 0 not known yet, 1 yes, 2 no.
var _stand_ok: PackedByteArray = PackedByteArray()
## Low obstacle surcharge for stopping, per surface.
var _surface_surcharge: PackedFloat64Array = PackedFloat64Array()
var _cost: PackedFloat64Array = PackedFloat64Array()
var _parent: PackedInt32Array = PackedInt32Array()
var _parent_checked: PackedByteArray = PackedByteArray()
var _checked_cost: PackedFloat64Array = PackedFloat64Array()
var _checked_parent: PackedInt32Array = PackedInt32Array()
var _done: PackedByteArray = PackedByteArray()
var _state_anchor: PackedInt32Array = PackedInt32Array()
var _start_states: PackedInt32Array = PackedInt32Array()

# Anchors: points a path runs through. The path to an anchor is the path to
# _anchor_prev, then the _anchor_via points, then the anchor.
var _anchor_pos: PackedVector3Array = PackedVector3Array()
var _anchor_surface: PackedInt32Array = PackedInt32Array()
var _anchor_cost: PackedFloat64Array = PackedFloat64Array()
var _anchor_prev: PackedInt32Array = PackedInt32Array()
var _anchor_via: Array[PackedVector3Array] = []
var _anchor_clearance: PackedFloat64Array = PackedFloat64Array()
## Off-grid anchors by their nearest node, for joining queries to them.
var _anchors_near_node: Dictionary[int, PackedInt32Array] = {}
## Per node, the surfaces whose footprint is close enough to climb onto from there.
var _wall_surfaces_near: Array[PackedInt32Array] = []
## Per node, 1 if a state on another surface is within a step of it.
var _near_other_surface: PackedByteArray = PackedByteArray()

# Last point query, so hovering and then clicking does the work once.
var _query_key: Vector4 = Vector4(INF, INF, INF, INF)
var _query_anchor: int = NONE
var _query_surface: int = NONE
var _query_target: Vector3
var _query_path: Array[Vector3] = []
var _query_path_ready: bool = false

# Last closest_destination() query.
var _snap_point: Vector3 = Vector3(INF, INF, INF)
var _snap_max: float = -1.0
var _snap_result: Variant = null

## Shared empty list of via points (packed arrays copy on write).
var _NO_POINTS: PackedVector3Array = PackedVector3Array()
var _heap_cost: PackedFloat64Array = PackedFloat64Array()
var _heap_state: PackedInt32Array = PackedInt32Array()


## `p_budget` is how far the model may move (the action's budget); negative
## means its full Movement characteristic.
func _init(state: GameState, p_model_id: int, p_budget: float = -1.0, p_cell_size: float = CELL_SIZE) -> void:
	model_id = p_model_id
	cell_size = p_cell_size
	var model: ModelState = state.get_model(model_id)
	if model == null:
		push_error("ReachField: no model with id %d" % model_id)
		return
	start = model.position
	budget = p_budget if p_budget >= 0.0 else model.movement
	_start_2d = Vector2(start.x, start.z)
	legality = MoveLegality.new(state, model)
	field = legality.field
	_radius = legality.radius
	_limit = budget + MARGIN_CELLS * cell_size
	for step: Vector2i in _STEPS:
		_step_lengths.append(Vector2(step).length() * cell_size)
	_build_grid(state)
	_build_states()
	_build_wall_lists()
	_search()


## Radius of the model's base, inches.
func base_radius() -> float:
	return _radius


## Whether the base centre can get to `point` and end its move there. The point
## is on the floor whose height there is closest to point.y (within
## HeightField.TOLERANCE).
func is_reachable(point: Vector3) -> bool:
	_resolve(Vector2(point.x, point.z), _surfaces_for(point))
	return _query_anchor != NONE


## What a move to `point` along path_to() deducts (its path plus any low
## obstacle surcharge), or INF if `point` cannot be reached.
func cost_to(point: Vector3) -> float:
	var path: Array[Vector3] = path_to(point)
	if path.is_empty():
		return INF
	return _path_cost(path) + legality.stop_surcharge(path[path.size() - 1])


## The low obstacle surcharge for stopping at `point` (0 if none or unreachable).
func surcharge_at(point: Vector3) -> float:
	var path: Array[Vector3] = path_to(point)
	if path.is_empty():
		return 0.0
	return legality.stop_surcharge(path[path.size() - 1])


## Waypoints from the model's position to `point` (start excluded, the
## destination last, on its floor), ready for MoveCommand. Empty if `point`
## cannot be reached.
func path_to(point: Vector3) -> Array[Vector3]:
	_resolve(Vector2(point.x, point.z), _surfaces_for(point))
	return _query_path_now()


## How the segment from u to v of a path from this field is taken (a walk or
## a kind of wall crossing), for showing it.
func segment_kind(u: Vector3, v: Vector3) -> Transitions.Kind:
	legality.segment_cost(u, v)
	return legality.last_kind


## The destination closest to `point`: `point` itself if it is reachable, else
## the closest reachable centre position no more than `max_distance` away on
## the table plane, or null if there is none. The floor is the one at or near
## `point` (within max_distance) nearest its height, then the others, nearest
## height first. With the base
## radius as `max_distance` this is the destination for a cursor anywhere in
## the area the base edge can reach.
func closest_destination(point: Vector3, max_distance: float) -> Variant:
	if point == _snap_point and max_distance == _snap_max:
		return _snap_result
	_snap_point = point
	_snap_max = max_distance
	_snap_result = null
	if _cost.is_empty():
		return null
	var target: Vector2 = Vector2(point.x, point.z)
	# The floors there, and any whose edge is within reach of the cursor.
	var candidates: PackedInt32Array = field.surfaces_at(target)
	for s: HeightField.Surface in field.surfaces:
		if candidates.has(s.index):
			continue
		if s.is_table() or s.shape.signed_distance(target) <= max_distance:
			candidates.append(s.index)
	var order: Array[Vector2] = []
	for s: int in candidates:
		order.append(Vector2(absf(field.surface_height(s, target) - point.y), s))
	order.sort()
	for entry: Vector2 in order:
		var found: Variant = _closest_on_surface(target, int(entry.y), max_distance)
		if found != null:
			_snap_result = found
			break
	return _snap_result


func node_index(ix: int, iz: int) -> int:
	return iz * size_x + ix


func node_count() -> int:
	return size_x * size_z


func node_position_2d(index: int) -> Vector2:
	return origin + Vector2(index % size_x, index / size_x) * cell_size


func state_count() -> int:
	return _state_node.size()


## A state's position: its node, on its floor.
func state_position(index: int) -> Vector3:
	return _state_pos[index]


func state_surface(index: int) -> int:
	return _state_surface[index]


func state_node(index: int) -> int:
	return _state_node[index]


## Path cost to a state, INF if the search did not reach it.
func state_cost(index: int) -> float:
	return _cost[index]


## Whether a move may end on this state: the model may stop there, and its path
## plus any surcharge fits the movement left.
func is_state_reachable(index: int) -> bool:
	if _cost[index] + _surface_surcharge[_state_surface[index]] > budget + EPSILON:
		return false
	if _stand_ok[index] == 0:
		var ok: bool = legality.stop_result_if_passing(_state_pos_2d[index], _state_surface[index]) == MoveLegality.Result.OK
		_stand_ok[index] = 1 if ok else 2
	return _stand_ok[index] == 1


## The states at a node, one per floor the base may pass through there.
func states_at_node(node: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for k: int in range(_node_first[node], _node_first[node + 1]):
		result.append(k)
	return result


func surface_height(surface: int, p: Vector2) -> float:
	return field.surface_height(surface, p)


## One layer per surface with somewhere to stop on it, for drawing the area the
## model may end its move in (see Layer).
func contour_layers() -> Array[Layer]:
	var layers: Array[Layer] = []
	var groups: Dictionary[int, bool] = {}
	for k: int in state_count():
		if is_state_reachable(k):
			groups[field.level_members(_state_surface[k])[0]] = true
	for first: int in groups:
		layers.append(_layer_for(first))
	return layers


## One layer for a whole level surface (all its pieces, so no outline at the
## seams between them). `surface` is the group's first member; they share a plane.
func _layer_for(surface: int) -> Layer:
	var members: PackedInt32Array = field.level_members(surface)
	var layer: Layer = Layer.new()
	layer.surface = surface
	var bounds_min: Vector2 = Vector2(INF, INF)
	var bounds_max: Vector2 = Vector2(-INF, -INF)
	for member: int in members:
		bounds_min = bounds_min.min(field.surfaces[member].bounds_min)
		bounds_max = bounds_max.max(field.surfaces[member].bounds_max)
	var low: Vector2 = (bounds_min - origin) / cell_size
	var high: Vector2 = (bounds_max - origin) / cell_size
	layer.ix0 = clampi(floori(low.x) - 1, 0, size_x - 1)
	layer.iz0 = clampi(floori(low.y) - 1, 0, size_z - 1)
	var ix1: int = clampi(ceili(high.x) + 1, 0, size_x - 1)
	var iz1: int = clampi(ceili(high.y) + 1, 0, size_z - 1)
	layer.size_x = ix1 - layer.ix0 + 1
	layer.size_z = iz1 - layer.iz0 + 1
	layer.values.resize(layer.size_x * layer.size_z)
	layer.clip.resize(layer.size_x * layer.size_z)
	for j: int in layer.size_z:
		for i: int in layer.size_x:
			var node: int = node_index(layer.ix0 + i, layer.iz0 + j)
			var p: Vector2 = node_position_2d(node)
			var k: int = j * layer.size_x + i
			# Over the pieces the point is on (or the nearest one if none): the
			# lowest value, so the pieces read as one area.
			var on: PackedInt32Array = PackedInt32Array()
			var nearest: int = members[0]
			var nearest_distance: float = INF
			for member: int in members:
				var d: float = field.surfaces[member].shape.signed_distance(p)
				if d <= HeightField.EDGE_SLACK:
					on.append(member)
				if d < nearest_distance:
					nearest_distance = d
					nearest = member
			layer.clip[k] = field.level_visible_value(p, surface)
			if p.distance_to(_start_2d) > _limit:
				layer.values[k] = cell_size
				continue
			if on.is_empty():
				on.append(nearest)
			var value: float = INF
			for member: int in on:
				value = minf(value, _node_value(node, p, member))
			layer.values[k] = value
	return layer


func _node_value(node: int, p: Vector2, surface: int) -> float:
	var blocked: float = -legality.stand_value(p, surface, CLEARANCE_CAP)
	if blocked > EPSILON:
		return blocked
	var state: int = _state_at(node, surface)
	if state != NONE and _cost[state] < INF:
		return maxf(_cost[state] + _surface_surcharge[surface] - budget, blocked)
	return cell_size


func _build_grid(state: GameState) -> void:
	# Past the table edge by the margin too, so an area that runs to the edge
	# still closes on the grid. Nodes off the table are simply never legal.
	var margin: float = MARGIN_CELLS * cell_size
	var reach: float = budget + _radius + margin
	var left: int = maxi(floori(minf(reach, start.x + margin) / cell_size + EPSILON), 0)
	var right: int = maxi(floori(minf(reach, state.table_width - start.x + margin) / cell_size + EPSILON), 0)
	var near: int = maxi(floori(minf(reach, start.z + margin) / cell_size + EPSILON), 0)
	var far: int = maxi(floori(minf(reach, state.table_depth - start.z + margin) / cell_size + EPSILON), 0)
	size_x = left + right + 1
	size_z = near + far + 1
	origin = _start_2d - Vector2(left, near) * cell_size
	_start_node = node_index(left, near)


func _build_states() -> void:
	for s: int in field.surface_count():
		_surface_surcharge.append(field.stop_surcharge(s, legality.start_piece_ids))
	var count: int = node_count()
	_node_first.resize(count + 1)
	for node: int in count:
		_node_first[node] = _state_node.size()
		var p: Vector2 = node_position_2d(node)
		if node == _start_node:
			p = _start_2d
		# Every way there costs at least the distance on the table plane.
		if p.distance_to(_start_2d) > _limit:
			continue
		for surface: int in field.surfaces_at(p):
			if legality.passing_result(p, surface) != MoveLegality.Result.OK:
				continue
			var k: int = _state_node.size()
			_state_node.append(node)
			_state_surface.append(surface)
			var pos: Vector3 = legality.on_surface(p, surface)
			_state_pos.append(pos)
			_state_pos_2d.append(p)
			_clearance.append(legality.clearance(p, surface, CLEARANCE_CAP))
			if node == _start_node and legality.start_surfaces.has(surface):
				_start_states.append(k)
	_node_first[count] = _state_node.size()
	var states: int = _state_node.size()
	_cost.resize(states)
	_cost.fill(INF)
	_parent.resize(states)
	_parent.fill(NONE)
	_parent_checked.resize(states)
	_checked_cost.resize(states)
	_checked_cost.fill(INF)
	_checked_parent.resize(states)
	_checked_parent.fill(NONE)
	_done.resize(states)
	_stand_ok.resize(states)
	_state_anchor.resize(states)
	_state_anchor.fill(NONE)
	_mark_surface_boundaries()


## Marks nodes where the search may change surface: another surface within a step.
func _mark_surface_boundaries() -> void:
	var count: int = node_count()
	var signature: PackedInt32Array = PackedInt32Array()
	signature.resize(count)
	for node: int in count:
		var first: int = _node_first[node]
		var last: int = _node_first[node + 1]
		if first == last:
			signature[node] = NONE
		elif last - first == 1:
			signature[node] = _state_surface[first]
		else:
			signature[node] = -2
	_near_other_surface.resize(count)
	for node: int in count:
		var own: int = signature[node]
		if own == NONE:
			continue
		if own == -2:
			_near_other_surface[node] = 1
			continue
		var ix: int = node % size_x
		var iz: int = node / size_x
		for step: Vector2i in _STEPS:
			var nx: int = ix + step.x
			var nz: int = iz + step.y
			if nx < 0 or nz < 0 or nx >= size_x or nz >= size_z:
				continue
			var other: int = signature[nz * size_x + nx]
			if other != NONE and other != own:
				_near_other_surface[node] = 1
				break


## For climbing: which surfaces' footprints come within reach of each node.
func _build_wall_lists() -> void:
	_wall_surfaces_near.resize(node_count())
	var reach: float = _radius + _wall_reach()
	for s: HeightField.Surface in field.surfaces:
		if s.is_table():
			continue
		var low: Vector2 = (s.bounds_min - Vector2(reach, reach) - origin) / cell_size
		var high: Vector2 = (s.bounds_max + Vector2(reach, reach) - origin) / cell_size
		for iz: int in range(maxi(floori(low.y), 0), mini(ceili(high.y), size_z - 1) + 1):
			for ix: int in range(maxi(floori(low.x), 0), mini(ceili(high.x), size_x - 1) + 1):
				_wall_surfaces_near[node_index(ix, iz)].append(s.index)


## How far from a wall a node may be and still walk to it and cross it.
func _wall_reach() -> float:
	return cell_size * 1.5


func _search() -> void:
	for k: int in _start_states:
		var anchor: int = _add_anchor(_state_pos[k], _state_surface[k], 0.0, NONE, PackedVector3Array(), _clearance[k])
		_state_anchor[k] = anchor
		_cost[k] = 0.0
		_parent[k] = anchor
		_parent_checked[k] = 1
		_heap_push(0.0, k)
	while not _heap_cost.is_empty():
		var cost: float = _heap_cost[0]
		var state: int = _heap_pop()
		if _done[state] == 1 or cost > _cost[state]:
			continue
		if not _confirm_parent(state):
			_done[state] = 1
			continue
		_done[state] = 1
		if _cost[state] > _limit:
			break
		_expand_walks(state)
		_expand_switches(state)
		_expand_walls(state)
	_heap_cost.clear()
	_heap_state.clear()


## Walks to neighbouring nodes on the same surface.
func _expand_walks(state: int) -> void:
	var node: int = _state_node[state]
	var ix: int = node % size_x
	var iz: int = node / size_x
	var surface: int = _state_surface[state]
	var here: Vector2 = _state_pos_2d[state]
	var here_3d: Vector3 = _state_pos[state]
	var own: int = _anchor_of(state)
	var via: int = _parent[state]
	var via_3d: Vector3 = _anchor_pos[via]
	var via_cost: float = _anchor_cost[via]
	var cost_here: float = _cost[state]
	var here_clearance: float = _clearance[state]
	for s: int in _STEPS.size():
		var nx: int = ix + _STEPS[s].x
		var nz: int = iz + _STEPS[s].y
		if nx < 0 or nz < 0 or nx >= size_x or nz >= size_z:
			continue
		var next_node: int = nz * size_x + nx
		var next: int = _node_first[next_node]
		var next_end: int = _node_first[next_node + 1]
		while next < next_end and _state_surface[next] != surface:
			next += 1
		if next == next_end or _done[next] == 1:
			continue
		var there_3d: Vector3 = _state_pos[next]
		var lazy_cost: float = via_cost + via_3d.distance_to(there_3d)
		var step_cost: float = cost_here + here_3d.distance_to(there_3d)
		if minf(lazy_cost, step_cost) >= _cost[next] and step_cost >= _checked_cost[next]:
			continue
		# The grid step itself must be legal, so the fallback always has one.
		if (
			minf(here_clearance, _clearance[next]) < _step_lengths[s] * 0.5
			and legality.walk_result(here, _state_pos_2d[next], surface) != MoveLegality.Result.OK
		):
			continue
		if step_cost < _checked_cost[next]:
			_checked_cost[next] = step_cost
			_checked_parent[next] = own
		if lazy_cost < _cost[next]:
			_cost[next] = lazy_cost
			_parent[next] = via
			_parent_checked[next] = 1 if via == own else 0
			_heap_push(lazy_cost, next)
		elif step_cost < _cost[next]:
			_cost[next] = step_cost
			_parent[next] = own
			_parent_checked[next] = 1
			_heap_push(step_cost, next)


## Changes to another surface at the same height, on the way to a neighbouring
## node (or at this node).
func _expand_switches(state: int) -> void:
	var node: int = _state_node[state]
	if _near_other_surface[node] == 0:
		return
	var ix: int = node % size_x
	var iz: int = node / size_x
	var surface: int = _state_surface[state]
	var here: Vector2 = _state_pos_2d[state]
	for s: int in _STEPS.size() + 1:
		var nx: int = ix
		var nz: int = iz
		if s < _STEPS.size():
			nx += _STEPS[s].x
			nz += _STEPS[s].y
		if nx < 0 or nz < 0 or nx >= size_x or nz >= size_z:
			continue
		var next_node: int = nz * size_x + nx
		for next: int in range(_node_first[next_node], _node_first[next_node + 1]):
			var other: int = _state_surface[next]
			if other == surface or _done[next] == 1:
				continue
			var there: Vector2 = _state_pos_2d[next]
			# The two surfaces must come within the tolerance of each other between
			# the two points: they are planes, so the ends decide it.
			var gap_here: float = _state_pos[state].y - field.surface_height(other, here)
			var gap_there: float = field.surface_height(surface, there) - _state_pos[next].y
			var slack: float = HeightField.TOLERANCE * 0.5
			if (gap_here > slack and gap_there > slack) or (gap_here < -slack and gap_there < -slack):
				continue
			var meet: Variant = _meeting_point(here, there, surface, other)
			if meet == null:
				continue
			var q: Vector2 = meet
			var to_meet: float = legality.walk_length(here, q, surface)
			var cost: float = _cost[state] + to_meet + legality.walk_length(q, there, other)
			if cost >= _cost[next] and cost >= _checked_cost[next]:
				continue
			if legality.walk_result(here, q, surface) != MoveLegality.Result.OK:
				continue
			if legality.walk_result(q, there, other) != MoveLegality.Result.OK:
				continue
			var anchor: int = _add_anchor(
				legality.on_surface(q, other), other, _cost[state] + to_meet, _anchor_of(state),
				PackedVector3Array(), legality.clearance(q, other, CLEARANCE_CAP)
			)
			_offer_checked(next, cost, anchor)


## Where two surfaces meet at the same height on the way from a to b, or null.
func _meeting_point(a: Vector2, b: Vector2, from: int, to: int) -> Variant:
	var range_from: Vector2 = PlanarGeometry.segment_polygon_clip(a, b, field.surfaces[from].polygon)
	var range_to: Vector2 = PlanarGeometry.segment_polygon_clip(a, b, field.surfaces[to].polygon)
	var t0: float = maxf(range_from.x, range_to.x)
	var t1: float = minf(range_from.y, range_to.y)
	if t0 > t1:
		return null
	var f0: float = field.surface_height(from, a) - field.surface_height(to, a)
	var f1: float = field.surface_height(from, b) - field.surface_height(to, b)
	var t: float = t0
	if absf(f1 - f0) > 1e-9:
		t = clampf(f0 / (f0 - f1), t0, t1)
	var q: Vector2 = a.lerp(b, t)
	var gap: float = absf(field.surface_height(from, q) - field.surface_height(to, q))
	if gap > HeightField.TOLERANCE * 0.5:
		return null
	if not field.is_floor(q, from) or not field.is_floor(q, to):
		return null
	return q


## Wall crossings from a state near a wall (up) or near the edge of its surface (down).
func _expand_walls(state: int) -> void:
	var surface: int = _state_surface[state]
	var here: Vector2 = _state_pos_2d[state]
	var node: int = _state_node[state]
	var reach: float = _wall_reach()
	# Up: walk straight to the closest point of the wall until the base touches it.
	for high: int in _wall_surfaces_near[node]:
		if high == surface:
			continue
		var polygon: PackedVector2Array = field.surfaces[high].polygon
		var d: float = field.surfaces[high].shape.signed_distance(here)
		if d < _radius - MoveLegality.TOUCH_SLACK or d > _radius + reach:
			continue
		var top: Vector2 = PlanarGeometry.closest_point_on_polygon(here, polygon)
		var touch: Vector2 = top + (here - top) / d * _radius
		if field.surface_height(high, top) <= field.surface_height(surface, touch) + HeightField.TOLERANCE:
			continue
		_try_wall(state, touch, surface, top, high)
	# Down: walk to the edge of this surface and step off it.
	if surface == HeightField.TABLE:
		return
	var own: PackedVector2Array = field.surfaces[surface].polygon
	if -field.surfaces[surface].shape.signed_distance(here) > reach:
		return
	var n: int = own.size()
	var orientation: float = signf(PlanarGeometry.polygon_double_area(own))
	for i: int in n:
		var a: Vector2 = own[i]
		var b: Vector2 = own[(i + 1) % n]
		var normal: Vector2 = _outward_normal(own, i, orientation)
		var at: Vector2 = PlanarGeometry.closest_point_on_segment(here, a, b)
		if here.distance_to(at) > reach + EPSILON:
			continue
		var directions: Array[Vector2] = [normal]
		if at.distance_to(a) < EPSILON:
			directions.append((normal + _outward_normal(own, (i + n - 1) % n, orientation)).normalized())
		elif at.distance_to(b) < EPSILON:
			directions.append((normal + _outward_normal(own, (i + 1) % n, orientation)).normalized())
		var edge_height: float = field.surface_height(surface, at)
		for direction: Vector2 in directions:
			var land: Vector2 = at + direction * _radius
			var below: int = NONE
			for s: int in field.surfaces_at(land):
				if field.surface_height(s, land) < edge_height - HeightField.TOLERANCE:
					below = s
			if below != NONE:
				_try_wall(state, at, surface, land, below)


## Outward unit normal of edge i of a convex polygon (`orientation` is the sign
## of its area).
static func _outward_normal(polygon: PackedVector2Array, i: int, orientation: float) -> Vector2:
	var edge: Vector2 = polygon[(i + 1) % polygon.size()] - polygon[i]
	return Vector2(edge.y, -edge.x).normalized() * orientation


## Walks from the state to `from` on `from_surface`, crosses the wall to `to` on
## `to_surface`, and joins the arrival point to the nodes around it.
func _try_wall(state: int, from: Vector2, from_surface: int, to: Vector2, to_surface: int) -> void:
	var here: Vector2 = _state_pos_2d[state]
	# States expand cheapest first, so a crossing already made close by is
	# usually at least as good: skip this one if an arrival point near `to`
	# plus the way from it is no dearer than the least this one could cost.
	var least: float = _cost[state] + here.distance_to(from) + from.distance_to(to)
	if _arrival_near_is_as_cheap(to, to_surface, least):
		return
	if not field.is_floor(from, from_surface) or not field.is_floor(to, to_surface):
		return
	var walk: float = 0.0
	if here.distance_to(from) > EPSILON:
		if legality.walk_result(here, from, from_surface) != MoveLegality.Result.OK:
			return
		walk = legality.walk_length(here, from, from_surface)
	var crossing: float = legality.wall_cost(from, from_surface, to, to_surface)
	if crossing == INF:
		return
	var arrival_cost: float = _cost[state] + walk + crossing
	if arrival_cost > _limit:
		return
	var via: PackedVector3Array = PackedVector3Array()
	if here.distance_to(from) > EPSILON:
		via.append(legality.on_surface(from, from_surface))
	else:
		via.append(_state_pos[state])
	var anchor: int = NONE
	var local: Vector2 = (to - origin) / cell_size
	var span: int = 2
	var reach: float = cell_size * 1.5 + EPSILON
	for dz: int in range(-span, span + 1):
		for dx: int in range(-span, span + 1):
			var nx: int = roundi(local.x) + dx
			var nz: int = roundi(local.y) + dz
			if nx < 0 or nz < 0 or nx >= size_x or nz >= size_z:
				continue
			var next: int = _state_at(nz * size_x + nx, to_surface)
			if next == NONE or _done[next] == 1:
				continue
			var there: Vector2 = _state_pos_2d[next]
			if there.distance_to(to) > reach:
				continue
			var cost: float = arrival_cost + legality.walk_length(to, there, to_surface)
			if cost >= _cost[next] and cost >= _checked_cost[next]:
				continue
			if legality.walk_result(to, there, to_surface) != MoveLegality.Result.OK:
				continue
			if anchor == NONE:
				anchor = _add_anchor(
					legality.on_surface(to, to_surface), to_surface, arrival_cost, _anchor_of(state), via,
					legality.clearance(to, to_surface, CLEARANCE_CAP)
				)
				_register_anchor(anchor, to)
			_offer_checked(next, cost, anchor)
	if anchor == NONE:
		# Nothing to join, but the arrival point may still be a destination
		# (a centre on a straight ledge) or lead to one.
		anchor = _add_anchor(
			legality.on_surface(to, to_surface), to_surface, arrival_cost, _anchor_of(state), via,
			legality.clearance(to, to_surface, CLEARANCE_CAP)
		)
		_register_anchor(anchor, to)


## Whether an arrival anchor on `surface` within a cell of p costs no more than
## `cost` once the way from it to p is added.
func _arrival_near_is_as_cheap(p: Vector2, surface: int, cost: float) -> bool:
	var local: Vector2 = (p - origin) / cell_size
	var cx: int = roundi(local.x)
	var cz: int = roundi(local.y)
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var nx: int = cx + dx
			var nz: int = cz + dz
			if nx < 0 or nz < 0 or nx >= size_x or nz >= size_z:
				continue
			var node: int = nz * size_x + nx
			if not _anchors_near_node.has(node):
				continue
			for anchor: int in _anchors_near_node[node]:
				if _anchor_surface[anchor] != surface:
					continue
				var at: Vector3 = _anchor_pos[anchor]
				if _anchor_cost[anchor] + Vector2(at.x, at.z).distance_to(p) <= cost:
					return true
	return false


## Offers a parent whose line has been checked.
func _offer_checked(state: int, cost: float, anchor: int) -> void:
	if cost < _checked_cost[state]:
		_checked_cost[state] = cost
		_checked_parent[state] = anchor
	if cost < _cost[state]:
		_cost[state] = cost
		_parent[state] = anchor
		_parent_checked[state] = 1
		_heap_push(cost, state)


## Checks the straight line from a state's parent. If it is not legal, falls
## back to the cheapest checked parent offered to it. Returns false if there is
## none (cannot happen in practice: it was reached by one).
func _confirm_parent(state: int) -> bool:
	if _parent_checked[state] == 1:
		return true
	var parent: int = _parent[state]
	var surface: int = _state_surface[state]
	var from: Vector2 = Vector2(_anchor_pos[parent].x, _anchor_pos[parent].z)
	var here: Vector2 = _state_pos_2d[state]
	var length: float = from.distance_to(here)
	if (
		_anchor_surface[parent] == surface
		and (
			minf(_anchor_clearance[parent], _clearance[state]) >= length * 0.5
			or legality.walk_result(from, here, surface) == MoveLegality.Result.OK
		)
	):
		_parent_checked[state] = 1
		return true
	_cost[state] = _checked_cost[state]
	_parent[state] = _checked_parent[state]
	_parent_checked[state] = 1
	return _parent[state] != NONE


func _state_at(node: int, surface: int) -> int:
	for k: int in range(_node_first[node], _node_first[node + 1]):
		if _state_surface[k] == surface:
			return k
	return NONE


func _anchor_of(state: int) -> int:
	if _state_anchor[state] == NONE:
		_state_anchor[state] = _add_anchor(
			_state_pos[state], _state_surface[state], _cost[state], _parent[state],
			_NO_POINTS, _clearance[state]
		)
	return _state_anchor[state]


func _add_anchor(
	pos: Vector3, surface: int, cost: float, prev: int, via: PackedVector3Array, clearance: float
) -> int:
	_anchor_pos.append(pos)
	_anchor_surface.append(surface)
	_anchor_cost.append(cost)
	_anchor_prev.append(prev)
	_anchor_via.append(via)
	_anchor_clearance.append(clearance)
	return _anchor_pos.size() - 1


func _register_anchor(anchor: int, p: Vector2) -> void:
	var local: Vector2 = (p - origin) / cell_size
	var nx: int = clampi(roundi(local.x), 0, size_x - 1)
	var nz: int = clampi(roundi(local.y), 0, size_z - 1)
	var node: int = node_index(nx, nz)
	if not _anchors_near_node.has(node):
		_anchors_near_node[node] = PackedInt32Array()
	_anchors_near_node[node].append(anchor)


## The surfaces a query point may be on, nearest its height first.
func _surfaces_for(point: Vector3) -> PackedInt32Array:
	return legality.surfaces_at(point)


func _resolve(target: Vector2, surfaces: PackedInt32Array) -> void:
	var key: Vector4 = Vector4(target.x, target.y, surfaces[0] if not surfaces.is_empty() else -1, surfaces.size())
	if key == _query_key:
		return
	_query_key = key
	_query_anchor = NONE
	_query_surface = NONE
	_query_path_ready = false
	if _cost.is_empty() or _start_states.is_empty():
		return
	var best_total: float = INF
	for surface: int in surfaces:
		if legality.point_result(target, surface) != MoveLegality.Result.OK:
			continue
		var stop_budget: float = budget - field.stop_surcharge(surface, legality.start_piece_ids) + EPSILON
		var found: Vector2 = _best_source(target, surface, minf(stop_budget, best_total))
		if found.y != NONE and found.x < best_total:
			best_total = found.x
			_query_anchor = int(found.y)
			_query_surface = surface
			_query_target = legality.on_surface(target, surface)


## The cheapest anchor (or state, made an anchor) on `surface` that can walk
## straight to `target` within `limit`: (total cost, anchor), anchor NONE if none.
func _best_source(target: Vector2, surface: int, limit: float) -> Vector2:
	# Candidates as (total cost, anchor or -2 - state).
	var candidates: Array[Vector2] = []
	for k: int in _start_states:
		if _state_surface[k] == surface:
			candidates.append(Vector2(legality.walk_length(_start_2d, target, surface), _state_anchor[k]))
	var local: Vector2 = (target - origin) / cell_size
	var cx: int = roundi(local.x)
	var cz: int = roundi(local.y)
	var seen: Dictionary[int, bool] = {}
	for dz: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var nx: int = cx + dx
			var nz: int = cz + dz
			if nx < 0 or nz < 0 or nx >= size_x or nz >= size_z:
				continue
			var node: int = nz * size_x + nx
			var state: int = _state_at(node, surface)
			if state != NONE and _done[state] == 1 and _cost[state] < INF:
				candidates.append(Vector2(_cost[state] + legality.walk_length(_state_pos_2d[state], target, surface), -2 - state))
				var parent: int = _parent[state]
				if parent != NONE and _anchor_surface[parent] == surface and not seen.has(parent):
					seen[parent] = true
					var from: Vector2 = Vector2(_anchor_pos[parent].x, _anchor_pos[parent].z)
					candidates.append(Vector2(_anchor_cost[parent] + legality.walk_length(from, target, surface), parent))
			if _anchors_near_node.has(node):
				for anchor: int in _anchors_near_node[node]:
					if _anchor_surface[anchor] != surface or seen.has(anchor):
						continue
					seen[anchor] = true
					var from: Vector2 = Vector2(_anchor_pos[anchor].x, _anchor_pos[anchor].z)
					candidates.append(Vector2(_anchor_cost[anchor] + legality.walk_length(from, target, surface), anchor))
	candidates.sort()
	for candidate: Vector2 in candidates:
		if candidate.x > limit:
			break
		var source: int = int(candidate.y)
		var from: Vector2
		if source <= -2:
			from = _state_pos_2d[-2 - source]
		else:
			from = Vector2(_anchor_pos[source].x, _anchor_pos[source].z)
		if from.distance_to(target) > EPSILON and legality.walk_result(from, target, surface) != MoveLegality.Result.OK:
			continue
		if source <= -2:
			source = _anchor_of(-2 - source)
		return Vector2(candidate.x, source)
	return Vector2(INF, NONE)


func _query_path_now() -> Array[Vector3]:
	if _query_path_ready:
		return _query_path.duplicate()
	var result: Array[Vector3] = []
	if _query_anchor == NONE:
		return result
	var points: Array[Vector3] = [_query_target]
	var anchor: int = _query_anchor
	while anchor != NONE:
		points.push_front(_anchor_pos[anchor])
		var via: PackedVector3Array = _anchor_via[anchor]
		for k: int in range(via.size() - 1, -1, -1):
			points.push_front(via[k])
		anchor = _anchor_prev[anchor]
	points = _without_repeats(points)
	points = _simplify(points)
	for i: int in range(1, points.size()):
		result.append(points[i])
	if result.is_empty():
		result.append(_query_target)
	_query_path = result
	_query_path_ready = true
	return result.duplicate()


static func _without_repeats(points: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = [points[0]]
	for i: int in range(1, points.size()):
		if points[i].distance_to(result[result.size() - 1]) > 1e-5:
			result.append(points[i])
	return result


## Drops every waypoint whose neighbours can be joined by a legal straight walk
## on one surface that costs no more. Each drop keeps the path legal and never
## makes it dearer.
func _simplify(points: Array[Vector3]) -> Array[Vector3]:
	var current: Array[Vector3] = points
	for _pass: int in 3:
		if current.size() <= 2:
			return current
		var kept: Array[Vector3] = [current[0]]
		for i: int in range(1, current.size() - 1):
			var anchor: Vector3 = kept[kept.size() - 1]
			var shortcut: float = legality.walk_cost(anchor, current[i + 1])
			if shortcut == INF:
				kept.append(current[i])
				continue
			var through: float = legality.segment_cost(anchor, current[i]) + legality.segment_cost(current[i], current[i + 1])
			if shortcut > through + EPSILON:
				kept.append(current[i])
		kept.append(current[current.size() - 1])
		if kept.size() == current.size():
			return kept
		current = kept
	return current


func _path_cost(path: Array[Vector3]) -> float:
	var total: float = 0.0
	var previous: Vector3 = start
	for point: Vector3 in path:
		total += legality.segment_cost(previous, point)
		previous = point
	return total


func _reachable_on(p: Vector2, surface: int) -> bool:
	_resolve(p, PackedInt32Array([surface]))
	return _query_anchor != NONE


func _closest_on_surface(target: Vector2, surface: int, max_distance: float) -> Variant:
	if _reachable_on(target, surface):
		return legality.on_surface(target, surface)
	# The closest destination state, then the last reachable point on the line
	# from it towards the target. The edge of the area lies within a cell of
	# that state, so this lands on the edge close to the closest point.
	var span: float = max_distance + cell_size * 1.5
	var local: Vector2 = (target - origin) / cell_size
	var reach_cells: int = ceili(span / cell_size)
	var best_state: int = NONE
	var best_distance: float = INF
	for nz: int in range(maxi(floori(local.y) - reach_cells, 0), mini(ceili(local.y) + reach_cells, size_z - 1) + 1):
		for nx: int in range(maxi(floori(local.x) - reach_cells, 0), mini(ceili(local.x) + reach_cells, size_x - 1) + 1):
			var state: int = _state_at(nz * size_x + nx, surface)
			if state == NONE:
				continue
			var d: float = _state_pos_2d[state].distance_to(target)
			if d < best_distance and d <= span and is_state_reachable(state):
				best_distance = d
				best_state = state
	var best: Vector2 = Vector2(INF, INF)
	if best_state != NONE:
		best = _bisect_edge(_state_pos_2d[best_state], target, surface)
	# Off-grid destinations (a centre on a ledge reached by a climb).
	var anchors: Array[int] = []
	for nz: int in range(maxi(floori(local.y) - reach_cells, 0), mini(ceili(local.y) + reach_cells, size_z - 1) + 1):
		for nx: int in range(maxi(floori(local.x) - reach_cells, 0), mini(ceili(local.x) + reach_cells, size_x - 1) + 1):
			var node: int = nz * size_x + nx
			if _anchors_near_node.has(node):
				for anchor: int in _anchors_near_node[node]:
					if _anchor_surface[anchor] == surface:
						anchors.append(anchor)
	for anchor: int in anchors:
		var p: Vector2 = Vector2(_anchor_pos[anchor].x, _anchor_pos[anchor].z)
		if p.distance_to(target) < best.distance_to(target) and _reachable_on(p, surface):
			best = _closer(best, _bisect_edge(p, target, surface), target)
	if best.x == INF:
		return null
	# That line is not quite the shortest way to the edge. Two better guesses,
	# one per kind of edge, are kept if they are reachable and closer:
	# - The movement limit near `best` is a circle round the last turn of the
	#   path there, so the closest point lies on the line from that turn.
	_resolve(best, PackedInt32Array([surface]))
	var path: Array[Vector3] = _query_path_now()
	if not path.is_empty():
		var turn: Vector3 = start if path.size() < 2 else path[path.size() - 2]
		var pivot: Vector2 = Vector2(turn.x, turn.z)
		if legality.surfaces_at(turn).has(surface) and _reachable_on(pivot, surface):
			best = _closer(best, _bisect_edge(pivot, target, surface), target)
	# - Where a base, terrain, a ledge or the table edge stops the model, step
	#   out of it along the gradient of the stand value (exact for straight
	#   edges and circles).
	var stand: float = legality.stand_value(target, surface)
	if stand < 0.0:
		var h: float = 0.001
		var gradient: Vector2 = Vector2(
			legality.stand_value(target + Vector2(h, 0), surface) - legality.stand_value(target - Vector2(h, 0), surface),
			legality.stand_value(target + Vector2(0, h), surface) - legality.stand_value(target - Vector2(0, h), surface)
		)
		if gradient.length_squared() > 0.0:
			var out: Vector2 = target + gradient.normalized() * (-stand + EPSILON)
			if _reachable_on(out, surface):
				best = _closer(best, out, target)
	if best.distance_to(target) > max_distance + EPSILON:
		return null
	return legality.on_surface(best, surface)


## The last reachable point on the line from `inside` (reachable) towards `outside`.
func _bisect_edge(inside: Vector2, outside: Vector2, surface: int) -> Vector2:
	for _i: int in SNAP_ITERATIONS:
		var middle: Vector2 = (inside + outside) * 0.5
		if _reachable_on(middle, surface):
			inside = middle
		else:
			outside = middle
	return inside


static func _closer(a: Vector2, b: Vector2, target: Vector2) -> Vector2:
	return b if b.distance_to(target) < a.distance_to(target) else a


func _heap_push(cost: float, state: int) -> void:
	_heap_cost.append(cost)
	_heap_state.append(state)
	var i: int = _heap_cost.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		if _heap_cost[parent] <= cost:
			break
		_heap_cost[i] = _heap_cost[parent]
		_heap_state[i] = _heap_state[parent]
		i = parent
	_heap_cost[i] = cost
	_heap_state[i] = state


func _heap_pop() -> int:
	var top: int = _heap_state[0]
	var last: int = _heap_cost.size() - 1
	var cost: float = _heap_cost[last]
	var state: int = _heap_state[last]
	_heap_cost.resize(last)
	_heap_state.resize(last)
	if last == 0:
		return top
	var i: int = 0
	while true:
		var child: int = 2 * i + 1
		if child >= last:
			break
		if child + 1 < last and _heap_cost[child + 1] < _heap_cost[child]:
			child += 1
		if _heap_cost[child] >= cost:
			break
		_heap_cost[i] = _heap_cost[child]
		_heap_state[i] = _heap_state[child]
		i = child
	_heap_cost[i] = cost
	_heap_state[i] = state
	return top
