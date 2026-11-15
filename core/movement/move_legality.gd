class_name MoveLegality
extends RefCounted
## Where one model's base may be, and along which segments it may move, on flat
## ground. Built once from the state for the moving model; shared by MoveCommand
## (which validates paths) and ReachField (which finds them), so the two always
## agree.
##
## Everything is on the table plane: a Vector2 is (world x, world z) and is the
## centre of the moving model's base. Touching is allowed; overlapping is not.
## Being exactly 1" from an enemy is allowed; closer is not.
##
## Friendly bases may be passed through but not stood on: segment_result() and
## clearance() ignore them (they describe passing), point_result() and
## friendly_clearance() include them (they describe where a move may end).

enum Result { OK, OFF_TABLE, TERRAIN, MODEL, ENEMY }

const EPSILON: float = 0.0001
## A model may only come within this distance of an enemy (edge to edge) by charging.
const ENEMY_DISTANCE_INCHES: float = 1.0

## Radius of the moving model's base, inches.
var radius: float

var _centre_min: Vector2
var _centre_max: Vector2

## Enemy models, as circles the moving centre must stay outside of all the way.
var _circle_centres: PackedVector2Array = PackedVector2Array()
## Minimum centre-to-centre distance for each circle.
var _circle_min_distances: PackedFloat64Array = PackedFloat64Array()

## Friendly models, as circles the moving centre may cross but not end inside.
var _friend_centres: PackedVector2Array = PackedVector2Array()
var _friend_min_distances: PackedFloat64Array = PackedFloat64Array()

## Blocking terrain footprints.
var _rect_centres: PackedVector2Array = PackedVector2Array()
var _rect_half_extents: PackedVector2Array = PackedVector2Array()
var _rect_rotations: PackedFloat64Array = PackedFloat64Array()
## Centre-to-corner distance plus the base radius: a quick reject for segments.
var _rect_reach: PackedFloat64Array = PackedFloat64Array()
var _rect_cos: PackedFloat64Array = PackedFloat64Array()
var _rect_sin: PackedFloat64Array = PackedFloat64Array()


func _init(state: GameState, model: ModelState) -> void:
	radius = model.base_radius_inches()
	_centre_min = Vector2(radius, radius)
	_centre_max = Vector2(state.table_width - radius, state.table_depth - radius)
	for other: ModelState in state.models:
		if other.id == model.id:
			continue
		var centre: Vector2 = Vector2(other.position.x, other.position.z)
		var min_distance: float = radius + other.base_radius_inches()
		if other.player != model.player:
			_circle_centres.append(centre)
			_circle_min_distances.append(min_distance + ENEMY_DISTANCE_INCHES)
		else:
			_friend_centres.append(centre)
			_friend_min_distances.append(min_distance)
	for piece: TerrainPiece in state.terrain:
		_rect_centres.append(piece.footprint_center)
		_rect_half_extents.append(piece.footprint_half_extents())
		_rect_rotations.append(piece.rotation)
		_rect_reach.append(piece.footprint_half_extents().length() + radius)
		_rect_cos.append(cos(piece.rotation))
		_rect_sin.append(sin(piece.rotation))


## Whether a move may end with the base centre at p: passing_result() and no
## overlap with a friendly base either.
func point_result(p: Vector2) -> Result:
	var result: Result = passing_result(p)
	if result != Result.OK:
		return result
	for i: int in _friend_centres.size():
		if p.distance_to(_friend_centres[i]) < _friend_min_distances[i] - EPSILON:
			return Result.MODEL
	return Result.OK


## Whether the base may be at p while moving (friendly bases ignored).
func passing_result(p: Vector2) -> Result:
	if not _inside_table(p):
		return Result.OFF_TABLE
	for i: int in _rect_centres.size():
		if PlanarGeometry.circle_overlaps_rect(
			p, radius, _rect_centres[i], _rect_half_extents[i], _rect_rotations[i], EPSILON
		):
			return Result.TERRAIN
	for i: int in _circle_centres.size():
		if p.distance_to(_circle_centres[i]) < _circle_min_distances[i] - EPSILON:
			return Result.ENEMY
	return Result.OK


## Whether the base may move in a straight line from a to b, ends included.
## Friendly bases are ignored: check where the move ends with point_result().
func segment_result(a: Vector2, b: Vector2) -> Result:
	# The legal region for the centre on the table is a rectangle, which is
	# convex, so checking both ends is enough.
	if not _inside_table(a) or not _inside_table(b):
		return Result.OFF_TABLE
	for i: int in _rect_centres.size():
		if PlanarGeometry.point_segment_distance(_rect_centres[i], a, b) >= _rect_reach[i]:
			continue
		if PlanarGeometry.swept_circle_overlaps_rect(
			a, b, radius, _rect_centres[i], _rect_half_extents[i], _rect_rotations[i], EPSILON
		):
			return Result.TERRAIN
	for i: int in _circle_centres.size():
		if PlanarGeometry.swept_circle_within(
			a, b, _circle_centres[i], _circle_min_distances[i], EPSILON
		):
			return Result.ENEMY
	return Result.OK


## How far the centre at p is from the nearest position passing_result()
## rejects: positive when legal, negative when illegal. It changes by at most the distance moved, so a
## segment whose ends both have clearance of at least half its length is legal.
## Values above `cap` may be returned as `cap`, which lets far obstacles be skipped.
func clearance(p: Vector2, cap: float = INF) -> float:
	var best: float = minf(
		minf(minf(p.x - _centre_min.x, _centre_max.x - p.x), minf(p.y - _centre_min.y, _centre_max.y - p.y)),
		cap
	)
	for i: int in _rect_centres.size():
		var d: Vector2 = p - _rect_centres[i]
		# The box is no nearer than its centre minus its corner distance.
		if d.length() - _rect_reach[i] >= best:
			continue
		# Inlined PlanarGeometry.point_rect_signed_distance(), with cached cos and sin.
		var c: float = _rect_cos[i]
		var s: float = _rect_sin[i]
		var half: Vector2 = _rect_half_extents[i]
		var qx: float = absf(d.x * c - d.y * s) - half.x
		var qy: float = absf(d.x * s + d.y * c) - half.y
		var outside: float = sqrt(maxf(qx, 0.0) * maxf(qx, 0.0) + maxf(qy, 0.0) * maxf(qy, 0.0))
		best = minf(best, outside + minf(maxf(qx, qy), 0.0) - radius)
	for i: int in _circle_centres.size():
		best = minf(best, p.distance_to(_circle_centres[i]) - _circle_min_distances[i])
	return best


## Like clearance(), but only for the friendly bases a move may not end on.
## min(clearance(p), friendly_clearance(p)) is the clearance for point_result().
func friendly_clearance(p: Vector2, cap: float = INF) -> float:
	var best: float = cap
	for i: int in _friend_centres.size():
		best = minf(best, p.distance_to(_friend_centres[i]) - _friend_min_distances[i])
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
	return "Illegal move."


func _inside_table(p: Vector2) -> bool:
	return (
		p.x >= _centre_min.x - EPSILON
		and p.y >= _centre_min.y - EPSILON
		and p.x <= _centre_max.x + EPSILON
		and p.y <= _centre_max.y + EPSILON
	)
