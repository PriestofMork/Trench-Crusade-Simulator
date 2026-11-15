class_name PlanarGeometry
extends RefCounted
## 2D geometry on the table plane. A Vector2 here is (world x, world z).
## Rectangles are oriented: centre, half extents along their own axes, and a
## rotation about the vertical axis with the same sign as Node3D.rotation.y.


static func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq <= 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## World point -> the rectangle's own frame (centre at origin, axis aligned).
static func to_rect_local(p: Vector2, center: Vector2, rotation: float) -> Vector2:
	var d: Vector2 = p - center
	var c: float = cos(rotation)
	var s: float = sin(rotation)
	return Vector2(d.x * c - d.y * s, d.x * s + d.y * c)


## Rectangle frame -> world point. Inverse of to_rect_local().
static func from_rect_local(local: Vector2, center: Vector2, rotation: float) -> Vector2:
	var c: float = cos(rotation)
	var s: float = sin(rotation)
	return center + Vector2(local.x * c + local.y * s, -local.x * s + local.y * c)


## Signed distance from a point to an oriented rectangle: positive outside,
## negative inside, 0 on its edge.
static func point_rect_signed_distance(
	p: Vector2, center: Vector2, half_extents: Vector2, rotation: float
) -> float:
	var local: Vector2 = to_rect_local(p, center, rotation)
	return _local_box_signed_distance(local, half_extents)


## Shortest distance between a segment and an oriented rectangle; 0 if they touch
## or intersect.
static func segment_rect_distance(
	a: Vector2, b: Vector2, center: Vector2, half_extents: Vector2, rotation: float
) -> float:
	var la: Vector2 = to_rect_local(a, center, rotation)
	var lb: Vector2 = to_rect_local(b, center, rotation)
	if _segment_hits_local_box(la, lb, half_extents):
		return 0.0
	# Both shapes are convex and apart, so the closest pair involves an endpoint
	# of the segment or a corner of the box.
	var best: float = minf(
		_local_box_signed_distance(la, half_extents), _local_box_signed_distance(lb, half_extents)
	)
	var hx: float = half_extents.x
	var hy: float = half_extents.y
	for corner: Vector2 in [Vector2(hx, hy), Vector2(-hx, hy), Vector2(-hx, -hy), Vector2(hx, -hy)]:
		best = minf(best, point_segment_distance(corner, la, lb))
	return best


## Whether a circle overlaps an oriented rectangle. Touching is not overlapping.
static func circle_overlaps_rect(
	circle_center: Vector2,
	radius: float,
	center: Vector2,
	half_extents: Vector2,
	rotation: float,
	epsilon: float = 0.0001
) -> bool:
	return point_rect_signed_distance(circle_center, center, half_extents, rotation) < radius - epsilon


## Whether a circle swept from a to b overlaps an oriented rectangle at any point.
static func swept_circle_overlaps_rect(
	a: Vector2,
	b: Vector2,
	radius: float,
	center: Vector2,
	half_extents: Vector2,
	rotation: float,
	epsilon: float = 0.0001
) -> bool:
	return segment_rect_distance(a, b, center, half_extents, rotation) < radius - epsilon


## Whether a circle swept from a to b comes closer than `min_distance` (centre to
## centre) to a fixed point.
static func swept_circle_within(
	a: Vector2, b: Vector2, point: Vector2, min_distance: float, epsilon: float = 0.0001
) -> bool:
	return point_segment_distance(point, a, b) < min_distance - epsilon


static func _local_box_signed_distance(local: Vector2, half_extents: Vector2) -> float:
	var q: Vector2 = local.abs() - half_extents
	var outside: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var inside: float = minf(maxf(q.x, q.y), 0.0)
	return outside + inside


## Liang-Barsky clip of segment a-b against the box [-h, h].
static func _segment_hits_local_box(a: Vector2, b: Vector2, h: Vector2) -> bool:
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = b - a
	var p: Array[float] = [-d.x, d.x, -d.y, d.y]
	var q: Array[float] = [a.x + h.x, h.x - a.x, a.y + h.y, h.y - a.y]
	for i: int in 4:
		if p[i] == 0.0:
			if q[i] < 0.0:
				return false
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return false
	return true


# Convex polygons. A polygon is a PackedVector2Array of corners in order, either
# way round, without repeating the first corner. Fewer than three corners (or
# no area) is a degenerate polygon: a segment or a point, with no inside.


## Corners of an oriented rectangle, in order.
static func rect_polygon(center: Vector2, half_extents: Vector2, rotation: float) -> PackedVector2Array:
	var hx: float = half_extents.x
	var hy: float = half_extents.y
	var polygon: PackedVector2Array = PackedVector2Array()
	for local: Vector2 in [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]:
		polygon.append(from_rect_local(local, center, rotation))
	return polygon


## The part of a convex polygon where normal.dot(q) + offset >= 0.
static func clip_polygon(polygon: PackedVector2Array, normal: Vector2, offset: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var n: int = polygon.size()
	for i: int in n:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % n]
		var fa: float = normal.dot(a) + offset
		var fb: float = normal.dot(b) + offset
		if fa >= 0.0:
			result.append(a)
		if (fa >= 0.0) != (fb >= 0.0):
			result.append(a.lerp(b, fa / (fa - fb)))
	return result


## Twice the signed area: positive when the corners run counter-clockwise in (x, z).
static func polygon_double_area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	var n: int = polygon.size()
	for i: int in n:
		total += polygon[i].cross(polygon[(i + 1) % n])
	return total


## Signed distance from p to a convex polygon: positive outside, negative inside.
static func point_polygon_signed_distance(p: Vector2, polygon: PackedVector2Array) -> float:
	var n: int = polygon.size()
	if n == 0:
		return INF
	if n == 1:
		return p.distance_to(polygon[0])
	var area: float = polygon_double_area(polygon)
	var outside: float = INF
	var inside: float = INF
	var is_inside: bool = absf(area) > 1e-12
	var orientation: float = signf(area)
	for i: int in n:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % n]
		outside = minf(outside, point_segment_distance(p, a, b))
		if is_inside:
			var edge: Vector2 = b - a
			var length: float = edge.length()
			if length <= 1e-12:
				continue
			# Distance to the edge line, positive on the inner side.
			var d: float = orientation * edge.cross(p - a) / length
			if d < 0.0:
				is_inside = false
			else:
				inside = minf(inside, d)
	if is_inside:
		return -inside
	return outside


## Shortest distance between segment a-b and a convex polygon; 0 if they touch.
static func segment_polygon_distance(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> float:
	var n: int = polygon.size()
	if n == 0:
		return INF
	var best: float = minf(
		maxf(point_polygon_signed_distance(a, polygon), 0.0),
		maxf(point_polygon_signed_distance(b, polygon), 0.0)
	)
	if best <= 0.0:
		return 0.0
	for i: int in n:
		var c: Vector2 = polygon[i]
		var d: Vector2 = polygon[(i + 1) % n]
		if segments_intersect(a, b, c, d):
			return 0.0
		best = minf(best, point_segment_distance(c, a, b))
	return best


static func segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab: Vector2 = b - a
	var cd: Vector2 = d - c
	var d1: float = ab.cross(c - a)
	var d2: float = ab.cross(d - a)
	var d3: float = cd.cross(a - c)
	var d4: float = cd.cross(b - c)
	if ((d1 > 0.0 and d2 < 0.0) or (d1 < 0.0 and d2 > 0.0)) and ((d3 > 0.0 and d4 < 0.0) or (d3 < 0.0 and d4 > 0.0)):
		return true
	return false


## Exact area of the overlap of a circle and a convex polygon.
static func circle_polygon_area(center: Vector2, radius: float, polygon: PackedVector2Array) -> float:
	var n: int = polygon.size()
	if n < 3:
		return 0.0
	var total: float = 0.0
	for i: int in n:
		total += _circle_triangle_signed_area(polygon[i] - center, polygon[(i + 1) % n] - center, radius)
	return absf(total)


## Signed area of the overlap of the circle (origin, r) and the triangle (origin, a, b).
static func _circle_triangle_signed_area(a: Vector2, b: Vector2, r: float) -> float:
	var r2: float = r * r
	var la2: float = a.length_squared()
	var lb2: float = b.length_squared()
	if la2 <= r2 and lb2 <= r2:
		return a.cross(b) * 0.5
	var d: Vector2 = b - a
	var qa: float = d.length_squared()
	if qa <= 1e-18:
		return 0.0
	var qb: float = a.dot(d)
	var qc: float = la2 - r2
	var disc: float = qb * qb - qa * qc
	if disc <= 0.0:
		return _sector(a, b, r2)
	var s: float = sqrt(disc)
	var t1: float = (-qb - s) / qa
	var t2: float = (-qb + s) / qa
	if t2 <= 0.0 or t1 >= 1.0:
		return _sector(a, b, r2)
	var p1: Vector2 = a + d * maxf(t1, 0.0)
	var p2: Vector2 = a + d * minf(t2, 1.0)
	var area: float = p1.cross(p2) * 0.5
	if la2 > r2:
		area += _sector(a, p1, r2)
	if lb2 > r2:
		area += _sector(p2, b, r2)
	return area


static func _sector(u: Vector2, v: Vector2, r2: float) -> float:
	return 0.5 * r2 * atan2(u.cross(v), u.dot(v))


## Closest point on segment a-b to p.
static func closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq <= 0.0:
		return a
	return a + ab * clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)


## Closest point of a convex polygon's boundary to p (for p outside, the
## closest point of the polygon).
static func closest_point_on_polygon(p: Vector2, polygon: PackedVector2Array) -> Vector2:
	var best: Vector2 = polygon[0]
	var best_distance: float = INF
	var n: int = polygon.size()
	for i: int in n:
		var q: Vector2 = closest_point_on_segment(p, polygon[i], polygon[(i + 1) % n])
		var d: float = p.distance_squared_to(q)
		if d < best_distance:
			best_distance = d
			best = q
	return best


## The part of segment a-b inside a convex polygon, as parameters (t0, t1) along
## it (0 at a, 1 at b); t0 > t1 if it misses.
static func segment_polygon_clip(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> Vector2:
	var t0: float = 0.0
	var t1: float = 1.0
	var n: int = polygon.size()
	if n < 3:
		return Vector2(1, 0)
	var orientation: float = signf(polygon_double_area(polygon))
	var d: Vector2 = b - a
	for i: int in n:
		var e0: Vector2 = polygon[i]
		var edge: Vector2 = polygon[(i + 1) % n] - e0
		# Inside where orientation * edge.cross(q - e0) >= 0, linear along the segment.
		var f0: float = orientation * edge.cross(a - e0)
		var df: float = orientation * edge.cross(d)
		if absf(df) < 1e-12:
			if f0 < 0.0:
				return Vector2(1, 0)
			continue
		var t: float = -f0 / df
		if df > 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return Vector2(1, 0)
	return Vector2(t0, t1)
