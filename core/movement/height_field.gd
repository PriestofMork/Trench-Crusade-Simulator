class_name HeightField
extends RefCounted
## The table as layers of floors, built from the terrain data. See
## docs/rules/terrain.md, "Where a model can be".
##
## A *surface* is one floor: the tabletop, or the top of a piece that has a
## floor (not impassable, not steeper than the steep angle). Each is a plane over
## a convex footprint. Surfaces can lie over each other (a bridge over the
## table), so a position is a table point plus the surface it is on.
##
## A grid over the table (CELL_SIZE, the reach field's cell size) lists, for each
## cell, the surfaces that may be there; the floors at a point are then worked
## out exactly from those, so every test here is exact geometry, not sampled.
##
## Terrain only: other models and the 1" rule are added by MoveLegality.
##
## Two position tests:
## - passable(): the base centre is over the surface, the base is on the table,
##   and it does not overlap terrain higher than its floor. Moves pass through
##   these.
## - stoppable(): passable, at least half the base area is over the surface,
##   and there is headroom for the model's cylinder. Moves end on these (if no
##   other base is in the way).
##
## "Higher than its floor" is measured against the floor's own plane, so on a
## ramp the base may dip into the ramp uphill. A walkable top that rises from
## at or below the floor at the base centre (the foot of a ramp, the top of a
## ramp meeting a platform) is the floor continuing, not an obstacle.

const CELL_SIZE: float = 0.25
## Heights closer than this are the same level, inches.
const TOLERANCE: float = 0.01
## Slack for "the centre is over the surface", so a centre placed on an edge by
## a computation counts as on it.
const EDGE_SLACK: float = 0.001
const EPSILON: float = 0.0001
## Support needed to stop: half the base area.
const SUPPORT_TO_STOP: float = 0.5
## Index of the tabletop in `surfaces`.
const TABLE: int = 0


## One floor: a plane over a convex footprint.
class Surface:
	extends RefCounted
	var index: int
	## null for the tabletop.
	var piece: TerrainPiece
	var polygon: PackedVector2Array
	## The plane: height(q) = height_at_origin + gradient.dot(q).
	var height_at_origin: float
	var gradient: Vector2
	var slope_degrees: float
	var bounds_min: Vector2
	var bounds_max: Vector2
	## Height paid to stop on it if it is a low obstacle, else 0.
	var low_obstacle_height: float = 0.0

	func height_at(p: Vector2) -> float:
		return height_at_origin + gradient.dot(p)

	func piece_id() -> int:
		return -1 if piece == null else piece.id

	func is_table() -> bool:
		return piece == null


## One terrain piece as a solid.
class Solid:
	extends RefCounted
	var piece: TerrainPiece
	var polygon: PackedVector2Array
	var bottom: float
	var top_at_origin: float
	var top_gradient: Vector2
	## Whether its top is a floor.
	var walkable: bool

	func top_at(p: Vector2) -> float:
		return top_at_origin + top_gradient.dot(p)


## Where one solid is in the way of a base on one surface: the part of its
## footprint where it fills the layer just above that surface's plane.
class Obstacle:
	extends RefCounted
	var solid: Solid
	var polygon: PackedVector2Array
	## Bounding circle of the polygon, for quick rejects.
	var center: Vector2
	var reach: float
	## For a walkable top: the obstacle only counts where
	## exempt_normal.dot(p) + exempt_offset > 0 (its top is above the floor at
	## the base centre p). Elsewhere it is the floor continuing.
	var can_be_exempt: bool = false
	var exempt_normal: Vector2
	var exempt_offset: float

	func counts_at(p: Vector2) -> bool:
		return not can_be_exempt or exempt_normal.dot(p) + exempt_offset > 0.0


## A floor at a point, as listed per cell.
class Floor:
	extends RefCounted
	var surface: int
	var height: float
	var slope_degrees: float
	## -1 for the tabletop.
	var piece_id: int


var table_width: float
var table_depth: float
var surfaces: Array[Surface] = []
var solids: Array[Solid] = []
var cells_x: int
var cells_z: int

## For each surface, the obstacles for passing (the layer just above the floor).
var _passing: Array = []
## Model height -> per surface obstacles for headroom.
var _headroom_cache: Dictionary = {}
## Per cell, the surfaces whose footprint may reach it.
var _cell_surfaces: Array[PackedInt32Array] = []


func _init(state: GameState) -> void:
	table_width = state.table_width
	table_depth = state.table_depth
	var table: Surface = Surface.new()
	table.index = TABLE
	table.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(table_width, 0), Vector2(table_width, table_depth), Vector2(0, table_depth)
	])
	table.height_at_origin = 0.0
	table.gradient = Vector2.ZERO
	table.bounds_min = Vector2.ZERO
	table.bounds_max = Vector2(table_width, table_depth)
	surfaces.append(table)
	for piece: TerrainPiece in state.terrain:
		var solid: Solid = Solid.new()
		solid.piece = piece
		solid.polygon = PlanarGeometry.rect_polygon(
			piece.footprint_center, piece.footprint_half_extents(), piece.rotation
		)
		solid.bottom = piece.base_height
		solid.top_gradient = piece.top_gradient()
		solid.top_at_origin = piece.top_at_center() - solid.top_gradient.dot(piece.footprint_center)
		solid.walkable = piece.has_floor()
		solids.append(solid)
		if not solid.walkable:
			continue
		var surface: Surface = Surface.new()
		surface.index = surfaces.size()
		surface.piece = piece
		surface.polygon = solid.polygon
		surface.height_at_origin = solid.top_at_origin
		surface.gradient = solid.top_gradient
		surface.slope_degrees = piece.slope_degrees()
		surface.bounds_min = Vector2(INF, INF)
		surface.bounds_max = Vector2(-INF, -INF)
		for corner: Vector2 in solid.polygon:
			surface.bounds_min = surface.bounds_min.min(corner)
			surface.bounds_max = surface.bounds_max.max(corner)
		surfaces.append(surface)
	for surface: Surface in surfaces:
		_passing.append(_obstacles_for(surface, TOLERANCE))
		surface.low_obstacle_height = _low_obstacle_height(surface)
	_build_cells()


func surface_count() -> int:
	return surfaces.size()


func surface_height(surface: int, p: Vector2) -> float:
	return surfaces[surface].height_at(p)


## Piece id of a surface, -1 for the tabletop.
func surface_piece_id(surface: int) -> int:
	return surfaces[surface].piece_id()


## Whether the surface is the top of a low obstacle.
func is_low_obstacle(surface: int) -> bool:
	return surfaces[surface].low_obstacle_height > 0.0


## What a move ending on `surface` pays on top of its path for stopping on a
## low obstacle: its height, unless the move started on that same piece.
func stop_surcharge(surface: int, start_piece_ids: PackedInt32Array) -> float:
	var s: Surface = surfaces[surface]
	if s.low_obstacle_height <= 0.0 or start_piece_ids.has(s.piece_id()):
		return 0.0
	return s.low_obstacle_height


## The surfaces that are a floor at p: p is over the surface's footprint and
## nothing fills the layer just above it there. Lowest first.
func surfaces_at(p: Vector2) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for index: int in _candidates_at(p):
		var surface: Surface = surfaces[index]
		if PlanarGeometry.point_polygon_signed_distance(p, surface.polygon) > EDGE_SLACK:
			continue
		if _is_covered(surface, p):
			continue
		result.append(index)
	return _sorted_by_height(result, p)


## The surfaces at p whose height there is within `tolerance` of y.
func surfaces_matching(p: Vector2, y: float, tolerance: float = TOLERANCE) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for index: int in surfaces_at(p):
		if absf(surfaces[index].height_at(p) - y) <= tolerance:
			result.append(index)
	return result


## The floors at the centre of grid cell (ix, iz), lowest first.
func cell_floors(ix: int, iz: int) -> Array[Floor]:
	var p: Vector2 = Vector2((ix + 0.5) * CELL_SIZE, (iz + 0.5) * CELL_SIZE)
	var result: Array[Floor] = []
	for index: int in surfaces_at(p):
		var f: Floor = Floor.new()
		f.surface = index
		f.height = surfaces[index].height_at(p)
		f.slope_degrees = surfaces[index].slope_degrees
		f.piece_id = surfaces[index].piece_id()
		result.append(f)
	return result


## Whether a base of `radius` centred at p on `surface` may be there while moving.
func passable(p: Vector2, surface: int, radius: float) -> bool:
	if not base_on_table(p, radius):
		return false
	if PlanarGeometry.point_polygon_signed_distance(p, surfaces[surface].polygon) > EDGE_SLACK:
		return false
	return not _overlaps_any(p, radius, _passing[surface])


## Whether a model may end a move there, as far as terrain goes.
func stoppable(p: Vector2, surface: int, radius: float, model_height: float) -> bool:
	if not passable(p, surface, radius):
		return false
	if support_fraction(p, surface, radius) < SUPPORT_TO_STOP - 1e-6:
		return false
	return not _overlaps_any(p, radius, headroom_obstacles(model_height)[surface])


## Share of the base's area over the surface's footprint, 0 to 1.
func support_fraction(p: Vector2, surface: int, radius: float) -> float:
	var s: Surface = surfaces[surface]
	if s.is_table():
		return 1.0
	var d: float = PlanarGeometry.point_polygon_signed_distance(p, s.polygon)
	if d <= -radius:
		return 1.0
	if d >= radius:
		return 0.0
	return PlanarGeometry.circle_polygon_area(p, radius, s.polygon) / (PI * radius * radius)


## Whether the base may walk straight from a to b on `surface`: every point of
## the way passable. The footprint and the table are convex, so the ends decide
## those; obstacles are checked against the swept base.
func walk_clear(a: Vector2, b: Vector2, surface: int, radius: float) -> bool:
	if not base_on_table(a, radius) or not base_on_table(b, radius):
		return false
	var polygon: PackedVector2Array = surfaces[surface].polygon
	if (
		PlanarGeometry.point_polygon_signed_distance(a, polygon) > EDGE_SLACK
		or PlanarGeometry.point_polygon_signed_distance(b, polygon) > EDGE_SLACK
	):
		return false
	for obstacle: Obstacle in _passing[surface]:
		if PlanarGeometry.point_segment_distance(obstacle.center, a, b) >= obstacle.reach + radius:
			continue
		var from: Vector2 = a
		var to: Vector2 = b
		if obstacle.can_be_exempt:
			# Only the part of the segment where the obstacle counts.
			var fa: float = obstacle.exempt_normal.dot(a) + obstacle.exempt_offset
			var fb: float = obstacle.exempt_normal.dot(b) + obstacle.exempt_offset
			if fa <= 0.0 and fb <= 0.0:
				continue
			if fa <= 0.0:
				from = a.lerp(b, fa / (fa - fb))
			elif fb <= 0.0:
				to = a.lerp(b, fa / (fa - fb))
		if PlanarGeometry.segment_polygon_distance(from, to, obstacle.polygon) < radius - EPSILON:
			return false
	return true


func base_on_table(p: Vector2, radius: float) -> bool:
	return (
		p.x >= radius - EPSILON
		and p.y >= radius - EPSILON
		and p.x <= table_width - radius + EPSILON
		and p.y <= table_depth - radius + EPSILON
	)


## A lower bound on how far the base centre at p can move on `surface` and stay
## passable: it changes by at most the distance moved, so a walk whose ends both
## have clearance of at least half its length is clear. Ignores the exemption
## of walkable tops (so it may be negative where passable() is true), and is
## capped at `cap`.
func clearance(p: Vector2, surface: int, radius: float, cap: float = INF) -> float:
	var best: float = minf(cap, _table_clearance(p, radius))
	var s: Surface = surfaces[surface]
	if not s.is_table():
		best = minf(best, -PlanarGeometry.point_polygon_signed_distance(p, s.polygon))
	for obstacle: Obstacle in _passing[surface]:
		if p.distance_to(obstacle.center) - obstacle.reach - radius >= best:
			continue
		best = minf(best, PlanarGeometry.point_polygon_signed_distance(p, obstacle.polygon) - radius)
	return best


## Roughly the signed distance, in inches, from p to the edge of where a model
## may stop on `surface` (terrain only): positive where stoppable() holds. Exact
## at straight edges, including the half-area edge of a ledge; smooth enough
## elsewhere to draw an outline from.
func stand_value(p: Vector2, surface: int, radius: float, model_height: float, cap: float = INF) -> float:
	var best: float = minf(cap, _table_clearance(p, radius))
	var s: Surface = surfaces[surface]
	if not s.is_table():
		best = minf(best, _support_value(p, s, radius))
	best = minf(best, _obstacle_value(p, radius, _passing[surface], best))
	best = minf(best, _obstacle_value(p, radius, headroom_obstacles(model_height)[surface], best))
	return best


## Per surface, the obstacles for a model of this height standing there:
## anything that fills any of the space up to model_height above the floor.
func headroom_obstacles(model_height: float) -> Array:
	var key: int = roundi(model_height * 10000.0)
	if not _headroom_cache.has(key):
		var per_surface: Array = []
		for surface: Surface in surfaces:
			per_surface.append(_obstacles_for(surface, model_height))
		_headroom_cache[key] = per_surface
	return _headroom_cache[key]


## Obstacles on one surface for the layer from its plane up to `layer` above it.
func _obstacles_for(surface: Surface, layer: float) -> Array[Obstacle]:
	var result: Array[Obstacle] = []
	for solid: Solid in solids:
		if surface.piece == solid.piece:
			continue
		# Where the solid's top is more than TOLERANCE above the floor plane ...
		var top_normal: Vector2 = solid.top_gradient - surface.gradient
		var top_offset: float = solid.top_at_origin - surface.height_at_origin - TOLERANCE
		# ... and its underside is less than `layer` above it.
		var bottom_normal: Vector2 = surface.gradient
		var bottom_offset: float = surface.height_at_origin + layer - solid.bottom
		var polygon: PackedVector2Array = _clip(solid.polygon, top_normal, top_offset)
		polygon = _clip(polygon, bottom_normal, bottom_offset)
		if polygon.is_empty():
			continue
		var obstacle: Obstacle = Obstacle.new()
		obstacle.solid = solid
		obstacle.polygon = polygon
		var centre: Vector2 = Vector2.ZERO
		for corner: Vector2 in polygon:
			centre += corner
		centre /= polygon.size()
		obstacle.center = centre
		obstacle.reach = 0.0
		for corner: Vector2 in polygon:
			obstacle.reach = maxf(obstacle.reach, centre.distance_to(corner))
		if solid.walkable and top_normal.length_squared() > 1e-12:
			obstacle.can_be_exempt = true
			obstacle.exempt_normal = top_normal
			obstacle.exempt_offset = top_offset
		result.append(obstacle)
	return result


## A low obstacle is a box no higher than the low obstacle height standing on
## a floor (the table or the top of another piece), so a thin floating deck is
## not one. Returns its height, or 0.
func _low_obstacle_height(surface: Surface) -> float:
	var piece: TerrainPiece = surface.piece
	if piece == null or piece.shape != TerrainPiece.Shape.BOX:
		return 0.0
	if piece.height > TerrainRules.LOW_OBSTACLE_HEIGHT + Transitions.HEIGHT_SLACK:
		return 0.0
	if piece.base_height <= TOLERANCE:
		return piece.height
	for solid: Solid in solids:
		if solid.piece == piece:
			continue
		if (
			absf(solid.top_at(piece.footprint_center) - piece.base_height) <= TOLERANCE
			and PlanarGeometry.point_polygon_signed_distance(piece.footprint_center, solid.polygon) <= 0.0
		):
			return piece.height
	return 0.0


## clip_polygon(), with a constant half-plane handled exactly.
static func _clip(polygon: PackedVector2Array, normal: Vector2, offset: float) -> PackedVector2Array:
	if normal.length_squared() <= 1e-12:
		return polygon if offset > 0.0 else PackedVector2Array()
	return PlanarGeometry.clip_polygon(polygon, normal, offset)


func _overlaps_any(p: Vector2, radius: float, obstacles: Array) -> bool:
	for obstacle: Obstacle in obstacles:
		if p.distance_to(obstacle.center) >= obstacle.reach + radius:
			continue
		if not obstacle.counts_at(p):
			continue
		if PlanarGeometry.point_polygon_signed_distance(p, obstacle.polygon) < radius - EPSILON:
			return true
	return false


func _obstacle_value(p: Vector2, radius: float, obstacles: Array, cap: float) -> float:
	var best: float = cap
	for obstacle: Obstacle in obstacles:
		if p.distance_to(obstacle.center) - obstacle.reach - radius >= best:
			continue
		if not obstacle.counts_at(p):
			continue
		best = minf(best, PlanarGeometry.point_polygon_signed_distance(p, obstacle.polygon) - radius)
	return best


func _table_clearance(p: Vector2, radius: float) -> float:
	return minf(
		minf(p.x - radius, table_width - radius - p.x), minf(p.y - radius, table_depth - radius - p.y)
	)


## The support test as a distance: how far a straight edge would be inside the
## base for the same supported share (0 at exactly half), so it matches the
## distance to the edge where the edge is straight.
func _support_value(p: Vector2, s: Surface, radius: float) -> float:
	var d: float = -PlanarGeometry.point_polygon_signed_distance(p, s.polygon)
	if d >= radius or d <= -radius:
		return d
	var fraction: float = PlanarGeometry.circle_polygon_area(p, radius, s.polygon) / (PI * radius * radius)
	return _straight_edge_offset(fraction, radius)


## Inverse of the share of a circle on the inner side of a straight line at
## signed distance d from its centre.
static func _straight_edge_offset(fraction: float, radius: float) -> float:
	var low: float = -radius
	var high: float = radius
	for _i: int in 30:
		var middle: float = (low + high) * 0.5
		var t: float = middle / radius
		var share: float = 0.5 + (t * sqrt(maxf(1.0 - t * t, 0.0)) + asin(t)) / PI
		if share < fraction:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


func _is_covered(surface: Surface, p: Vector2) -> bool:
	var h: float = surface.height_at(p)
	for solid: Solid in solids:
		if solid.piece == surface.piece:
			continue
		if solid.bottom > h + TOLERANCE or solid.top_at(p) <= h + TOLERANCE:
			continue
		if PlanarGeometry.point_polygon_signed_distance(p, solid.polygon) < -EPSILON:
			return true
	return false


func _build_cells() -> void:
	cells_x = maxi(ceili(table_width / CELL_SIZE), 1)
	cells_z = maxi(ceili(table_depth / CELL_SIZE), 1)
	_cell_surfaces.resize(cells_x * cells_z)
	var everywhere: PackedInt32Array = PackedInt32Array([TABLE])
	for k: int in _cell_surfaces.size():
		_cell_surfaces[k] = everywhere.duplicate()
	for surface: Surface in surfaces:
		if surface.is_table():
			continue
		var slack: float = EDGE_SLACK + EPSILON
		var x_from: int = clampi(floori((surface.bounds_min.x - slack) / CELL_SIZE), 0, cells_x - 1)
		var x_to: int = clampi(floori((surface.bounds_max.x + slack) / CELL_SIZE), 0, cells_x - 1)
		var z_from: int = clampi(floori((surface.bounds_min.y - slack) / CELL_SIZE), 0, cells_z - 1)
		var z_to: int = clampi(floori((surface.bounds_max.y + slack) / CELL_SIZE), 0, cells_z - 1)
		for iz: int in range(z_from, z_to + 1):
			for ix: int in range(x_from, x_to + 1):
				_cell_surfaces[iz * cells_x + ix].append(surface.index)


func _candidates_at(p: Vector2) -> PackedInt32Array:
	var ix: int = clampi(floori(p.x / CELL_SIZE), 0, cells_x - 1)
	var iz: int = clampi(floori(p.y / CELL_SIZE), 0, cells_z - 1)
	return _cell_surfaces[iz * cells_x + ix]


func _sorted_by_height(indices: PackedInt32Array, p: Vector2) -> PackedInt32Array:
	if indices.size() < 2:
		return indices
	var pairs: Array[Vector2] = []
	for index: int in indices:
		pairs.append(Vector2(surfaces[index].height_at(p), index))
	pairs.sort()
	var result: PackedInt32Array = PackedInt32Array()
	for pair: Vector2 in pairs:
		result.append(int(pair.y))
	return result
