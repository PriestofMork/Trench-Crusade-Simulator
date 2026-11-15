class_name MarchingSquares
extends RefCounted
## Contours a grid of values at level 0: inside where a value is <= 0.
## Works in grid coordinates (node (i, j) is at Vector2(i, j)); the caller maps
## them to the table. Produces fill triangles for the inside and the outline as
## chains of points, each oriented so that the inside lies to its left (see
## inside_normal()).


class Contour:
	extends RefCounted
	## Inside area, three points per triangle.
	var triangles: PackedVector2Array = PackedVector2Array()
	## The grid value at each triangle point (0 on the outline).
	var triangle_values: PackedFloat32Array = PackedFloat32Array()
	## Outline chains in order. A closed chain does not repeat its first point.
	var chains: Array[PackedVector2Array] = []
	var closed: Array[bool] = []


## Unit normal pointing to the inside for an outline segment going from a to b.
static func inside_normal(a: Vector2, b: Vector2) -> Vector2:
	var d: Vector2 = (b - a).normalized()
	return Vector2(-d.y, d.x)


static func build(values: PackedFloat32Array, size_x: int, size_z: int) -> Contour:
	var contour: Contour = Contour.new()
	if size_x < 2 or size_z < 2:
		return contour
	var points_by_key: Dictionary[int, Vector2] = {}
	var next_key: Dictionary[int, int] = {}

	for j: int in size_z - 1:
		for i: int in size_x - 1:
			# Fast paths for cells wholly outside or inside, which are most of them.
			var base: int = j * size_x + i
			var v0: float = values[base]
			var v1: float = values[base + 1]
			var v2: float = values[base + size_x + 1]
			var v3: float = values[base + size_x]
			if v0 > 0.0 and v1 > 0.0 and v2 > 0.0 and v3 > 0.0:
				continue
			if v0 <= 0.0 and v1 <= 0.0 and v2 <= 0.0 and v3 <= 0.0:
				var q0: Vector2 = Vector2(i, j)
				var q2: Vector2 = Vector2(i + 1, j + 1)
				contour.triangles.append_array(
					[q0, Vector2(i + 1, j), q2, q0, q2, Vector2(i, j + 1)]
				)
				contour.triangle_values.append_array([v0, v1, v2, v0, v2, v3])
				continue
			var corners: Array[Vector2i] = [
				Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)
			]
			var v: Array[float] = []
			var inside: Array[bool] = []
			var inside_count: int = 0
			for c: Vector2i in corners:
				var value: float = _value(values, size_x, c)
				v.append(value)
				inside.append(value <= 0.0)
				if value <= 0.0:
					inside_count += 1
			if inside_count == 0:
				continue
			if inside_count == 4:
				var p0: Vector2 = Vector2(corners[0])
				var p1: Vector2 = Vector2(corners[1])
				var p2: Vector2 = Vector2(corners[2])
				var p3: Vector2 = Vector2(corners[3])
				contour.triangles.append_array([p0, p1, p2, p0, p2, p3])
				contour.triangle_values.append_array([v[0], v[1], v[2], v[0], v[2], v[3]])
				continue

			# Walk round the cell, collecting inside corners and edge crossings.
			var polygon: Array[Vector2] = []
			var polygon_values: Array[float] = []
			var crossing_keys: Array[int] = []
			var crossing_leaves: Array[bool] = []  # true: inside -> outside along the walk
			for k: int in 4:
				var a: int = k
				var b: int = (k + 1) % 4
				if inside[a]:
					polygon.append(Vector2(corners[a]))
					polygon_values.append(v[a])
				if inside[a] != inside[b]:
					var key: int = _edge_key(corners[a], corners[b], size_x)
					if not points_by_key.has(key):
						points_by_key[key] = _edge_point(values, size_x, corners[a], corners[b])
					polygon.append(points_by_key[key])
					polygon_values.append(0.0)
					crossing_keys.append(key)
					crossing_leaves.append(inside[a])

			if crossing_keys.size() == 2:
				_fan(contour, polygon, polygon_values)
				var leave: int = 0 if crossing_leaves[0] else 1
				next_key[crossing_keys[leave]] = crossing_keys[1 - leave]
				continue

			# Saddle: two opposite corners inside. Decide by the cell centre.
			var centre_inside: bool = (v[0] + v[1] + v[2] + v[3]) * 0.25 <= 0.0
			for c: int in 4:
				if not crossing_leaves[c]:
					continue
				var partner: int = (c + 1) % 4 if centre_inside else (c + 3) % 4
				next_key[crossing_keys[c]] = crossing_keys[partner]
			if centre_inside:
				_fan(contour, polygon, polygon_values)
			else:
				for k: int in 4:
					if not inside[k]:
						continue
					var before: int = _edge_key(corners[(k + 3) % 4], corners[k], size_x)
					var after: int = _edge_key(corners[k], corners[(k + 1) % 4], size_x)
					contour.triangles.append_array(
						[Vector2(corners[k]), points_by_key[after], points_by_key[before]]
					)
					contour.triangle_values.append_array([v[k], 0.0, 0.0])

	_chain(contour, points_by_key, next_key)
	return contour


static func _chain(
	contour: Contour, points_by_key: Dictionary[int, Vector2], next_key: Dictionary[int, int]
) -> void:
	var has_previous: Dictionary[int, bool] = {}
	for key: int in next_key:
		has_previous[next_key[key]] = true
	var used: Dictionary[int, bool] = {}
	# Open chains first (only possible where the contour runs off the grid), then loops.
	var starts: Array[int] = []
	for key: int in next_key:
		if not has_previous.has(key):
			starts.append(key)
	for key: int in next_key:
		starts.append(key)
	for first: int in starts:
		if used.has(first):
			continue
		var chain: PackedVector2Array = PackedVector2Array()
		var key: int = first
		var closed: bool = false
		while true:
			used[key] = true
			chain.append(points_by_key[key])
			if not next_key.has(key):
				break
			key = next_key[key]
			if key == first:
				closed = true
				break
			if used.has(key):
				break
		if chain.size() >= 2:
			contour.chains.append(chain)
			contour.closed.append(closed)


static func _fan(contour: Contour, polygon: Array[Vector2], values: Array[float]) -> void:
	for k: int in range(1, polygon.size() - 1):
		contour.triangles.append_array([polygon[0], polygon[k], polygon[k + 1]])
		contour.triangle_values.append_array([values[0], values[k], values[k + 1]])


static func _value(values: PackedFloat32Array, size_x: int, c: Vector2i) -> float:
	return values[c.y * size_x + c.x]


## Every grid edge gets one id, whichever cell asks and in which direction.
static func _edge_key(a: Vector2i, b: Vector2i, size_x: int) -> int:
	var low: Vector2i = a if (a.y < b.y or (a.y == b.y and a.x < b.x)) else b
	var horizontal: int = 1 if a.y == b.y else 0
	return (low.y * size_x + low.x) * 2 + (0 if horizontal == 1 else 1)


## Where the value crosses 0 on an edge. Computed from the lower corner so both
## cells sharing the edge get exactly the same point.
static func _edge_point(values: PackedFloat32Array, size_x: int, a: Vector2i, b: Vector2i) -> Vector2:
	var low: Vector2i = a if (a.y < b.y or (a.y == b.y and a.x < b.x)) else b
	var high: Vector2i = b if low == a else a
	var vl: float = _value(values, size_x, low)
	var vh: float = _value(values, size_x, high)
	var t: float = 0.5
	if vl != vh:
		t = clampf(vl / (vl - vh), 0.0, 1.0)
	return Vector2(low).lerp(Vector2(high), t)
