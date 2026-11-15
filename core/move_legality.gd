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

enum Result { OK, OFF_TABLE, TERRAIN, MODEL, ENEMY }

const EPSILON: float = 0.0001
## A model may only come within this distance of an enemy (edge to edge) by charging.
const ENEMY_DISTANCE_INCHES: float = 1.0

## Radius of the moving model's base, inches.
var radius: float

var _centre_min: Vector2
var _centre_max: Vector2

## Other models, as circles the moving centre must stay outside of.
var _circle_centres: PackedVector2Array = PackedVector2Array()
## Minimum centre-to-centre distance for each circle.
var _circle_min_distances: PackedFloat64Array = PackedFloat64Array()
var _circle_is_enemy: Array[bool] = []

## Blocking terrain footprints.
var _rect_centres: PackedVector2Array = PackedVector2Array()
var _rect_half_extents: PackedVector2Array = PackedVector2Array()
var _rect_rotations: PackedFloat64Array = PackedFloat64Array()


func _init(state: GameState, model: ModelState) -> void:
	radius = model.base_radius_inches()
	_centre_min = Vector2(radius, radius)
	_centre_max = Vector2(state.table_width - radius, state.table_depth - radius)
	for other: ModelState in state.models:
		if other.id == model.id:
			continue
		var is_enemy: bool = other.player != model.player
		var min_distance: float = radius + other.base_radius_inches()
		if is_enemy:
			min_distance += ENEMY_DISTANCE_INCHES
		_circle_centres.append(Vector2(other.position.x, other.position.z))
		_circle_min_distances.append(min_distance)
		_circle_is_enemy.append(is_enemy)
	for piece: TerrainPiece in state.terrain:
		if not piece.blocks_movement:
			continue
		_rect_centres.append(piece.footprint_center())
		_rect_half_extents.append(piece.footprint_half_extents())
		_rect_rotations.append(piece.rotation)


## Whether the base may stand with its centre at p.
func point_result(p: Vector2) -> Result:
	if not _inside_table(p):
		return Result.OFF_TABLE
	for i: int in _rect_centres.size():
		if PlanarGeometry.circle_overlaps_rect(
			p, radius, _rect_centres[i], _rect_half_extents[i], _rect_rotations[i], EPSILON
		):
			return Result.TERRAIN
	for i: int in _circle_centres.size():
		if p.distance_to(_circle_centres[i]) < _circle_min_distances[i] - EPSILON:
			return Result.ENEMY if _circle_is_enemy[i] else Result.MODEL
	return Result.OK


## Whether the base may move in a straight line from a to b, ends included.
func segment_result(a: Vector2, b: Vector2) -> Result:
	# The legal region for the centre on the table is a rectangle, which is
	# convex, so checking both ends is enough.
	if not _inside_table(a) or not _inside_table(b):
		return Result.OFF_TABLE
	for i: int in _rect_centres.size():
		if PlanarGeometry.swept_circle_overlaps_rect(
			a, b, radius, _rect_centres[i], _rect_half_extents[i], _rect_rotations[i], EPSILON
		):
			return Result.TERRAIN
	for i: int in _circle_centres.size():
		if PlanarGeometry.swept_circle_within(
			a, b, _circle_centres[i], _circle_min_distances[i], EPSILON
		):
			return Result.ENEMY if _circle_is_enemy[i] else Result.MODEL
	return Result.OK


## How far the centre at p is from the nearest illegal position: positive when
## legal, negative when illegal. It changes by at most the distance moved, so a
## segment whose ends both have clearance of at least half its length is legal.
func clearance(p: Vector2) -> float:
	var best: float = minf(
		minf(p.x - _centre_min.x, _centre_max.x - p.x),
		minf(p.y - _centre_min.y, _centre_max.y - p.y)
	)
	for i: int in _rect_centres.size():
		var d: float = PlanarGeometry.point_rect_signed_distance(
			p, _rect_centres[i], _rect_half_extents[i], _rect_rotations[i]
		)
		best = minf(best, d - radius)
	for i: int in _circle_centres.size():
		best = minf(best, p.distance_to(_circle_centres[i]) - _circle_min_distances[i])
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
			return "Blocked: the base would overlap another model."
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
