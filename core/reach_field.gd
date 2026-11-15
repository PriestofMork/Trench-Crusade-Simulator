class_name ReachField
extends RefCounted
## Everywhere the centre of one model's base can legally get to on flat ground
## with its remaining movement, and the path there.
##
## A grid of nodes covers the square around the model that its movement could
## reach (clipped to the table). The model's own position is exactly a node. A
## node is standable if the base may stand there; a shortest-path search with
## 16 neighbours runs over standable nodes, and a step is taken only if the base
## swept along it is legal. All checks are MoveLegality, the same ones
## MoveCommand uses, so every path returned here is a path MoveCommand accepts.
## Grid paths are never shorter than the straight line, so the field is a little
## conservative, never optimistic.

const CELL_SIZE: float = 0.25
## Nodes searched past the remaining movement so the outline can close and
## interpolate smoothly at its edge. They are never reported as reachable.
const MARGIN_CELLS: int = 3
const EPSILON: float = 0.0001
const NO_NODE: int = -1

## Neighbour steps: 4 straight, 4 diagonal and 8 knight's moves.
const _STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
	Vector2i(1, 2), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(-1, -2),
]

var model_id: int
## The model's position when the field was computed.
var start: Vector3
var movement_left: float
var cell_size: float
## Table position (world x, z) of node (0, 0). Node (i, j) is at origin + (i, j) * cell_size.
var origin: Vector2
var size_x: int = 0
var size_z: int = 0

var _legality: MoveLegality
var _start_2d: Vector2
var _start_node: int = NO_NODE
var _clearance: PackedFloat64Array = PackedFloat64Array()
var _cost: PackedFloat64Array = PackedFloat64Array()
var _parent: PackedInt32Array = PackedInt32Array()

# Last point query, so hovering and then clicking does the work once.
# _query_cost is the grid cost, an upper bound on the final path's length.
var _query_point: Vector2 = Vector2(INF, INF)
var _query_cost: float = INF
## NO_NODE: unreachable. -2: straight from the start. Otherwise the node the path runs through last.
var _query_node: int = NO_NODE
var _query_path: Array[Vector3] = []
var _query_path_ready: bool = false

var _heap_cost: PackedFloat64Array = PackedFloat64Array()
var _heap_node: PackedInt32Array = PackedInt32Array()

const _DIRECT: int = -2


func _init(state: GameState, p_model_id: int, p_cell_size: float = CELL_SIZE) -> void:
	model_id = p_model_id
	cell_size = p_cell_size
	var model: ModelState = state.get_model(model_id)
	if model == null:
		push_error("ReachField: no model with id %d" % model_id)
		return
	start = model.position
	movement_left = model.movement_left
	_start_2d = Vector2(start.x, start.z)
	_legality = MoveLegality.new(state, model)
	_build_grid(state)
	_compute_clearance()
	_search()


## Whether the base centre can get to `point` (its y is ignored).
func is_reachable(point: Vector3) -> bool:
	_resolve(Vector2(point.x, point.z))
	return _query_node != NO_NODE


## Length of the path path_to() returns, or INF if `point` cannot be reached.
## This is what a move there deducts.
func cost_to(point: Vector3) -> float:
	var path: Array[Vector3] = path_to(point)
	if path.is_empty():
		return INF
	return MoveCommand.path_length(start, path)


## Waypoints from the model's position to `point` (start excluded, `point` last),
## ready for MoveCommand. Empty if `point` cannot be reached.
func path_to(point: Vector3) -> Array[Vector3]:
	var target: Vector2 = Vector2(point.x, point.z)
	_resolve(target)
	if _query_path_ready:
		return _query_path.duplicate()
	var result: Array[Vector3] = []
	if _query_node == NO_NODE:
		return result
	var points: Array[Vector2] = []
	if _query_node != _DIRECT:
		var node: int = _query_node
		while node != NO_NODE:
			points.append(node_position_2d(node))
			node = _parent[node]
		points.reverse()
	else:
		points.append(_start_2d)
	if points[points.size() - 1].distance_to(target) > EPSILON:
		points.append(target)
	points = _simplify(points)
	for i: int in range(1, points.size()):
		result.append(Vector3(points[i].x, start.y, points[i].y))
	if result.is_empty():
		result.append(Vector3(target.x, start.y, target.y))
	_query_path = result
	_query_path_ready = true
	return result.duplicate()


func node_index(ix: int, iz: int) -> int:
	return iz * size_x + ix


func node_count() -> int:
	return size_x * size_z


func node_position_2d(index: int) -> Vector2:
	return origin + Vector2(index % size_x, index / size_x) * cell_size


func node_position(index: int) -> Vector3:
	var p: Vector2 = node_position_2d(index)
	return Vector3(p.x, start.y, p.y)


## Path cost to a grid node, INF if not reached by the search.
func node_cost(index: int) -> float:
	return _cost[index]


func is_node_reachable(index: int) -> bool:
	return _cost[index] <= movement_left + EPSILON


## One value per node for drawing the outline: negative inside the reachable
## area, positive outside, roughly in inches from the edge, so a contour at 0
## (e.g. marching squares) follows the edge smoothly. Where the edge is set by
## an obstacle it follows the obstacle's shape; where it is set by distance it
## follows the path cost.
func contour_values() -> PackedFloat32Array:
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(node_count())
	for i: int in node_count():
		var blocked: float = -_clearance[i]
		if blocked > EPSILON:
			values[i] = blocked
		elif _cost[i] < INF:
			values[i] = maxf(_cost[i] - movement_left, blocked)
		else:
			values[i] = cell_size
	return values


func _build_grid(state: GameState) -> void:
	var reach: float = movement_left + MARGIN_CELLS * cell_size
	var left: int = floori(minf(reach, start.x) / cell_size + EPSILON)
	var right: int = floori(minf(reach, state.table_width - start.x) / cell_size + EPSILON)
	var near: int = floori(minf(reach, start.z) / cell_size + EPSILON)
	var far: int = floori(minf(reach, state.table_depth - start.z) / cell_size + EPSILON)
	left = maxi(left, 0)
	right = maxi(right, 0)
	near = maxi(near, 0)
	far = maxi(far, 0)
	size_x = left + right + 1
	size_z = near + far + 1
	origin = _start_2d - Vector2(left, near) * cell_size
	_start_node = node_index(left, near)


func _compute_clearance() -> void:
	_clearance.resize(node_count())
	for i: int in node_count():
		_clearance[i] = _legality.clearance(node_position_2d(i))


func _search() -> void:
	var count: int = node_count()
	_cost.resize(count)
	_cost.fill(INF)
	_parent.resize(count)
	_parent.fill(NO_NODE)
	if _legality.point_result(_start_2d) != MoveLegality.Result.OK:
		return
	var limit: float = movement_left + MARGIN_CELLS * cell_size
	var step_lengths: PackedFloat64Array = PackedFloat64Array()
	for step: Vector2i in _STEPS:
		step_lengths.append(Vector2(step).length() * cell_size)

	var done: PackedByteArray = PackedByteArray()
	done.resize(count)
	_cost[_start_node] = 0.0
	_heap_push(0.0, _start_node)
	while not _heap_cost.is_empty():
		var cost: float = _heap_cost[0]
		var node: int = _heap_pop()
		if done[node] == 1 or cost > _cost[node]:
			continue
		done[node] = 1
		if cost > limit:
			break
		var ix: int = node % size_x
		var iz: int = node / size_x
		var here: Vector2 = node_position_2d(node)
		var here_clearance: float = _clearance[node]
		for s: int in _STEPS.size():
			var nx: int = ix + _STEPS[s].x
			var nz: int = iz + _STEPS[s].y
			if nx < 0 or nz < 0 or nx >= size_x or nz >= size_z:
				continue
			var next: int = nz * size_x + nx
			if done[next] == 1 or _clearance[next] < -EPSILON:
				continue
			var new_cost: float = cost + step_lengths[s]
			if new_cost >= _cost[next]:
				continue
			if not _step_is_legal(here, here_clearance, next, step_lengths[s]):
				continue
			_cost[next] = new_cost
			_parent[next] = node
			_heap_push(new_cost, next)
	_heap_cost.clear()
	_heap_node.clear()


func _step_is_legal(here: Vector2, here_clearance: float, next: int, length: float) -> bool:
	# Clearance changes by at most the distance moved, and every point of the step
	# is within half its length of one end: if both ends are clear by that much
	# the whole step is legal without testing it.
	if minf(here_clearance, _clearance[next]) >= length * 0.5:
		return true
	return _legality.segment_result(here, node_position_2d(next)) == MoveLegality.Result.OK


func _resolve(target: Vector2) -> void:
	if target == _query_point:
		return
	_query_point = target
	_query_cost = INF
	_query_node = NO_NODE
	_query_path_ready = false
	if _legality == null or _cost.is_empty() or _cost[_start_node] == INF:
		return

	var direct: float = _start_2d.distance_to(target)
	if (
		direct <= movement_left + EPSILON
		and _legality.segment_result(_start_2d, target) == MoveLegality.Result.OK
	):
		_query_cost = direct
		_query_node = _DIRECT
		return

	# Otherwise finish from one of the nearby reached nodes.
	var local: Vector2 = (target - origin) / cell_size
	var cx: int = roundi(local.x)
	var cz: int = roundi(local.y)
	var candidates: Array[Vector2] = []  # (total cost, node index)
	for dz: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var nx: int = cx + dx
			var nz: int = cz + dz
			if nx < 0 or nz < 0 or nx >= size_x or nz >= size_z:
				continue
			var node: int = nz * size_x + nx
			if not is_node_reachable(node):
				continue
			var total: float = _cost[node] + node_position_2d(node).distance_to(target)
			if total <= movement_left + EPSILON:
				candidates.append(Vector2(total, node))
	candidates.sort()
	for candidate: Vector2 in candidates:
		var node: int = int(candidate.y)
		if _legality.segment_result(node_position_2d(node), target) == MoveLegality.Result.OK:
			_query_cost = _cost[node] + node_position_2d(node).distance_to(target)
			_query_node = node
			return


## Drops every waypoint whose neighbours can be joined by a legal straight
## segment. Each drop shortens the path, so it stays within the movement.
func _simplify(points: Array[Vector2]) -> Array[Vector2]:
	var current: Array[Vector2] = points
	for _pass: int in 3:
		if current.size() <= 2:
			return current
		var kept: Array[Vector2] = [current[0]]
		for i: int in range(1, current.size() - 1):
			var anchor: Vector2 = kept[kept.size() - 1]
			if _legality.segment_result(anchor, current[i + 1]) != MoveLegality.Result.OK:
				kept.append(current[i])
		kept.append(current[current.size() - 1])
		if kept.size() == current.size():
			return kept
		current = kept
	return current


func _heap_push(cost: float, node: int) -> void:
	_heap_cost.append(cost)
	_heap_node.append(node)
	var i: int = _heap_cost.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		if _heap_cost[parent] <= cost:
			break
		_heap_cost[i] = _heap_cost[parent]
		_heap_node[i] = _heap_node[parent]
		i = parent
	_heap_cost[i] = cost
	_heap_node[i] = node


func _heap_pop() -> int:
	var top: int = _heap_node[0]
	var last: int = _heap_cost.size() - 1
	var cost: float = _heap_cost[last]
	var node: int = _heap_node[last]
	_heap_cost.resize(last)
	_heap_node.resize(last)
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
		_heap_node[i] = _heap_node[child]
		i = child
	_heap_cost[i] = cost
	_heap_node[i] = node
	return top
