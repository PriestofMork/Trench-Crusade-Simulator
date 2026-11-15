class_name ConvexShape
extends RefCounted
## A convex polygon on the table plane with what is needed to measure distances
## to it quickly. Rectangles (most footprints) use closed forms; other convex
## polygons (footprints clipped by a slope) use precomputed edge data. Same
## results as the PlanarGeometry polygon functions, only faster.

var polygon: PackedVector2Array
var is_rect: bool = false
## Rectangle: centre, unit axes and half extents.
var center: Vector2
var axis_x: Vector2
var axis_z: Vector2
var half: Vector2
## Bounding circle, for quick rejects.
var bound_center: Vector2
var bound_radius: float
## General polygon: per edge, start corner, edge vector, 1 / length^2, outward
## unit normal and the normal's offset (normal . corner).
var _starts: PackedVector2Array = PackedVector2Array()
var _edges: PackedVector2Array = PackedVector2Array()
var _inverse_lengths: PackedFloat64Array = PackedFloat64Array()
var _normals: PackedVector2Array = PackedVector2Array()
var _offsets: PackedFloat64Array = PackedFloat64Array()


static func from_polygon(p_polygon: PackedVector2Array) -> ConvexShape:
	var shape: ConvexShape = ConvexShape.new()
	shape.polygon = p_polygon
	var n: int = p_polygon.size()
	var centre: Vector2 = Vector2.ZERO
	for corner: Vector2 in p_polygon:
		centre += corner
	if n > 0:
		centre /= n
	shape.bound_center = centre
	shape.bound_radius = 0.0
	for corner: Vector2 in p_polygon:
		shape.bound_radius = maxf(shape.bound_radius, centre.distance_to(corner))
	var orientation: float = signf(PlanarGeometry.polygon_double_area(p_polygon))
	for i: int in n:
		var a: Vector2 = p_polygon[i]
		var edge: Vector2 = p_polygon[(i + 1) % n] - a
		var length_sq: float = edge.length_squared()
		shape._starts.append(a)
		shape._edges.append(edge)
		shape._inverse_lengths.append(1.0 / length_sq if length_sq > 1e-18 else 0.0)
		var normal: Vector2 = Vector2(edge.y, -edge.x).normalized() * orientation
		shape._normals.append(normal)
		shape._offsets.append(normal.dot(a))
	if n == 4 and orientation != 0.0:
		var e0: Vector2 = shape._edges[0]
		var e1: Vector2 = shape._edges[1]
		var e2: Vector2 = shape._edges[2]
		if absf(e0.dot(e1)) <= 1e-6 * e0.length() * e1.length() and (e0 + e2).length() <= 1e-6 * e0.length():
			shape.is_rect = true
			shape.center = centre
			shape.axis_x = e0.normalized()
			shape.axis_z = e1.normalized()
			shape.half = Vector2(e0.length(), e1.length()) * 0.5
	return shape


## Signed distance from p: positive outside, negative inside.
func signed_distance(p: Vector2) -> float:
	if is_rect:
		var d: Vector2 = p - center
		var qx: float = absf(d.dot(axis_x)) - half.x
		var qz: float = absf(d.dot(axis_z)) - half.y
		if qx <= 0.0 and qz <= 0.0:
			return maxf(qx, qz)
		var ox: float = maxf(qx, 0.0)
		var oz: float = maxf(qz, 0.0)
		return sqrt(ox * ox + oz * oz)
	var n: int = _starts.size()
	if n < 3:
		return PlanarGeometry.point_polygon_signed_distance(p, polygon)
	var worst: float = -INF
	for i: int in n:
		worst = maxf(worst, _normals[i].dot(p) - _offsets[i])
	if worst <= 0.0:
		return worst
	var best: float = INF
	for i: int in n:
		if _normals[i].dot(p) - _offsets[i] < -1e-9:
			continue
		var a: Vector2 = _starts[i]
		var edge: Vector2 = _edges[i]
		var t: float = clampf((p - a).dot(edge) * _inverse_lengths[i], 0.0, 1.0)
		best = minf(best, p.distance_squared_to(a + edge * t))
	return sqrt(best)


## Shortest distance between segment a-b and the shape; 0 if they touch.
func segment_distance(a: Vector2, b: Vector2) -> float:
	if not is_rect:
		return PlanarGeometry.segment_polygon_distance(a, b, polygon)
	var da: Vector2 = a - center
	var db: Vector2 = b - center
	var la: Vector2 = Vector2(da.dot(axis_x), da.dot(axis_z))
	var lb: Vector2 = Vector2(db.dot(axis_x), db.dot(axis_z))
	# Liang-Barsky clip against the box [-half, half].
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = lb - la
	var hits: bool = true
	for k: int in 4:
		var pk: float
		var qk: float
		match k:
			0:
				pk = -d.x
				qk = la.x + half.x
			1:
				pk = d.x
				qk = half.x - la.x
			2:
				pk = -d.y
				qk = la.y + half.y
			_:
				pk = d.y
				qk = half.y - la.y
		if pk == 0.0:
			if qk < 0.0:
				hits = false
				break
		else:
			var t: float = qk / pk
			if pk < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				hits = false
				break
	if hits:
		return 0.0
	# Apart and convex: the closest pair has an end of the segment or a corner.
	var best: float = minf(_local_rect_distance(la), _local_rect_distance(lb))
	for corner: Vector2 in [Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y), Vector2(half.x, -half.y)]:
		best = minf(best, PlanarGeometry.point_segment_distance(corner, la, lb))
	return best


func _local_rect_distance(local: Vector2) -> float:
	var ox: float = maxf(absf(local.x) - half.x, 0.0)
	var oz: float = maxf(absf(local.y) - half.y, 0.0)
	return sqrt(ox * ox + oz * oz)
