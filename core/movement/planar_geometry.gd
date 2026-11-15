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
