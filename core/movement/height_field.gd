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
## The floor is the whole level surface, not one piece (terrain.md, "Where the
## move ends"). Two surfaces *join* where their footprints meet and their
## heights there agree within TOLERANCE (a row of sandbags, a platform made of
## boxes, a ramp meeting a platform at its top, a ramp's foot and the table).
## Joined surfaces in the same plane form a *level group*: walks cross between
## them as if they were one surface, and they are one obstacle for the low
## obstacle surcharge. Support counts the area over the model's level group and
## over the floors directly joined to it near the seam; lower ground never counts.
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
## Point queries only look at terrain within this of the query's grid cell.
## It covers the largest base radius plus NEAR_CAP, so values from
## clearance(), stand_value() and visible_value() are exact up to NEAR_CAP.
const NEAR_DISTANCE: float = 3.6
const NEAR_CAP: float = 2.0
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
	var shape: ConvexShape
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
	var shape: ConvexShape
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
	var solid_index: int
	var polygon: PackedVector2Array
	var shape: ConvexShape
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

## For each surface, the obstacles for passing (the layer just above the
## floor), as an array indexed by solid (null where the solid is not in the way).
var _passing: Array = []
## Model height -> per surface obstacles for headroom.
var _headroom_cache: Dictionary = {}
## Per surface, the surfaces it joins.
var _joins: Array[PackedInt32Array] = []
## Per surface, its level group (an index into _group_members).
var _level_group: PackedInt32Array = PackedInt32Array()
var _group_members: Array[PackedInt32Array] = []
## Per surface, the floor that supports a base there, as non-overlapping convex shapes.
var _support_shapes: Array = []
## Per level group, its outline without the seams (see _build_group_outlines()).
var _group_outlines: Array[PackedVector2Array] = []
## (a * surface count + b) -> where surfaces a and b join.
var _join_regions: Dictionary[int, PackedVector2Array] = {}
## Piece id -> surface index.
var _surface_of_piece: Dictionary[int, int] = {}
## How far around a seam a joined floor of another plane counts as support:
## more than the largest base radius.
const SUPPORT_REACH: float = 1.5

## Per cell, the surfaces and the solids whose footprint may reach it.
var _cell_surfaces: Array[PackedInt32Array] = []
var _cell_solids: Array[PackedInt32Array] = []
## Per cell, the solids within NEAR_DISTANCE of it.
var _near_solids: Array[PackedInt32Array] = []


func _init(state: GameState) -> void:
	table_width = state.table_width
	table_depth = state.table_depth
	var table: Surface = Surface.new()
	table.index = TABLE
	table.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(table_width, 0), Vector2(table_width, table_depth), Vector2(0, table_depth)
	])
	table.shape = ConvexShape.from_polygon(table.polygon)
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
		solid.shape = ConvexShape.from_polygon(solid.polygon)
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
		surface.shape = solid.shape
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
		_surface_of_piece[surface.piece_id()] = surface.index
	_build_joins()
	_build_group_outlines()
	for surface: Surface in surfaces:
		_support_shapes.append(_build_support(surface.index))
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
## Adjoining low obstacles of the same height (a row of sandbags) are one
## obstacle: starting on any of them waives it.
func stop_surcharge(surface: int, start_piece_ids: PackedInt32Array) -> float:
	var s: Surface = surfaces[surface]
	if s.low_obstacle_height <= 0.0:
		return 0.0
	for piece_id: int in start_piece_ids:
		if _surface_of_piece.has(piece_id) and same_level(_surface_of_piece[piece_id], surface):
			return 0.0
	return s.low_obstacle_height


## Whether two surfaces are in one level group (joined, in the same plane).
func same_level(a: int, b: int) -> bool:
	return _level_group[a] == _level_group[b]


## The surfaces in a surface's level group (itself included).
func level_members(surface: int) -> PackedInt32Array:
	return _group_members[_level_group[surface]]


## The surfaces a surface joins.
func joined_surfaces(surface: int) -> PackedInt32Array:
	return _joins[surface]


## The surfaces that are a floor at p: p is over the surface's footprint and
## nothing fills the layer just above it there. Lowest first.
func surfaces_at(p: Vector2) -> PackedInt32Array:
	var cell: int = _cell_at(p)
	var candidates: PackedInt32Array = _cell_surfaces[cell]
	var result: PackedInt32Array = PackedInt32Array()
	if _cell_solids[cell].is_empty():
		# Only the tabletop near here, with nothing on it.
		if (
			p.x >= -EDGE_SLACK and p.y >= -EDGE_SLACK
			and p.x <= table_width + EDGE_SLACK and p.y <= table_depth + EDGE_SLACK
		):
			result.append(TABLE)
		return result
	for index: int in candidates:
		var surface: Surface = surfaces[index]
		if surface.shape.signed_distance(p) > EDGE_SLACK:
			continue
		if _is_covered(surface, p):
			continue
		result.append(index)
	return _sorted_by_height(result, p)


## Whether `surface` is a floor at p (the same test as surfaces_at()).
func is_floor(p: Vector2, surface: int) -> bool:
	var s: Surface = surfaces[surface]
	if s.shape.signed_distance(p) > EDGE_SLACK:
		return false
	return not _is_covered(s, p)


## Signed distance from p to the part of `surface` that can be seen from above
## nearby: its footprint, less where terrain fills the layer above it. Positive
## outside. For clipping what is drawn on the surface. Values below -cap may
## be returned as -cap.
func visible_value(p: Vector2, surface: int, cap: float = NEAR_CAP) -> float:
	cap = minf(cap, NEAR_CAP)
	var best: float = maxf(surfaces[surface].shape.signed_distance(p), -cap)
	return _uncovered(p, surface, best)


## visible_value() for a whole level surface: its pieces together, so the
## seams between them are inside, not edges.
func level_visible_value(p: Vector2, surface: int, cap: float = NEAR_CAP) -> float:
	cap = minf(cap, NEAR_CAP)
	var members: PackedInt32Array = level_members(surface)
	if members.size() == 1:
		return visible_value(p, surface, cap)
	var inside: bool = false
	var outside: float = INF
	for member: int in members:
		var d: float = surfaces[member].shape.signed_distance(p)
		if d <= 0.0:
			inside = true
		outside = minf(outside, d)
	var best: float = outside
	if inside:
		# Distance to the outline of the whole surface, seams left out.
		best = -cap
		var outline: PackedVector2Array = _group_outlines[_level_group[surface]]
		for k: int in range(0, outline.size(), 2):
			best = maxf(best, -PlanarGeometry.point_segment_distance(p, outline[k], outline[k + 1]))
	best = maxf(best, -cap)
	for member: int in members:
		best = _uncovered(p, member, best)
	return best


## Raises `best` to positive inside terrain that covers `surface` at p.
func _uncovered(p: Vector2, surface: int, best: float) -> float:
	var by_solid: Array = _passing[surface]
	for index: int in _near_solids[_cell_at(p)]:
		var obstacle: Obstacle = by_solid[index]
		if obstacle == null or p.distance_to(obstacle.center) - obstacle.reach >= -best:
			continue
		best = maxf(best, -obstacle.shape.signed_distance(p))
	return best


## For each level group, the edges of its pieces that are not shared with
## another piece of the group, as pairs of points.
func _build_group_outlines() -> void:
	for members: PackedInt32Array in _group_members:
		var outline: PackedVector2Array = PackedVector2Array()
		for member: int in members:
			var polygon: PackedVector2Array = surfaces[member].polygon
			for i: int in polygon.size():
				var a: Vector2 = polygon[i]
				var b: Vector2 = polygon[(i + 1) % polygon.size()]
				# Cut out the parts of the edge that lie on another piece.
				var keep: Array[Vector2] = [Vector2(0, 1)]
				for other: int in members:
					if other == member:
						continue
					var grown: PackedVector2Array = _grown(surfaces[other].polygon, EDGE_SLACK * 2.0)
					var span: Vector2 = PlanarGeometry.segment_polygon_clip(a, b, grown)
					if span.x > span.y:
						continue
					var next: Array[Vector2] = []
					for piece: Vector2 in keep:
						if span.x > piece.x:
							next.append(Vector2(piece.x, minf(span.x, piece.y)))
						if span.y < piece.y:
							next.append(Vector2(maxf(span.y, piece.x), piece.y))
					keep = next
				for piece: Vector2 in keep:
					if piece.y - piece.x > 1e-6:
						outline.append(a.lerp(b, piece.x))
						outline.append(a.lerp(b, piece.y))
		_group_outlines.append(outline)


## A convex polygon pushed out by `distance` along its edge normals.
static func _grown(polygon: PackedVector2Array, distance: float) -> PackedVector2Array:
	var centre: Vector2 = Vector2.ZERO
	for corner: Vector2 in polygon:
		centre += corner
	centre /= polygon.size()
	var result: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in polygon:
		result.append(corner + (corner - centre).normalized() * distance * 1.5)
	return result


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
	if (
		surface != TABLE
		and surfaces[surface].shape.signed_distance(p) > EDGE_SLACK
	):
		return false
	return not _overlaps_any(p, radius, _passing[surface])


## Whether a model may end a move there, as far as terrain goes.
func stoppable(p: Vector2, surface: int, radius: float, model_height: float) -> bool:
	return passable(p, surface, radius) and supported_with_headroom(p, surface, radius, model_height)


## The part of stoppable() that passable() does not cover: half the base area
## supported, and headroom.
func supported_with_headroom(p: Vector2, surface: int, radius: float, model_height: float) -> bool:
	if support_fraction(p, surface, radius) < SUPPORT_TO_STOP - 1e-6:
		return false
	return headroom_clear(p, surface, radius, headroom_obstacles(model_height))


## Whether the base at p on `surface` is clear of `per_surface` obstacles (from
## headroom_obstacles()).
func headroom_clear(p: Vector2, surface: int, radius: float, per_surface: Array) -> bool:
	return not _overlaps_any(p, radius, per_surface[surface])


## Share of the base's area over the surface's footprint, 0 to 1.
func support_fraction(p: Vector2, surface: int, radius: float) -> float:
	var s: Surface = surfaces[surface]
	if s.is_table():
		return 1.0
	if s.shape.signed_distance(p) <= -radius:
		return 1.0
	var total: float = 0.0
	for shape: ConvexShape in _support_shapes[surface]:
		if p.distance_to(shape.bound_center) >= shape.bound_radius + radius:
			continue
		total += PlanarGeometry.circle_polygon_area(p, radius, shape.polygon)
	return minf(total / (PI * radius * radius), 1.0)


## Whether the base may walk straight from a to b on `surface`: every point of
## the way passable. The footprint and the table are convex, so the ends decide
## those; obstacles are checked against the swept base.
func walk_clear(a: Vector2, b: Vector2, surface: int, radius: float) -> bool:
	if not base_on_table(a, radius) or not base_on_table(b, radius):
		return false
	if surface != TABLE:
		var shape: ConvexShape = surfaces[surface].shape
		if shape.signed_distance(a) > EDGE_SLACK or shape.signed_distance(b) > EDGE_SLACK:
			return false
	var ab: Vector2 = b - a
	var ab_length_sq: float = ab.length_squared()
	for obstacle: Obstacle in _passing[surface]:
		if obstacle == null:
			continue
		# Quick reject: the obstacle's bounding circle is out of reach of the segment.
		var t: float = 0.0
		if ab_length_sq > 0.0:
			t = clampf((obstacle.center - a).dot(ab) / ab_length_sq, 0.0, 1.0)
		var limit: float = obstacle.reach + radius
		if obstacle.center.distance_squared_to(a + ab * t) >= limit * limit:
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
		if obstacle.shape.segment_distance(from, to) < radius - EPSILON:
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
func clearance(p: Vector2, surface: int, radius: float, cap: float = NEAR_CAP) -> float:
	var best: float = minf(minf(cap, NEAR_CAP), _table_clearance(p, radius))
	var s: Surface = surfaces[surface]
	if not s.is_table():
		best = minf(best, -s.shape.signed_distance(p))
	var by_solid: Array = _passing[surface]
	for index: int in _near_solids[_cell_at(p)]:
		var obstacle: Obstacle = by_solid[index]
		if obstacle == null or p.distance_to(obstacle.center) - obstacle.reach - radius >= best:
			continue
		best = minf(best, obstacle.shape.signed_distance(p) - radius)
	return best


## Roughly the signed distance, in inches, from p to the edge of where a model
## may stop on `surface` (terrain only): positive where stoppable() holds. Exact
## at straight edges, including the half-area edge of a ledge; smooth enough
## elsewhere to draw an outline from.
func stand_value(p: Vector2, surface: int, radius: float, model_height: float, cap: float = NEAR_CAP) -> float:
	var best: float = minf(minf(cap, NEAR_CAP), _table_clearance(p, radius))
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
func _obstacles_for(surface: Surface, layer: float) -> Array:
	var result: Array = []
	result.resize(solids.size())
	for solid_index: int in solids.size():
		var solid: Solid = solids[solid_index]
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
		obstacle.solid_index = solid_index
		obstacle.polygon = polygon
		obstacle.shape = ConvexShape.from_polygon(polygon)
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
		result[solid_index] = obstacle
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
			and solid.shape.signed_distance(piece.footprint_center) <= 0.0
		):
			return piece.height
	return 0.0


## clip_polygon(), with a constant half-plane handled exactly.
static func _clip(polygon: PackedVector2Array, normal: Vector2, offset: float) -> PackedVector2Array:
	if normal.length_squared() <= 1e-12:
		return polygon if offset > 0.0 else PackedVector2Array()
	return PlanarGeometry.clip_polygon(polygon, normal, offset)


func _overlaps_any(p: Vector2, radius: float, by_solid: Array) -> bool:
	for index: int in _near_solids[_cell_at(p)]:
		var obstacle: Obstacle = by_solid[index]
		if obstacle == null or p.distance_to(obstacle.center) >= obstacle.reach + radius:
			continue
		if not obstacle.counts_at(p):
			continue
		if obstacle.shape.signed_distance(p) < radius - EPSILON:
			return true
	return false


func _obstacle_value(p: Vector2, radius: float, by_solid: Array, cap: float) -> float:
	var best: float = cap
	for index: int in _near_solids[_cell_at(p)]:
		var obstacle: Obstacle = by_solid[index]
		if obstacle == null or p.distance_to(obstacle.center) - obstacle.reach - radius >= best:
			continue
		if not obstacle.counts_at(p):
			continue
		best = minf(best, obstacle.shape.signed_distance(p) - radius)
	return best


func _table_clearance(p: Vector2, radius: float) -> float:
	return minf(
		minf(p.x - radius, table_width - radius - p.x), minf(p.y - radius, table_depth - radius - p.y)
	)


## The support test as a distance: how far a straight edge would be inside the
## base for the same supported share (0 at exactly half), so it matches the
## distance to the edge where the edge is straight.
func _support_value(p: Vector2, s: Surface, radius: float) -> float:
	var d: float = -s.shape.signed_distance(p)
	if d >= radius:
		return d
	var fraction: float = support_fraction(p, s.index, radius)
	if fraction >= 1.0 - 1e-9:
		return radius
	if fraction <= 0.0:
		return minf(d, -radius)
	return _straight_edge_offset(fraction, radius)


func _build_joins() -> void:
	var n: int = surfaces.size()
	_joins.resize(n)
	var join_regions: Dictionary[int, PackedVector2Array] = {}
	for a: int in n:
		for b: int in range(a + 1, n):
			var region: PackedVector2Array = _join_region(surfaces[a], surfaces[b])
			if region.is_empty():
				continue
			_joins[a].append(b)
			_joins[b].append(a)
			join_regions[a * n + b] = region
			join_regions[b * n + a] = region
	# Level groups: joins between surfaces in the same plane, closed over.
	_level_group.resize(n)
	_level_group.fill(-1)
	for start: int in n:
		if _level_group[start] != -1:
			continue
		var group: int = _group_members.size()
		var members: PackedInt32Array = PackedInt32Array([start])
		_level_group[start] = group
		var k: int = 0
		while k < members.size():
			for other: int in _joins[members[k]]:
				if _level_group[other] == -1 and _coplanar(surfaces[members[k]], surfaces[other]):
					_level_group[other] = group
					members.append(other)
			k += 1
		_group_members.append(members)
	_join_regions = join_regions


## Where two surfaces' footprints meet (within the edge slack) at heights
## within TOLERANCE of each other; empty if they do not join.
func _join_region(a: Surface, b: Surface) -> PackedVector2Array:
	var region: PackedVector2Array = a.polygon
	var orientation: float = signf(PlanarGeometry.polygon_double_area(b.polygon))
	var count: int = b.polygon.size()
	for i: int in count:
		var p0: Vector2 = b.polygon[i]
		var edge: Vector2 = b.polygon[(i + 1) % count] - p0
		var inward: Vector2 = Vector2(-edge.y, edge.x).normalized() * orientation
		region = PlanarGeometry.clip_polygon(region, inward, -inward.dot(p0) + EDGE_SLACK * 2.0)
		if region.is_empty():
			return region
	# |height_a - height_b| <= TOLERANCE, as two half-planes.
	var dg: Vector2 = a.gradient - b.gradient
	var dh: float = a.height_at_origin - b.height_at_origin
	region = _clip(region, -dg, TOLERANCE - dh)
	region = _clip(region, dg, TOLERANCE + dh)
	return region


static func _coplanar(a: Surface, b: Surface) -> bool:
	return a.gradient.is_equal_approx(b.gradient) and absf(a.height_at_origin - b.height_at_origin) <= TOLERANCE


## The floor under a base on `surface`, as non-overlapping convex pieces: the
## surface, the rest of its level group, and, near each seam, the floors of
## another plane joined to them (less where terrain covers those).
func _build_support(surface: int) -> Array:
	var pieces: Array[PackedVector2Array] = []
	var members: PackedInt32Array = level_members(surface)
	_add_disjoint(pieces, surfaces[surface].polygon)
	for member: int in members:
		if member != surface:
			_add_disjoint(pieces, surfaces[member].polygon)
	var n: int = surfaces.size()
	for member: int in members:
		for other: int in _joins[member]:
			if members.has(other):
				continue
			var near: PackedVector2Array = _around(_join_regions[member * n + other], SUPPORT_REACH)
			var part: PackedVector2Array = _clip_by_box(surfaces[other].polygon, near)
			if part.size() < 3:
				continue
			var parts: Array[PackedVector2Array] = [part]
			for obstacle: Obstacle in _passing[other]:
				if obstacle == null:
					continue
				var next: Array[PackedVector2Array] = []
				for piece: PackedVector2Array in parts:
					next.append_array(_subtract(piece, obstacle.polygon))
				parts = next
			for piece: PackedVector2Array in parts:
				_add_disjoint(pieces, piece)
	var shapes: Array = []
	for piece: PackedVector2Array in pieces:
		shapes.append(ConvexShape.from_polygon(piece))
	return shapes


## Adds the part of `polygon` not already in `pieces`, as convex pieces.
static func _add_disjoint(pieces: Array[PackedVector2Array], polygon: PackedVector2Array) -> void:
	var rest: Array[PackedVector2Array] = [polygon]
	for existing: PackedVector2Array in pieces:
		var next: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in rest:
			next.append_array(_subtract(piece, existing))
		rest = next
	for piece: PackedVector2Array in rest:
		if absf(PlanarGeometry.polygon_double_area(piece)) > 1e-9:
			pieces.append(piece)


## Convex p minus convex q, as convex pieces.
static func _subtract(p: PackedVector2Array, q: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if q.size() < 3 or absf(PlanarGeometry.polygon_double_area(q)) <= 1e-12:
		result.append(p)
		return result
	var orientation: float = signf(PlanarGeometry.polygon_double_area(q))
	var rest: PackedVector2Array = p
	var count: int = q.size()
	for i: int in count:
		var p0: Vector2 = q[i]
		var edge: Vector2 = q[(i + 1) % count] - p0
		var outward: Vector2 = Vector2(edge.y, -edge.x).normalized() * orientation
		var outside: PackedVector2Array = PlanarGeometry.clip_polygon(rest, outward, -outward.dot(p0))
		if outside.size() >= 3 and absf(PlanarGeometry.polygon_double_area(outside)) > 1e-12:
			result.append(outside)
		rest = PlanarGeometry.clip_polygon(rest, -outward, outward.dot(p0))
		if rest.size() < 3:
			break
	return result


## Bounding box of a polygon grown by `grow`, as [min, max].
static func _around(polygon: PackedVector2Array, grow: float) -> PackedVector2Array:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for corner: Vector2 in polygon:
		low = low.min(corner)
		high = high.max(corner)
	return PackedVector2Array([low - Vector2(grow, grow), high + Vector2(grow, grow)])


static func _clip_by_box(polygon: PackedVector2Array, box: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = PlanarGeometry.clip_polygon(polygon, Vector2(1, 0), -box[0].x)
	result = PlanarGeometry.clip_polygon(result, Vector2(-1, 0), box[1].x)
	result = PlanarGeometry.clip_polygon(result, Vector2(0, 1), -box[0].y)
	return PlanarGeometry.clip_polygon(result, Vector2(0, -1), box[1].y)


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
	for index: int in _cell_solids[_cell_at(p)]:
		var solid: Solid = solids[index]
		if solid.piece == surface.piece:
			continue
		if solid.bottom > h + TOLERANCE or solid.top_at(p) <= h + TOLERANCE:
			continue
		if solid.shape.signed_distance(p) < -EPSILON:
			return true
	return false


func _build_cells() -> void:
	cells_x = maxi(ceili(table_width / CELL_SIZE), 1)
	cells_z = maxi(ceili(table_depth / CELL_SIZE), 1)
	_cell_surfaces.resize(cells_x * cells_z)
	_cell_solids.resize(cells_x * cells_z)
	_near_solids.resize(cells_x * cells_z)
	var everywhere: PackedInt32Array = PackedInt32Array([TABLE])
	for k: int in _cell_surfaces.size():
		_cell_surfaces[k] = everywhere.duplicate()
	for surface: Surface in surfaces:
		if surface.is_table():
			continue
		for cell: int in _cells_over(surface.polygon):
			_cell_surfaces[cell].append(surface.index)
	for index: int in solids.size():
		for cell: int in _cells_over(solids[index].polygon):
			_cell_solids[cell].append(index)
		for cell: int in _cells_over(solids[index].polygon, NEAR_DISTANCE):
			_near_solids[cell].append(index)


## The cells a polygon's bounding box (plus the edge slack) touches.
func _cells_over(polygon: PackedVector2Array, grow: float = 0.0) -> PackedInt32Array:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for corner: Vector2 in polygon:
		low = low.min(corner)
		high = high.max(corner)
	var slack: float = EDGE_SLACK + EPSILON + grow
	var x_from: int = clampi(floori((low.x - slack) / CELL_SIZE), 0, cells_x - 1)
	var x_to: int = clampi(floori((high.x + slack) / CELL_SIZE), 0, cells_x - 1)
	var z_from: int = clampi(floori((low.y - slack) / CELL_SIZE), 0, cells_z - 1)
	var z_to: int = clampi(floori((high.y + slack) / CELL_SIZE), 0, cells_z - 1)
	var result: PackedInt32Array = PackedInt32Array()
	for iz: int in range(z_from, z_to + 1):
		for ix: int in range(x_from, x_to + 1):
			result.append(iz * cells_x + ix)
	return result


func _cell_at(p: Vector2) -> int:
	var ix: int = clampi(floori(p.x / CELL_SIZE), 0, cells_x - 1)
	var iz: int = clampi(floori(p.y / CELL_SIZE), 0, cells_z - 1)
	return iz * cells_x + ix


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
