class_name MoveLegality
extends RefCounted
## Where one model's base may be, and how it may get from one point to the
## next, across the floors of the height field. Built once from the state for
## the moving model; shared by MoveCommand (which validates paths) and ReachField
## (which finds them), so the two always agree: ReachField only ever builds a
## path from steps this class accepts, and MoveCommand checks a path with
## segment_cost() and stop_surcharge() from here.
##
## A position is a table point (Vector2: world x, z) plus a surface of the
## HeightField; its height is the surface's height there. Waypoints are 3D
## points, matched to the surfaces whose height there is within
## HeightField.TOLERANCE.
##
## A path is a list of segments, each either
## - a walk: both ends on one surface, the base passable all along it; it
##   costs its length along the surface (3D); or
## - a wall crossing: from a point where the base touches a wall to the point
##   on top directly above the touch point (going up), or the reverse (going
##   down). It costs what Transitions says for that wall; or
## - a gap jump: from a point on the ledge of one surface (the base centre on
##   its edge) straight across to the ledge of another, with no floor between
##   them at the level of the lower ledge. It costs the gap's width, plus the
##   rise if the far side is higher, and that total must be within the jump
##   limit (ruling 5 of brief 006: half the model's Movement, halved again
##   after standing up).
## Crossings that need a roll (Transitions) are allowed unless allow_rolls is
## false; where a segment can be read several ways, the one with the fewest
## rolls is taken, then the cheapest.
## Changing between two surfaces at the same height needs no segment of its
## own: one walk ends on the first and the next starts on the second.
##
## Models: friendly bases may be passed through but not stood on; no point of
## the way may come within 1" of an enemy, measured in 3D between the two
## cylinders (so a model on a bridge is not held back by an enemy far below).
## Touching is allowed; overlapping is not. Exactly 1" from an enemy is allowed.

enum Result {
	OK, OFF_TABLE, TERRAIN, MODEL, ENEMY, NO_FLOOR, NOT_SUPPORTED, HEADROOM, NEEDS_ROLL, NO_WAY, TOO_WIDE
}

const EPSILON: float = 0.0001
## A model may only come within this distance of an enemy (edge to edge) by charging.
const ENEMY_DISTANCE_INCHES: float = 1.0
## How exactly a wall crossing must start at the touch point and end above it.
const TOUCH_SLACK: float = 0.002
## A jump must cross at least this much gap (less is a seam between floors).
const MIN_GAP: float = 0.05
## How far from where a model falls or fails the closest place to stop is looked for.
const STOP_SEARCH_DISTANCE: float = 12.0
const STOP_RING_STEP: float = 0.05

## Radius of the moving model's base, inches.
var radius: float
## Height of its cylinder, inches.
var model_height: float
var field: HeightField
## The model's position, and the surfaces it stands on there.
var start: Vector3
var start_surfaces: PackedInt32Array
## Pieces the model starts on (-1 for the table), for the low obstacle surcharge.
var start_piece_ids: PackedInt32Array = PackedInt32Array()

## Whether crossings that need a roll may be used.
var allow_rolls: bool = true
## The widest gap (plus any rise) the model may jump, inches.
var jump_limit: float = 0.0

## Why the last check failed, and the kind of the last segment that passed,
## with how far it came down or went up and, for a jump, the gap.
var last_result: Result = Result.OK
var last_kind: Transitions.Kind = Transitions.Kind.NONE
var last_drop: float = 0.0
var last_rise: float = 0.0
var last_gap: float = 0.0
var last_fall_point: Vector3 = Vector3.ZERO
var last_rolls: int = 0

## Per surface, the terrain in the way of this model's cylinder when standing.
var _headroom: Array = []
var _enemy_centres: PackedVector2Array = PackedVector2Array()
var _enemy_bottoms: PackedFloat64Array = PackedFloat64Array()
var _enemy_tops: PackedFloat64Array = PackedFloat64Array()
var _enemy_radii: PackedFloat64Array = PackedFloat64Array()
var _friend_centres: PackedVector2Array = PackedVector2Array()
var _friend_bottoms: PackedFloat64Array = PackedFloat64Array()
var _friend_tops: PackedFloat64Array = PackedFloat64Array()
var _friend_radii: PackedFloat64Array = PackedFloat64Array()


func _init(state: GameState, model: ModelState, p_field: HeightField = null) -> void:
	radius = model.base_radius_inches()
	model_height = model.height_inches()
	field = p_field if p_field != null else state.height_field()
	_headroom = field.headroom_obstacles(model_height)
	jump_limit = TurnFlow.movement_budget(state, model) * 0.5
	start = model.position
	start_surfaces = surfaces_at(start)
	for s: int in start_surfaces:
		start_piece_ids.append(field.surface_piece_id(s))
	for other: ModelState in state.models:
		if other.id == model.id or not other.on_table():
			continue
		var centre: Vector2 = Vector2(other.position.x, other.position.z)
		if other.player != model.player:
			_enemy_centres.append(centre)
			_enemy_bottoms.append(other.position.y)
			_enemy_tops.append(other.position.y + other.height_inches())
			_enemy_radii.append(other.base_radius_inches())
		else:
			_friend_centres.append(centre)
			_friend_bottoms.append(other.position.y)
			_friend_tops.append(other.position.y + other.height_inches())
			_friend_radii.append(other.base_radius_inches())


## The surfaces a 3D point is on (lowest first).
func surfaces_at(p: Vector3) -> PackedInt32Array:
	return field.surfaces_matching(Vector2(p.x, p.z), p.y, HeightField.TOLERANCE)


## The point on `surface` above or below the table point p.
func on_surface(p: Vector2, surface: int) -> Vector3:
	return Vector3(p.x, field.surface_height(surface, p), p.y)


## Whether the base may be at p on `surface` while moving (friendly bases ignored).
func passing_result(p: Vector2, surface: int) -> Result:
	var y: float = field.surface_height(surface, p)
	if field.passable(p, surface, radius) and _enemies_clear(p, p, y, y):
		return Result.OK
	if not field.base_on_table(p, radius):
		return Result.OFF_TABLE
	if field.surfaces[surface].shape.signed_distance(p) > HeightField.EDGE_SLACK:
		return Result.NO_FLOOR
	if not field.passable(p, surface, radius):
		return Result.TERRAIN
	return Result.ENEMY


## Whether a move may end with the base centre at p on `surface`.
func point_result(p: Vector2, surface: int) -> Result:
	var result: Result = passing_result(p, surface)
	if result != Result.OK:
		return result
	return stop_result_if_passing(p, surface)


## point_result() for a position already known to pass passing_result().
func stop_result_if_passing(p: Vector2, surface: int) -> Result:
	if field.support_fraction(p, surface, radius) < HeightField.SUPPORT_TO_STOP - 1e-6:
		return Result.NOT_SUPPORTED
	if not field.headroom_clear(p, surface, radius, _headroom):
		return Result.HEADROOM
	var y: float = field.surface_height(surface, p)
	for i: int in _friend_centres.size():
		if p.distance_to(_friend_centres[i]) >= radius + _friend_radii[i] - EPSILON:
			continue
		if y < _friend_tops[i] - EPSILON and _friend_bottoms[i] < y + model_height - EPSILON:
			return Result.MODEL
	return Result.OK


## Whether the base may walk straight from a to b on `surface`.
func walk_result(a: Vector2, b: Vector2, surface: int) -> Result:
	if field.walk_clear(a, b, surface, radius) and _enemies_clear(
		a, b, field.surface_height(surface, a), field.surface_height(surface, b)
	):
		return Result.OK
	if not field.base_on_table(a, radius) or not field.base_on_table(b, radius):
		return Result.OFF_TABLE
	var shape: ConvexShape = field.surfaces[surface].shape
	if shape.signed_distance(a) > HeightField.EDGE_SLACK or shape.signed_distance(b) > HeightField.EDGE_SLACK:
		return Result.NO_FLOOR
	if not field.walk_clear(a, b, surface, radius):
		return Result.TERRAIN
	return Result.ENEMY


## Cost of walking from a to b on `surface`: the length along the surface.
func walk_length(a: Vector2, b: Vector2, surface: int) -> float:
	return on_surface(a, surface).distance_to(on_surface(b, surface))


## Cost of crossing a wall from u on surface su to v on surface sv, or INF if
## that is not a legal crossing (last_result says why). See the class notes:
## one end is where the base touches the wall, the other is on top, directly
## above the touch point. `preferred` asks for one kind where there is a choice.
func wall_cost(u: Vector2, su: int, v: Vector2, sv: int, preferred: Transitions.Kind = Transitions.Kind.NONE) -> float:
	last_kind = Transitions.Kind.NONE
	var yu: float = field.surface_height(su, u)
	var yv: float = field.surface_height(sv, v)
	var going_up: bool = yv > yu
	var high_surface: int = sv if going_up else su
	var low_surface: int = su if going_up else sv
	var high: Vector2 = v if going_up else u
	var low: Vector2 = u if going_up else v
	var high_y: float = maxf(yu, yv)
	var low_y: float = minf(yu, yv)
	var wall_height: float = high_y - low_y
	last_result = Result.NO_WAY
	if wall_height <= HeightField.TOLERANCE:
		return INF
	var piece: TerrainPiece = field.surfaces[high_surface].piece
	if piece == null:
		return INF
	var shape: ConvexShape = field.surfaces[high_surface].shape
	# The low end touches the wall, the high end is on its top edge, a base radius away.
	var horizontal: float = low.distance_to(high)
	if (
		absf(horizontal - radius) > TOUCH_SLACK
		or shape.signed_distance(low) < radius - TOUCH_SLACK
		or shape.signed_distance(high) > HeightField.EDGE_SLACK
	):
		return INF
	# Going down lands on the first floor beneath.
	if not going_up:
		for s: int in field.surfaces_at(low):
			var y: float = field.surface_height(s, low)
			if y > low_y + HeightField.TOLERANCE and y < high_y - HeightField.TOLERANCE:
				return INF
	var options: Array[Transitions.Kind] = Transitions.wall_options(
		going_up, wall_height, piece.tag, going_up and field.is_low_obstacle(high_surface)
	)
	# A climb needs the wall to reach down to the low floor; dropping or
	# hopping off anything is fine.
	if piece.base_height > low_y + HeightField.TOLERANCE:
		var off: Array[Transitions.Kind] = []
		for option: Transitions.Kind in options:
			if not Transitions.climbs(option):
				off.append(option)
		options = off
	var kind: Transitions.Kind = Transitions.pick_wall_kind(options, going_up, wall_height, allow_rolls, preferred)
	if kind == Transitions.Kind.NONE:
		last_result = Result.NEEDS_ROLL if not options.is_empty() else Result.NO_WAY
		return INF
	var result: Result = passing_result(low, low_surface)
	if result == Result.OK:
		result = passing_result(high, high_surface)
	if result == Result.OK and not _enemies_clear(low, high, low_y, high_y):
		result = Result.ENEMY
	if result != Result.OK:
		last_result = result
		return INF
	last_result = Result.OK
	last_kind = kind
	last_drop = 0.0 if going_up else wall_height
	last_rise = wall_height if going_up else 0.0
	last_gap = 0.0
	last_rolls = Transitions.roll_count(kind, last_drop)
	return Transitions.wall_cost(kind, horizontal, wall_height)


## Cost of a gap jump from u on the ledge of su straight across to v on the
## ledge of sv, or INF if that is not a legal jump (last_result says why;
## TOO_WIDE if only the jump limit is in the way). See the class notes.
func jump_cost(u: Vector2, su: int, v: Vector2, sv: int) -> float:
	last_kind = Transitions.Kind.NONE
	last_result = Result.NO_WAY
	if su == sv or su == HeightField.TABLE or sv == HeightField.TABLE or field.same_level(su, sv):
		return INF
	var a: HeightField.Surface = field.surfaces[su]
	var b: HeightField.Surface = field.surfaces[sv]
	# Both ends at their ledges.
	if absf(a.shape.signed_distance(u)) > TOUCH_SLACK or absf(b.shape.signed_distance(v)) > TOUCH_SLACK:
		return INF
	var width: float = u.distance_to(v)
	if width < MIN_GAP:
		return INF
	var yu: float = field.surface_height(su, u)
	var yv: float = field.surface_height(sv, v)
	var low_ledge: float = minf(yu, yv)
	var high_ledge: float = maxf(yu, yv)
	if not _gap_is_open(u, v, su, sv, low_ledge, high_ledge):
		return INF
	var rise: float = maxf(yv - yu, 0.0)
	if width + rise > jump_limit + EPSILON:
		last_result = Result.TOO_WIDE
		return INF
	var result: Result = passing_result(u, su)
	if result == Result.OK:
		result = passing_result(v, sv)
	if result == Result.OK and not _enemies_clear(u, v, low_ledge, high_ledge):
		result = Result.ENEMY
	if result != Result.OK:
		last_result = result
		return INF
	if not allow_rolls:
		last_result = Result.NEEDS_ROLL
		return INF
	last_result = Result.OK
	last_kind = Transitions.Kind.GAP_JUMP
	last_drop = maxf(yu - yv, 0.0)
	last_rise = rise
	last_gap = width
	var middle: Vector2 = (u + v) * 0.5
	last_fall_point = Vector3(middle.x, yu, middle.y)
	last_rolls = Transitions.roll_count(Transitions.Kind.GAP_JUMP, last_drop)
	return width + rise


## Whether the straight way from u (on su) to v (on sv) runs over neither
## ledge in between, every floor under it there is lower than the lower ledge,
## and no terrain rises into the jump. Only the centre line is checked.
func _gap_is_open(u: Vector2, v: Vector2, su: int, sv: int, low_ledge: float, high_ledge: float) -> bool:
	var length: float = u.distance_to(v)
	var slack: float = (TOUCH_SLACK + HeightField.EDGE_SLACK) / length
	for s: HeightField.Surface in field.surfaces:
		var span: Vector2 = PlanarGeometry.segment_polygon_clip(u, v, s.polygon)
		var t0: float = maxf(span.x, slack)
		var t1: float = minf(span.y, 1.0 - slack)
		if t0 >= t1:
			continue
		if s.index == su or s.index == sv:
			return false
		var top: float = maxf(s.height_at(u.lerp(v, t0)), s.height_at(u.lerp(v, t1)))
		if top > low_ledge - HeightField.TOLERANCE:
			return false
	for solid: HeightField.Solid in field.solids:
		var span: Vector2 = PlanarGeometry.segment_polygon_clip(u, v, solid.polygon)
		var t0: float = maxf(span.x, slack)
		var t1: float = minf(span.y, 1.0 - slack)
		if t0 >= t1:
			continue
		var top: float = maxf(solid.top_at(u.lerp(v, t0)), solid.top_at(u.lerp(v, t1)))
		if top > low_ledge - HeightField.TOLERANCE and solid.bottom < high_ledge + model_height:
			last_result = Result.TERRAIN
			return false
	return true


## Cost of one path segment between two 3D points, whichever legal way it is
## taken (the fewest rolls, then the cheapest, if there are several; or the
## `preferred` kind if it is one of them), or INF if there is none;
## last_result then says why, last_kind (and last_drop, last_rise, last_gap,
## last_fall_point, last_rolls) say how it was taken otherwise.
func segment_cost(u: Vector3, v: Vector3, preferred: Transitions.Kind = Transitions.Kind.NONE) -> float:
	var su_list: PackedInt32Array = surfaces_at(u)
	var sv_list: PackedInt32Array = surfaces_at(v)
	var u2: Vector2 = Vector2(u.x, u.z)
	var v2: Vector2 = Vector2(v.x, v.z)
	var best: float = INF
	var best_key: Vector2 = Vector2(INF, INF)
	var best_reading: Array = []
	var reason: Result = Result.NO_FLOOR
	for s: int in _walk_surfaces(su_list, sv_list):
		var walk: Result = level_walk_result(u2, v2, s)
		if walk == Result.OK:
			var length: float = walk_length(u2, v2, s)
			if Vector2(0, length) < best_key:
				best = length
				best_key = Vector2(0, length)
				best_reading = [Transitions.Kind.WALK, maxf(u.y - v.y, 0.0), maxf(v.y - u.y, 0.0), 0.0, Vector3.ZERO, 0]
		else:
			reason = walk
	for su: int in su_list:
		for sv: int in sv_list:
			if su == sv:
				continue
			for jump: bool in [false, true]:
				var cost: float = jump_cost(u2, su, v2, sv) if jump else wall_cost(u2, su, v2, sv, preferred)
				if cost < INF:
					var key: Vector2 = Vector2(last_rolls, cost)
					if preferred != Transitions.Kind.NONE and last_kind == preferred:
						key = Vector2(-1, cost)
					if key < best_key:
						best = cost
						best_key = key
						best_reading = [last_kind, last_drop, last_rise, last_gap, last_fall_point, last_rolls]
				elif _more_telling(last_result, reason):
					reason = last_result
	if best < INF:
		last_result = Result.OK
		last_kind = best_reading[0]
		last_drop = best_reading[1]
		last_rise = best_reading[2]
		last_gap = best_reading[3]
		last_fall_point = best_reading[4]
		last_rolls = best_reading[5]
	else:
		last_result = reason
		last_kind = Transitions.Kind.NONE
		last_rolls = 0
	return best


## Whether `candidate` says more about why a segment is not legal than `current`.
static func _more_telling(candidate: Result, current: Result) -> bool:
	if current == Result.NO_FLOOR:
		return candidate != Result.NO_WAY
	if candidate == Result.NEEDS_ROLL:
		return true
	return candidate == Result.TOO_WIDE and current != Result.NEEDS_ROLL


## The segments of the path from `from` through `points`, as taken (see
## segment_cost()), or an empty list if a segment is not legal (last_result
## says why). `preferred` gives a kind per segment (NONE: whichever is best).
func segments_for(from: Vector3, points: Array[Vector3], preferred: Array = []) -> Array[MoveSegment]:
	var result: Array[MoveSegment] = []
	var previous: Vector3 = from
	for i: int in points.size():
		var wanted: Transitions.Kind = Transitions.Kind.NONE
		if i < preferred.size():
			wanted = preferred[i]
		var cost: float = segment_cost(previous, points[i], wanted)
		if cost == INF:
			return []
		var segment: MoveSegment = MoveSegment.new()
		segment.from = previous
		segment.to = points[i]
		segment.kind = last_kind
		segment.cost = cost
		segment.drop = last_drop
		segment.rise = last_rise
		segment.gap_width = last_gap
		segment.fall_point = last_fall_point
		result.append(segment)
		previous = points[i]
	last_result = Result.OK
	return result


## The highest floor at p lower than `y`, or -1 if there is none.
func surface_below(p: Vector2, y: float) -> int:
	var best: int = -1
	var best_y: float = -INF
	for s: int in field.surfaces_at(p):
		var h: float = field.surface_height(s, p)
		if h < y - HeightField.TOLERANCE and h > best_y:
			best = s
			best_y = h
	return best


## The closest position to p on `surface` (or the floors of its level) where
## the model may stop, or null if there is none within STOP_SEARCH_DISTANCE.
## Searched on rings of growing radius, so it is within a ring step of exact.
func closest_stop(p: Vector2, surface: int) -> Variant:
	var surfaces: PackedInt32Array = field.level_members(surface)
	var found: Variant = _stop_on(p, surfaces)
	if found != null:
		return found
	var r: float = STOP_RING_STEP
	while r <= STOP_SEARCH_DISTANCE + EPSILON:
		var count: int = maxi(8, ceili(TAU * r / STOP_RING_STEP))
		for k: int in count:
			var angle: float = TAU * k / count
			var at: Variant = _stop_on(p + Vector2(cos(angle), sin(angle)) * r, surfaces)
			if at != null:
				return at
		r += STOP_RING_STEP
	return null


func _stop_on(q: Vector2, surfaces: PackedInt32Array) -> Variant:
	for s: int in surfaces:
		if field.is_floor(q, s) and point_result(q, s) == Result.OK:
			return on_surface(q, s)
	return null


## Like segment_cost(), but only as a walk on one surface (INF otherwise).
func walk_cost(u: Vector3, v: Vector3) -> float:
	var u2: Vector2 = Vector2(u.x, u.z)
	var v2: Vector2 = Vector2(v.x, v.z)
	var best: float = INF
	for s: int in _walk_surfaces(surfaces_at(u), surfaces_at(v)):
		if level_walk_result(u2, v2, s) == Result.OK:
			best = minf(best, walk_length(u2, v2, s))
	return best


## One surface per level group that both ends of a walk are on.
func _walk_surfaces(su_list: PackedInt32Array, sv_list: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for su: int in su_list:
		for sv: int in sv_list:
			if not field.same_level(su, sv):
				continue
			var seen: bool = false
			for s: int in result:
				if field.same_level(s, su):
					seen = true
			if not seen:
				result.append(su)
	return result


## Whether the base may walk straight from a to b on the level surface that
## `surface` is part of: across the seams between its pieces as if they were
## one. The way is split where it crosses from piece to piece, and each part is
## a walk_result() on its piece.
func level_walk_result(a: Vector2, b: Vector2, surface: int) -> Result:
	var members: PackedInt32Array = field.level_members(surface)
	var length: float = a.distance_to(b)
	if members.size() == 1 or length < EPSILON:
		return walk_result(a, b, surface)
	var spans: Array[Vector3] = []  # (from, to, piece surface) along the way
	for member: int in members:
		var span: Vector2 = PlanarGeometry.segment_polygon_clip(a, b, field.surfaces[member].polygon)
		if span.x <= span.y:
			spans.append(Vector3(span.x, span.y, member))
	var slack: float = HeightField.EDGE_SLACK / length
	var at: float = 0.0
	while at < 1.0 - slack:
		var best_end: float = at
		var best_member: int = -1
		for span: Vector3 in spans:
			if span.x <= at + slack and span.y > best_end:
				best_end = span.y
				best_member = int(span.z)
		if best_member == -1:
			return Result.NO_FLOOR
		var result: Result = walk_result(a.lerp(b, at), a.lerp(b, minf(best_end, 1.0)), best_member)
		if result != Result.OK:
			return result
		at = best_end
	return Result.OK


## Whether a move may end at p, and what it pays on top of its path for
## stopping there (a low obstacle's height). INF if it may not end there;
## last_result then says why.
func stop_surcharge(p: Vector3) -> float:
	var p2: Vector2 = Vector2(p.x, p.z)
	var best: float = INF
	var reason: Result = Result.NO_FLOOR
	for s: int in surfaces_at(p):
		var result: Result = point_result(p2, s)
		if result == Result.OK:
			best = minf(best, field.stop_surcharge(s, start_piece_ids))
		else:
			reason = result
	last_result = Result.OK if best < INF else reason
	return best


## A lower bound on how far the centre at p on `surface` can move and stay
## passable, capped at `cap` (see HeightField.clearance()). Only meaningful on
## flat surfaces; on a slope it is -1 so nothing is skipped on its strength.
func clearance(p: Vector2, surface: int, cap: float = INF) -> float:
	if field.surfaces[surface].gradient != Vector2.ZERO:
		return -1.0
	var best: float = field.clearance(p, surface, radius, cap)
	var y: float = field.surface_height(surface, p)
	for i: int in _enemy_centres.size():
		var limit: float = _enemy_limit(i, y, y)
		if limit > 0.0:
			best = minf(best, p.distance_to(_enemy_centres[i]) - limit)
	return best


## Roughly the signed distance from p on `surface` to the edge of where the
## model may stop: positive where point_result() is OK. For drawing outlines
## and snapping, never for legality.
func stand_value(p: Vector2, surface: int, cap: float = INF) -> float:
	var best: float = field.stand_value(p, surface, radius, model_height, cap)
	var y: float = field.surface_height(surface, p)
	for i: int in _enemy_centres.size():
		var limit: float = _enemy_limit(i, y, y)
		if limit > 0.0:
			best = minf(best, p.distance_to(_enemy_centres[i]) - limit)
	for i: int in _friend_centres.size():
		if y < _friend_tops[i] - EPSILON and _friend_bottoms[i] < y + model_height - EPSILON:
			best = minf(best, p.distance_to(_friend_centres[i]) - radius - _friend_radii[i])
	return best


static func describe(result: Result) -> String:
	match result:
		Result.OK:
			return ""
		Result.OFF_TABLE:
			return "Blocked: the base would leave the table."
		Result.TERRAIN:
			return "Blocked: the base would overlap terrain."
		Result.MODEL:
			return "Blocked: the move may not end with the base overlapping another model."
		Result.ENEMY:
			return "Too close to an enemy: only a charge may come within 1\"."
		Result.NO_FLOOR:
			return "Blocked: there is no floor to move on there."
		Result.NOT_SUPPORTED:
			return "Cannot stop there: less than half the base would be supported."
		Result.HEADROOM:
			return "Cannot stop there: not enough headroom for the model."
		Result.NEEDS_ROLL:
			return "That needs a roll (a sheer climb, a jump or a drop)."
		Result.NO_WAY:
			return "Blocked: there is no way from one floor to the other there."
		Result.TOO_WIDE:
			return "Too wide to jump: a gap (plus any rise) may be at most half the model's Movement."
	return "Illegal move."


## Whether the base moving in a straight line from a (height ya) to b (height
## yb) stays at least 1" from every enemy cylinder. Conservative between the
## ends: the closest vertical approach over the whole height range is used.
func _enemies_clear(a: Vector2, b: Vector2, ya: float, yb: float) -> bool:
	var low: float = minf(ya, yb)
	var high: float = maxf(ya, yb)
	for i: int in _enemy_centres.size():
		var limit: float = _enemy_limit(i, low, high)
		if limit <= 0.0:
			continue
		if PlanarGeometry.point_segment_distance(_enemy_centres[i], a, b) < limit - EPSILON:
			return false
	return true


## The centre-to-centre distance the mover must keep from enemy i while its base
## is somewhere between heights low and high, or 0 if the cylinders are 1" or
## more apart vertically anyway.
func _enemy_limit(i: int, low: float, high: float) -> float:
	var gap: float = 0.0
	if _enemy_bottoms[i] > high + model_height:
		gap = _enemy_bottoms[i] - (high + model_height)
	elif low > _enemy_tops[i]:
		gap = low - _enemy_tops[i]
	if gap >= ENEMY_DISTANCE_INCHES:
		return 0.0
	var horizontal: float = sqrt(ENEMY_DISTANCE_INCHES * ENEMY_DISTANCE_INCHES - gap * gap)
	return radius + _enemy_radii[i] + horizontal
