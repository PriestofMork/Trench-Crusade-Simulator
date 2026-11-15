extends GutTest

const EPS: float = 0.0001


func test_point_segment_distance() -> void:
	var a: Vector2 = Vector2(0, 0)
	var b: Vector2 = Vector2(10, 0)
	assert_almost_eq(PlanarGeometry.point_segment_distance(Vector2(5, 3), a, b), 3.0, EPS)
	assert_almost_eq(PlanarGeometry.point_segment_distance(Vector2(-4, 3), a, b), 5.0, EPS)
	assert_almost_eq(PlanarGeometry.point_segment_distance(Vector2(13, 4), a, b), 5.0, EPS)
	assert_almost_eq(PlanarGeometry.point_segment_distance(Vector2(1, 1), a, a), sqrt(2.0), EPS)


func test_rect_local_round_trip() -> void:
	var centre: Vector2 = Vector2(3, -2)
	var p: Vector2 = Vector2(7.5, 1.25)
	var local: Vector2 = PlanarGeometry.to_rect_local(p, centre, 0.7)
	var back: Vector2 = PlanarGeometry.from_rect_local(local, centre, 0.7)
	assert_almost_eq(back.x, p.x, EPS)
	assert_almost_eq(back.y, p.y, EPS)


func test_rotation_matches_node3d_rotation_y() -> void:
	# A Node3D turned by +90 degrees about y maps its local +x axis to world -z.
	var basis: Basis = Basis(Vector3.UP, PI / 2.0)
	var world: Vector3 = basis * Vector3(1, 0, 0)
	var ours: Vector2 = PlanarGeometry.from_rect_local(Vector2(1, 0), Vector2.ZERO, PI / 2.0)
	assert_almost_eq(ours.x, world.x, EPS)
	assert_almost_eq(ours.y, world.z, EPS)


func test_point_rect_signed_distance() -> void:
	var centre: Vector2 = Vector2(10, 10)
	var half: Vector2 = Vector2(2, 1)
	assert_almost_eq(PlanarGeometry.point_rect_signed_distance(Vector2(15, 10), centre, half, 0.0), 3.0, EPS)
	assert_almost_eq(PlanarGeometry.point_rect_signed_distance(Vector2(10, 10), centre, half, 0.0), -1.0, EPS)
	assert_almost_eq(PlanarGeometry.point_rect_signed_distance(Vector2(15, 15), centre, half, 0.0), 5.0, EPS)


func test_circle_against_axis_aligned_rect() -> void:
	var centre: Vector2 = Vector2.ZERO
	var half: Vector2 = Vector2(2, 1)
	assert_true(PlanarGeometry.circle_overlaps_rect(Vector2(2.9, 0), 1.0, centre, half, 0.0))
	assert_false(PlanarGeometry.circle_overlaps_rect(Vector2(3.0, 0), 1.0, centre, half, 0.0), "touching")
	assert_false(PlanarGeometry.circle_overlaps_rect(Vector2(3.1, 0), 1.0, centre, half, 0.0))
	assert_true(PlanarGeometry.circle_overlaps_rect(Vector2(0, 0), 0.1, centre, half, 0.0), "inside")


func test_circle_grazing_rotated_box_corner() -> void:
	# A 2x2 square turned 45 degrees: one corner points along +x at sqrt(2).
	var centre: Vector2 = Vector2(5, 5)
	var half: Vector2 = Vector2(1, 1)
	var rotation: float = PI / 4.0
	var corner_x: float = 5.0 + sqrt(2.0)
	var r: float = 0.5
	assert_true(PlanarGeometry.circle_overlaps_rect(Vector2(corner_x + r - 0.01, 5), r, centre, half, rotation))
	assert_false(PlanarGeometry.circle_overlaps_rect(Vector2(corner_x + r + 0.01, 5), r, centre, half, rotation))
	# Off the diagonal, close to where the unrotated square's corner would be:
	# the turned square has its edge further in, so this does not overlap.
	assert_false(PlanarGeometry.circle_overlaps_rect(Vector2(6.3, 6.3), r, centre, half, rotation))
	assert_true(PlanarGeometry.circle_overlaps_rect(Vector2(6.3, 6.3), r, centre, half, 0.0))


func test_segment_rect_distance() -> void:
	var centre: Vector2 = Vector2.ZERO
	var half: Vector2 = Vector2(1, 1)
	# Crossing straight through.
	assert_almost_eq(PlanarGeometry.segment_rect_distance(Vector2(-5, 0), Vector2(5, 0), centre, half, 0.0), 0.0, EPS)
	# Passing alongside, 2 above the top edge.
	assert_almost_eq(PlanarGeometry.segment_rect_distance(Vector2(-5, 3), Vector2(5, 3), centre, half, 0.0), 2.0, EPS)
	# Ends well away from the box, closest approach is the box corner to the segment middle.
	var d: float = PlanarGeometry.segment_rect_distance(Vector2(0, 4), Vector2(4, 0), centre, half, 0.0)
	assert_almost_eq(d, Vector2(2, 2).distance_to(Vector2(1, 1)), EPS)
	# Segment entirely inside.
	assert_almost_eq(PlanarGeometry.segment_rect_distance(Vector2(-0.5, 0), Vector2(0.5, 0), centre, half, 0.0), 0.0, EPS)


func test_swept_circle_past_rotated_corner() -> void:
	# The diamond's corner points along +y at sqrt(2). A circle sweeping sideways
	# just above it grazes it or not depending on its radius.
	var centre: Vector2 = Vector2.ZERO
	var half: Vector2 = Vector2(1, 1)
	var rotation: float = PI / 4.0
	var a: Vector2 = Vector2(-5, sqrt(2.0) + 0.5)
	var b: Vector2 = Vector2(5, sqrt(2.0) + 0.5)
	assert_false(PlanarGeometry.swept_circle_overlaps_rect(a, b, 0.49, centre, half, rotation))
	assert_true(PlanarGeometry.swept_circle_overlaps_rect(a, b, 0.51, centre, half, rotation))
	# Unrotated, the top edge is at y = 1, so even a smaller base hits it lower down.
	assert_true(PlanarGeometry.swept_circle_overlaps_rect(a - Vector2(0, 0.6), b - Vector2(0, 0.6), 0.49, centre, half, 0.0))
	assert_true(PlanarGeometry.swept_circle_overlaps_rect(a - Vector2(0, 0.6), b - Vector2(0, 0.6), 0.49, centre, half, rotation), "and the diamond corner too")


func test_swept_circle_within_point() -> void:
	var a: Vector2 = Vector2(0, 0)
	var b: Vector2 = Vector2(10, 0)
	assert_true(PlanarGeometry.swept_circle_within(a, b, Vector2(5, 1.9), 2.0))
	assert_false(PlanarGeometry.swept_circle_within(a, b, Vector2(5, 2.0), 2.0), "exactly at the limit")
	assert_false(PlanarGeometry.swept_circle_within(a, b, Vector2(13, 0), 2.0))
