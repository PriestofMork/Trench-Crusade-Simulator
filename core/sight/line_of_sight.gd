class_name LineOfSight
extends Sight
## Line of sight between model cylinders (docs/rules/line-of-sight.md;
## rulings of brief 008):
## - each model is its SightCylinder, tilted to the floor it stands on;
## - the target is visible if some segment from a sample point of the
##   viewer's cylinder to a sample point of the target's is not blocked
##   (SightCylinder.sample_points(), ruling 3);
## - every terrain piece that blocks sight, the tabletop and the cylinder of
##   every other model on the table block (ruling 4); touching is not
##   blocking (SightGeometry.TOLERANCE, ruling 6);
## - the check always runs from the cylinder that comes first in a fixed
##   order, so A sees B exactly when B sees A (ruling 7);
## - Out of Action models neither block nor are seen (ruling 9); Down models
##   keep their cylinder (ruling 8).
##
## Speed: model cylinders are kept between checks while a model stays where
## it is; only blockers near both cylinders (a capsule round the line between
## them, and the box round both) are tried; the line between the middles is
## tried first; then each sample point gets an outcode per blocker, so most
## segments are rejected by one bit test, and the blocker that stopped the
## last segment is tried first. The cache is guarded, so checks may run on a
## worker thread (charge planning) while the game asks too.

## Model id -> its cylinder, and the position, base and terrain it was built for.
var _cylinders: Dictionary[int, SightCylinder] = {}
var _cache_terrain: SightTerrain = null
var _mutex: Mutex = Mutex.new()

## Further than this from a model's base centre, no part of its cylinder can
## be, however it is tilted (the tallest model's height plus the widest
## radius, with room to spare), inches.
const MODEL_REACH: float = 4.5


func check(state: GameState, viewer: ModelState, target: ModelState) -> SightResult:
	if viewer == null or target == null or viewer.id == target.id:
		return SightResult.blocked()
	if not viewer.on_table() or not target.on_table():
		return SightResult.blocked()
	return check_between(
		state, cylinder_of(state, viewer), cylinder_of(state, target), PackedInt32Array([viewer.id, target.id])
	)


func check_between(
	state: GameState, viewer: SightCylinder, target: SightCylinder, ignored_ids: PackedInt32Array
) -> SightResult:
	if SightCylinder.comes_before(target, viewer):
		var reverse: SightResult = _search(state, target, viewer, ignored_ids)
		if reverse.visible:
			return SightResult.clear(reverse.to, reverse.from)
		return reverse
	return _search(state, viewer, target, ignored_ids)


## A model's sight cylinder where it stands now (kept until it moves).
func cylinder_of(state: GameState, model: ModelState) -> SightCylinder:
	var terrain: SightTerrain = state.sight_terrain()
	_mutex.lock()
	if _cache_terrain != terrain:
		_cylinders.clear()
		_cache_terrain = terrain
	var cylinder: SightCylinder = _fresh_cylinder(state, model)
	_mutex.unlock()
	return cylinder


## With the mutex held: the cached cylinder, rebuilt if the model has moved.
func _fresh_cylinder(state: GameState, model: ModelState) -> SightCylinder:
	var cylinder: SightCylinder = _cylinders.get(model.id)
	if cylinder != null and cylinder.base == model.position and cylinder.base_mm == model.base_mm:
		return cylinder
	cylinder = SightCylinder.for_model(state, model)
	cylinder.sample_points()
	_cylinders[model.id] = cylinder
	return cylinder


func _search(state: GameState, a: SightCylinder, b: SightCylinder, ignored_ids: PackedInt32Array) -> SightResult:
	var box_min: Vector3 = a.bounds_min.min(b.bounds_min)
	var box_max: Vector3 = a.bounds_max.max(b.bounds_max)
	# Everything between the two lies within this capsule.
	var ca: Vector3 = a.middle
	var cb: Vector3 = b.middle
	var reach: float = maxf(a.sphere_radius, b.sphere_radius)
	var solids: Array[SightGeometry.Solid] = []
	for solid: SightGeometry.Solid in state.sight_terrain().solids:
		if not SightGeometry.boxes_overlap(solid.bounds_min, solid.bounds_max, box_min, box_max):
			continue
		if _point_segment_distance(solid.sphere_centre, ca, cb) <= solid.sphere_radius + reach:
			solids.append(solid)
	var cylinders: Array[SightCylinder] = []
	var terrain: SightTerrain = state.sight_terrain()
	_mutex.lock()
	if _cache_terrain != terrain:
		_cylinders.clear()
		_cache_terrain = terrain
	for model: ModelState in state.models:
		if not model.on_table() or ignored_ids.has(model.id):
			continue
		# Far from the line between them, whatever its tilt: skip it.
		if _point_segment_distance(model.position, ca, cb) > reach + MODEL_REACH:
			continue
		var cylinder: SightCylinder = _fresh_cylinder(state, model)
		if not SightGeometry.boxes_overlap(cylinder.bounds_min, cylinder.bounds_max, box_min, box_max):
			continue
		if _point_segment_distance(cylinder.middle, ca, cb) <= cylinder.sphere_radius + reach:
			cylinders.append(cylinder)
	_mutex.unlock()
	var from_points: PackedVector3Array = a.sample_points()
	var to_points: PackedVector3Array = b.sample_points()
	if solids.is_empty() and cylinders.is_empty():
		return SightResult.clear(from_points[0], to_points[0])
	# Probes: a few sample pairs that are most often clear. Any clear one
	# answers; the blockers that stopped them are the ones to try to prove
	# the target hidden with.
	var stoppers: PackedInt32Array = PackedInt32Array()
	for pair: Vector2i in _probes(a, b):
		var p: Vector3 = from_points[pair.x]
		var q: Vector3 = to_points[pair.y]
		var found: PackedInt32Array = _all_blockers(p, q, solids, cylinders)
		if found.is_empty():
			return SightResult.clear(p, q)
		for index: int in found:
			if index >= 0 and not stoppers.has(index):
				stoppers.append(index)
	# Hidden proof: the ends a segment can have and still meet a convex
	# blocker form a convex set, for either end held fixed. So if one blocker
	# stops every segment between two point sets, it stops every segment
	# between their convex hulls. Tried with the boxes round the cylinders
	# (8 corners each, cheap but a little larger), then with the hulls of the
	# sample points themselves (the top and bottom rings), which is exact.
	for index: int in stoppers:
		if _blocks_between(a.box_corners(), b.box_corners(), index, solids, cylinders):
			return SightResult.blocked()
	for index: int in stoppers:
		if _blocks_between(a.hull_points(), b.hull_points(), index, solids, cylinders):
			return SightResult.blocked()
	# Outcodes: per blocker and sample point, a bit for each face (or side of
	# a cylinder's square) the point is outside of. A segment whose two ends
	# share a bit misses that blocker. For solids the rooms (how far inside
	# each face a point is) are kept for the exact test.
	var na: int = from_points.size()
	var nb: int = to_points.size()
	var solid_count: int = solids.size()
	var total: int = solid_count + cylinders.size()
	var codes_a: PackedInt32Array = PackedInt32Array()
	var codes_b: PackedInt32Array = PackedInt32Array()
	codes_a.resize(total * na)
	codes_b.resize(total * nb)
	var rooms_a: Array[PackedFloat64Array] = []
	var rooms_b: Array[PackedFloat64Array] = []
	var planes: PackedInt32Array = PackedInt32Array()
	for i: int in solid_count:
		var solid: SightGeometry.Solid = solids[i]
		var count: int = solid.normals.size()
		planes.append(count)
		rooms_a.append(_solid_rooms(solid, from_points, codes_a, i * na))
		rooms_b.append(_solid_rooms(solid, to_points, codes_b, i * nb))
	for i: int in cylinders.size():
		_cylinder_codes(cylinders[i], from_points, codes_a, (solid_count + i) * na)
		_cylinder_codes(cylinders[i], to_points, codes_b, (solid_count + i) * nb)
	var hull: PackedInt32Array = SightCylinder.hull_indices()
	# The blocker that stopped the last segment, tried first.
	var last: int = -1
	for pi: int in na:
		var p: Vector3 = from_points[pi]
		# Per-point proof: if one blocker stops the segments from p to every
		# point of b's hull, it stops those to every sample point of b.
		if last != -1 and _blocks_hull_from(p, pi, na, nb, last, solids, cylinders, codes_a, codes_b, rooms_a, rooms_b, planes, to_points, hull):
			continue
		for qi: int in nb:
			var q: Vector3 = to_points[qi]
			if p.y < -SightGeometry.TOLERANCE or q.y < -SightGeometry.TOLERANCE:
				continue  # Into the tabletop (SightGeometry.segment_blocked_by_table()).
			var blocked: bool = false
			for k: int in total + 1:
				var i: int = last if k == 0 else k - 1
				if i == -1 or (k > 0 and i == last):
					continue
				var code_p: int = codes_a[i * na + pi]
				var code_q: int = codes_b[i * nb + qi]
				if code_p & code_q != 0:
					continue
				var hit: bool
				if i < solid_count:
					var count: int = planes[i]
					hit = code_p == 0 or code_q == 0 or SightGeometry.rooms_blocked(rooms_a[i], pi * count, rooms_b[i], qi * count, count)
				else:
					var c: SightCylinder = cylinders[i - solid_count]
					hit = SightGeometry.segment_blocked_by_cylinder(p, q, c.base, c.axis, c.radius, c.height)
				if hit:
					last = i
					blocked = true
					break
			if not blocked:
				return SightResult.clear(p, q)
	return SightResult.blocked()


## Whether blocker `index` stops every segment from sample point `p` (index
## `pi` of `na`) of the first cylinder to the hull points of the second (its
## sample points at the indices in `hull`).
static func _blocks_hull_from(
	p: Vector3, pi: int, na: int, nb: int, index: int, solids: Array[SightGeometry.Solid], cylinders: Array[SightCylinder],
	codes_a: PackedInt32Array, codes_b: PackedInt32Array, rooms_a: Array[PackedFloat64Array], rooms_b: Array[PackedFloat64Array],
	planes: PackedInt32Array, to_points: PackedVector3Array, hull: PackedInt32Array
) -> bool:
	if index < solids.size():
		var code_p: int = codes_a[index * na + pi]
		if code_p == 0:
			return true
		var count: int = planes[index]
		for qi: int in hull:
			var code_q: int = codes_b[index * nb + qi]
			if code_p & code_q != 0:
				return false
			if code_q == 0:
				continue
			if not SightGeometry.rooms_blocked(rooms_a[index], pi * count, rooms_b[index], qi * count, count):
				return false
		return true
	var c: SightCylinder = cylinders[index - solids.size()]
	for qi: int in hull:
		if not SightGeometry.segment_blocked_by_cylinder(p, to_points[qi], c.base, c.axis, c.radius, c.height):
			return false
	return true


## Everything in the lists that blocks the segment: indices of solids, or
## the number of solids plus the index of a cylinder; -2 for the tabletop.
## Empty if the segment is clear.
static func _all_blockers(
	p: Vector3, q: Vector3, solids: Array[SightGeometry.Solid], cylinders: Array[SightCylinder]
) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if SightGeometry.segment_blocked_by_table(p, q):
		result.append(-2)
	var lo: Vector3 = p.min(q)
	var hi: Vector3 = p.max(q)
	for i: int in solids.size():
		var solid: SightGeometry.Solid = solids[i]
		if SightGeometry.boxes_overlap(lo, hi, solid.bounds_min, solid.bounds_max) and SightGeometry.segment_blocked_by_solid(p, q, solid):
			result.append(i)
	for i: int in cylinders.size():
		var c: SightCylinder = cylinders[i]
		if SightGeometry.boxes_overlap(lo, hi, c.bounds_min, c.bounds_max) and SightGeometry.segment_blocked_by_cylinder(p, q, c.base, c.axis, c.radius, c.height):
			result.append(solids.size() + i)
	return result


## The sample pairs tried first (indices into the two sample lists): the
## axis points level with each other, and at each ring level the rim points
## furthest to either side of the line between the cylinders.
static func _probes(a: SightCylinder, b: SightCylinder) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var axis_count: int = SightCylinder.AXIS_LEVELS.size()
	for k: int in axis_count:
		result.append(Vector2i(k, k))
	var side: Vector3 = (b.middle - a.middle).cross(Vector3.UP)
	if side.length_squared() < 1e-9:
		side = Vector3.RIGHT
	var a_points: PackedVector3Array = a.sample_points()
	var b_points: PackedVector3Array = b.sample_points()
	for level: int in SightCylinder.RING_LEVELS.size():
		var first: int = axis_count + level * SightCylinder.RING_POINTS
		result.append(Vector2i(_furthest(a_points, first, a.middle, side), _furthest(b_points, first, b.middle, side)))
		result.append(Vector2i(_furthest(a_points, first, a.middle, -side), _furthest(b_points, first, b.middle, -side)))
	return result


## Of the ring points from `first`, the one furthest along `direction`.
static func _furthest(points: PackedVector3Array, first: int, centre: Vector3, direction: Vector3) -> int:
	var best: int = first
	var best_value: float = -INF
	for k: int in range(first, first + SightCylinder.RING_POINTS):
		var value: float = (points[k] - centre).dot(direction)
		if value > best_value + 1e-9:
			best_value = value
			best = k
	return best


## Whether blocker `index` (as in _all_blockers()) stops every segment from
## a point of `a_corners` to a point of `b_corners`.
static func _blocks_between(
	a_corners: PackedVector3Array, b_corners: PackedVector3Array, index: int,
	solids: Array[SightGeometry.Solid], cylinders: Array[SightCylinder]
) -> bool:
	if index < solids.size():
		var solid: SightGeometry.Solid = solids[index]
		var count: int = solid.normals.size()
		var codes_a: PackedInt32Array = PackedInt32Array()
		var codes_b: PackedInt32Array = PackedInt32Array()
		codes_a.resize(a_corners.size())
		codes_b.resize(b_corners.size())
		var rooms_a: PackedFloat64Array = _solid_rooms(solid, a_corners, codes_a, 0)
		var rooms_b: PackedFloat64Array = _solid_rooms(solid, b_corners, codes_b, 0)
		for i: int in a_corners.size():
			for j: int in b_corners.size():
				if codes_a[i] & codes_b[j] != 0:
					return false
				if codes_a[i] == 0 or codes_b[j] == 0:
					continue
				if not SightGeometry.rooms_blocked(rooms_a, i * count, rooms_b, j * count, count):
					return false
		return true
	var c: SightCylinder = cylinders[index - solids.size()]
	for p: Vector3 in a_corners:
		for q: Vector3 in b_corners:
			if not SightGeometry.segment_blocked_by_cylinder(p, q, c.base, c.axis, c.radius, c.height):
				return false
	return true


## The rooms of every point against every face of `solid`, in one array
## (point by point), with each point's outcode written to codes[at + k].
static func _solid_rooms(
	solid: SightGeometry.Solid, points: PackedVector3Array, codes: PackedInt32Array, at: int
) -> PackedFloat64Array:
	var count: int = solid.normals.size()
	var rooms: PackedFloat64Array = PackedFloat64Array()
	rooms.resize(points.size() * count)
	for k: int in points.size():
		var p: Vector3 = points[k]
		var code: int = 0
		for j: int in count:
			var room: float = solid.offsets[j] - solid.margins[j] - solid.normals[j].dot(p)
			rooms[k * count + j] = room
			if room <= 0.0:
				code |= 1 << j
		codes[at + k] = code
	return rooms


## Outcodes against a cylinder: below its underside, above its top, and
## outside each side of the square round it.
static func _cylinder_codes(c: SightCylinder, points: PackedVector3Array, codes: PackedInt32Array, at: int) -> void:
	var e1: Vector3 = c.side_x
	var e2: Vector3 = c.side_z
	var r: float = c.radius - SightGeometry.TOLERANCE
	var low: float = -SightGeometry.TOLERANCE
	var high: float = c.height - SightGeometry.TOLERANCE
	for k: int in points.size():
		var rel: Vector3 = points[k] - c.base
		var along: float = rel.dot(c.axis)
		var u: float = rel.dot(e1)
		var v: float = rel.dot(e2)
		var code: int = 0
		if along <= low:
			code |= 1
		if along >= high:
			code |= 2
		if u >= r:
			code |= 4
		if u <= -r:
			code |= 8
		if v >= r:
			code |= 16
		if v <= -r:
			code |= 32
		codes[at + k] = code


static func _point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var d: Vector3 = b - a
	var length_squared: float = d.length_squared()
	if length_squared < 1e-12:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(d) / length_squared, 0.0, 1.0)
	return p.distance_to(a + d * t)
