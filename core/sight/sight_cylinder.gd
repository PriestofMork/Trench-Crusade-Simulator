class_name SightCylinder
extends RefCounted
## A model's volume for line of sight (ruling 1 of brief 008): its base
## diameter by the height from the base size table, its underside on the
## floor under the model's centre, its axis the normal of that floor (upright
## on level ground, tilted on a ramp, no cap). Movement, support, melee and
## headroom never use this; they keep the upright cylinder.
##
## Built from a model, or from plain data for "what would be seen from
## there" without moving anything. A Down model keeps the same cylinder
## (ruling 8).

## The fixed sample points used to look for a clear line (ruling 3): rings
## of RING_POINTS points round the rim at each of RING_LEVELS (fractions of
## the height), plus points on the axis at AXIS_LEVELS. This is the one
## definition of the sample set. Eight points a ring are 45 degrees apart,
## which finds a 0.25" sliver of the widest base (60 mm): a strip that wide
## at the edge of a cylinder of radius r spans 2 * acos((r - 0.25) / r) of
## its rim, 76 degrees for r = 1.18".
const RING_POINTS: int = 8
const RING_LEVELS: Array[float] = [1.0, 0.5, 0.0]
const AXIS_LEVELS: Array[float] = [0.5, 1.0, 0.0]

## The model it belongs to, or -1 for a cylinder at a hypothetical position.
var model_id: int = -1
## The base size it was built from, or -1 if built from a radius and height.
var base_mm: int = -1
## Centre of the underside, inches.
var base: Vector3
## Unit axis, from the underside to the top.
var axis: Vector3 = Vector3.UP
var radius: float
var height: float
## Bounding box, for quick rejects.
var bounds_min: Vector3
var bounds_max: Vector3
## The middle of the axis and the radius of the sphere round it that holds
## the whole cylinder, for quick rejects.
var middle: Vector3
var sphere_radius: float
## Two directions square to the axis (the tilt's x and z).
var side_x: Vector3
var side_z: Vector3

var _points: PackedVector3Array = PackedVector3Array()
var _corners: PackedVector3Array = PackedVector3Array()
var _hull: PackedVector3Array = PackedVector3Array()


func _init(p_base: Vector3, p_axis: Vector3, p_radius: float, p_height: float, p_model_id: int = -1) -> void:
	base = p_base
	axis = p_axis.normalized()
	radius = p_radius
	height = p_height
	model_id = p_model_id
	var top: Vector3 = base + axis * height
	# The rim's reach along each world axis: radius * sqrt(1 - axis_i^2).
	var reach: Vector3 = Vector3(
		radius * sqrt(maxf(0.0, 1.0 - axis.x * axis.x)),
		radius * sqrt(maxf(0.0, 1.0 - axis.y * axis.y)),
		radius * sqrt(maxf(0.0, 1.0 - axis.z * axis.z))
	)
	bounds_min = base.min(top) - reach
	bounds_max = base.max(top) + reach
	middle = base + axis * (height / 2.0)
	sphere_radius = sqrt(radius * radius + height * height / 4.0)
	var tilt: Basis = tilt_basis()
	side_x = tilt.x
	side_z = tilt.z


## The sight cylinder of a model where it stands now.
static func for_model(state: GameState, model: ModelState) -> SightCylinder:
	return at(state, model.position, model.base_mm, model.id)


## The sight cylinder a model of `base_mm` would have with its underside
## centre at `position`, tilted to the floor there.
static func at(state: GameState, position: Vector3, base_mm: int, p_model_id: int = -1) -> SightCylinder:
	var cylinder: SightCylinder = SightCylinder.new(
		position, tilt_at(state, position), BaseSizes.mm_to_inches(base_mm) / 2.0,
		BaseSizes.height_inches(base_mm), p_model_id
	)
	cylinder.base_mm = base_mm
	return cylinder


## The up direction of a model whose underside centre is at `position`: the
## normal of the floor there. The one source of a model's tilt, for sight and
## for drawing (ruling 2).
static func tilt_at(state: GameState, position: Vector3) -> Vector3:
	return state.height_field().floor_up_at(position)


## The rotation from upright to this cylinder's axis (the same rotation the
## model is drawn with).
func tilt_basis() -> Basis:
	return Basis(Quaternion(Vector3.UP, axis))


func top_centre() -> Vector3:
	return base + axis * height



## The sample points (ruling 3), in a fixed order: the axis points first,
## then the rings. Built once.
func sample_points() -> PackedVector3Array:
	if not _points.is_empty():
		return _points
	var tilt: Basis = tilt_basis()
	for level: float in AXIS_LEVELS:
		_points.append(base + axis * (height * level))
	for level: float in RING_LEVELS:
		var centre: Vector3 = base + axis * (height * level)
		for k: int in RING_POINTS:
			var angle: float = TAU * k / RING_POINTS
			_points.append(centre + tilt * Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return _points


## Indices into sample_points() of the points whose convex hull holds them
## all: the rings at the top and at the bottom.
static func hull_indices() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for level: int in RING_LEVELS.size():
		if RING_LEVELS[level] == 1.0 or RING_LEVELS[level] == 0.0:
			var first: int = AXIS_LEVELS.size() + level * RING_POINTS
			for k: int in RING_POINTS:
				result.append(first + k)
	return result


## The sample points at hull_indices().
func hull_points() -> PackedVector3Array:
	if not _hull.is_empty():
		return _hull
	var points: PackedVector3Array = sample_points()
	for index: int in hull_indices():
		_hull.append(points[index])
	return _hull


## The eight corners of the box round the cylinder, square to its axis (it
## holds every sample point).
func box_corners() -> PackedVector3Array:
	if not _corners.is_empty():
		return _corners
	for level: float in [0.0, height]:
		var centre: Vector3 = base + axis * level
		for sx: float in [-radius, radius]:
			for sz: float in [-radius, radius]:
				_corners.append(centre + side_x * sx + side_z * sz)
	return _corners


## A fixed order between cylinders that does not depend on which one is the
## viewer, so a sight check can always run the same way round (ruling 7).
static func comes_before(a: SightCylinder, b: SightCylinder) -> bool:
	var ka: Array[float] = [a.base.x, a.base.y, a.base.z, a.axis.x, a.axis.y, a.axis.z, a.radius, a.height]
	var kb: Array[float] = [b.base.x, b.base.y, b.base.z, b.axis.x, b.axis.y, b.axis.z, b.radius, b.height]
	for i: int in ka.size():
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return a.model_id < b.model_id
