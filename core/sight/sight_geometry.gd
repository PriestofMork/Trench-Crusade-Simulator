class_name SightGeometry
extends RefCounted
## Segment tests for line of sight (brief 008): does a straight segment from a
## to b pass through a terrain solid, a model's (possibly tilted) cylinder or
## the tabletop? Pure functions on plain data.
##
## Touching is not blocking (ruling 6): the sides and the top of every solid
## are pulled in by TOLERANCE before the test, so a segment that only grazes
## a side, a top or an edge, or runs along a top (the floor a model stands
## on), is clear. Undersides are the one exception: they are pushed *down*
## by TOLERANCE, because a solid's underside rests on a floor, and a segment
## running along that floor must be blocked by what stands on it, not slip
## through the seam between the two. TOLERANCE is the one value for this;
## nothing else in sight may use its own.

## Inches. See above.
const TOLERANCE: float = 0.001
const PARALLEL: float = 1e-12


## A convex solid as planes: a point p is inside where, for every plane i,
## normals[i].dot(p) <= offsets[i]. Normals are unit length, so the offsets
## are in inches. With its bounding box for quick rejects.
class Solid:
	extends RefCounted
	var normals: PackedVector3Array = PackedVector3Array()
	var offsets: PackedFloat64Array = PackedFloat64Array()
	## Per plane: pulled in by TOLERANCE (sides, top) or pushed out (underside).
	var margins: PackedFloat64Array = PackedFloat64Array()
	var bounds_min: Vector3
	var bounds_max: Vector3
	## The sphere round the bounding box, for quick rejects.
	var sphere_centre: Vector3
	var sphere_radius: float
	## The terrain piece it was built from, -1 if none.
	var piece_id: int = -1

	## For each plane, how far p is inside it (after the margin): positive
	## inside, zero or less outside.
	func rooms(p: Vector3) -> PackedFloat64Array:
		var result: PackedFloat64Array = PackedFloat64Array()
		result.resize(normals.size())
		for j: int in normals.size():
			result[j] = offsets[j] - margins[j] - normals[j].dot(p)
		return result

	func add_plane(normal: Vector3, offset: float, underside: bool = false) -> void:
		var length: float = normal.length()
		normals.append(normal / length)
		offsets.append(offset / length)
		margins.append(-TOLERANCE if underside else TOLERANCE)


## The solid of a terrain piece (see TerrainPiece): its footprint rectangle,
## its flat underside and its top (flat for a box, the rising plane of a ramp).
static func piece_solid(piece: TerrainPiece) -> Solid:
	var solid: Solid = Solid.new()
	solid.piece_id = piece.id
	var centre: Vector3 = Vector3(piece.footprint_center.x, 0.0, piece.footprint_center.y)
	var axis_x: Vector2 = piece.local_x_axis()
	var ex: Vector3 = Vector3(axis_x.x, 0.0, axis_x.y)
	# The piece's own z axis, as Node3D.rotation.y turns it.
	var ez: Vector3 = Vector3(sin(piece.rotation), 0.0, cos(piece.rotation))
	var half: Vector2 = piece.footprint_half_extents()
	solid.add_plane(ex, ex.dot(centre) + half.x)
	solid.add_plane(-ex, -ex.dot(centre) + half.x)
	solid.add_plane(ez, ez.dot(centre) + half.y)
	solid.add_plane(-ez, -ez.dot(centre) + half.y)
	solid.add_plane(Vector3.DOWN, -piece.base_height, true)
	var gradient: Vector2 = piece.top_gradient()
	# y <= top_at_center + gradient . (p - centre)
	solid.add_plane(
		Vector3(-gradient.x, 1.0, -gradient.y),
		piece.top_at_center() - gradient.x * centre.x - gradient.y * centre.z
	)
	var corner_reach: Vector3 = (ex * half.x).abs() + (ez * half.y).abs()
	solid.bounds_min = Vector3(centre.x - corner_reach.x, piece.base_height, centre.z - corner_reach.z)
	solid.bounds_max = Vector3(centre.x + corner_reach.x, piece.top_max(), centre.z + corner_reach.z)
	solid.sphere_centre = (solid.bounds_min + solid.bounds_max) / 2.0
	solid.sphere_radius = (solid.bounds_max - solid.bounds_min).length() / 2.0
	return solid


## Whether the segment from a to b passes through the inside of `solid`
## (with the margins above).
static func segment_blocked_by_solid(a: Vector3, b: Vector3, solid: Solid) -> bool:
	var rooms_a: PackedFloat64Array = solid.rooms(a)
	var rooms_b: PackedFloat64Array = solid.rooms(b)
	return rooms_blocked(rooms_a, 0, rooms_b, 0, solid.normals.size())


## The clipping step of segment_blocked_by_solid() on precomputed rooms (see
## Solid.rooms()): the rooms of a start at rooms_a[ia], those of b at
## rooms_b[ib], `count` planes each. Line of sight computes the rooms once per
## sample point and reuses them for every segment.
static func rooms_blocked(
	rooms_a: PackedFloat64Array, ia: int, rooms_b: PackedFloat64Array, ib: int, count: int
) -> bool:
	var t0: float = 0.0
	var t1: float = 1.0
	for j: int in count:
		var ra: float = rooms_a[ia + j]
		var rb: float = rooms_b[ib + j]
		if ra > 0.0:
			if rb > 0.0:
				continue
			# Leaves this plane's inside where the room runs out.
			t1 = minf(t1, ra / (ra - rb))
		elif rb > 0.0:
			t0 = maxf(t0, ra / (ra - rb))
		else:
			return false
		if t0 >= t1:
			return false
	return t0 < t1


## Whether the segment from a to b passes through the inside of the cylinder
## whose underside centre is `base`, with unit axis `axis`: its side and top
## pulled in by TOLERANCE, its underside pushed down by it (as for solids).
static func segment_blocked_by_cylinder(
	a: Vector3, b: Vector3, base: Vector3, axis: Vector3, radius: float, height: float
) -> bool:
	var rel: Vector3 = a - base
	var d: Vector3 = b - a
	var t0: float = 0.0
	var t1: float = 1.0
	# Between the underside and the top.
	var along: float = rel.dot(axis)
	var along_rate: float = d.dot(axis)
	var low: float = -TOLERANCE
	var high: float = height - TOLERANCE
	if absf(along_rate) < PARALLEL:
		if along <= low or along >= high:
			return false
	else:
		var ta: float = (low - along) / along_rate
		var tb: float = (high - along) / along_rate
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 >= t1:
			return false
	# Within the radius of the axis.
	var across: Vector3 = rel - axis * along
	var across_rate: Vector3 = d - axis * along_rate
	var r: float = radius - TOLERANCE
	var qa: float = across_rate.dot(across_rate)
	var qb: float = 2.0 * across.dot(across_rate)
	var qc: float = across.dot(across) - r * r
	if qa < PARALLEL:
		return qc < 0.0
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return false
	var root: float = sqrt(disc)
	t0 = maxf(t0, (-qb - root) / (2.0 * qa))
	t1 = minf(t1, (-qb + root) / (2.0 * qa))
	return t0 < t1


## Whether the segment from a to b goes into the tabletop (below y = 0 by
## more than TOLERANCE). The tabletop is the plane y = 0 and everything
## under it.
static func segment_blocked_by_table(a: Vector3, b: Vector3) -> bool:
	return minf(a.y, b.y) < -TOLERANCE


## Whether two boxes overlap.
static func boxes_overlap(min_a: Vector3, max_a: Vector3, min_b: Vector3, max_b: Vector3) -> bool:
	return (
		min_a.x <= max_b.x and max_a.x >= min_b.x
		and min_a.y <= max_b.y and max_a.y >= min_b.y
		and min_a.z <= max_b.z and max_a.z >= min_b.z
	)
