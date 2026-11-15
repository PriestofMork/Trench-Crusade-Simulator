class_name TerrainPicker
extends RefCounted
## Where a ray from the camera first meets the table or a terrain piece, worked
## out from the terrain data (no physics), so the cursor can point at any
## floor: the top of a platform, a ramp, or the table under a bridge.


class Hit:
	extends RefCounted
	var point: Vector3
	var distance: float
	var normal: Vector3
	## -1 for the tabletop.
	var piece_id: int = -1


## The first hit along the ray, or null. `direction` must be normalised.
static func pick(state: GameState, origin: Vector3, direction: Vector3) -> Hit:
	var best: Hit = null
	for piece: TerrainPiece in state.terrain:
		var hit: Hit = _ray_piece(piece, origin, direction)
		if hit != null and (best == null or hit.distance < best.distance):
			best = hit
	if direction.y < -0.000001:
		var t: float = -origin.y / direction.y
		var p: Vector3 = origin + direction * t
		if (
			t > 0.0 and (best == null or t < best.distance)
			and p.x >= 0.0 and p.z >= 0.0 and p.x <= state.table_width and p.z <= state.table_depth
		):
			best = Hit.new()
			best.point = Vector3(p.x, 0.0, p.z)
			best.distance = t
			best.normal = Vector3.UP
	return best


## Ray against one piece as a convex solid (Cyrus-Beck clipping against its
## faces as half-spaces n.p <= d, in the piece's own frame).
static func _ray_piece(piece: TerrainPiece, origin: Vector3, direction: Vector3) -> Hit:
	var basis: Basis = Basis(Vector3.UP, piece.rotation)
	var centre: Vector3 = Vector3(piece.footprint_center.x, piece.base_height, piece.footprint_center.y)
	var o: Vector3 = basis.inverse() * (origin - centre)
	var d: Vector3 = basis.inverse() * direction
	var hx: float = piece.footprint_size.x / 2.0
	var hz: float = piece.footprint_size.y / 2.0
	var planes: Array[Plane] = [
		Plane(Vector3(1, 0, 0), hx), Plane(Vector3(-1, 0, 0), hx),
		Plane(Vector3(0, 0, 1), hz), Plane(Vector3(0, 0, -1), hz),
		Plane(Vector3(0, -1, 0), 0.0),
	]
	if piece.shape == TerrainPiece.Shape.RAMP:
		# Top: y <= h * (x + hx) / (2 hx).
		var slope: float = piece.height / piece.footprint_size.x
		planes.append(Plane(Vector3(-slope, 1, 0).normalized(), slope * hx / Vector3(-slope, 1, 0).length()))
	else:
		planes.append(Plane(Vector3(0, 1, 0), piece.height))
	var t_enter: float = 0.0
	var t_exit: float = INF
	var enter_normal: Vector3 = Vector3.ZERO
	for plane: Plane in planes:
		var denominator: float = plane.normal.dot(d)
		var distance: float = plane.d - plane.normal.dot(o)
		if absf(denominator) < 1e-9:
			if distance < 0.0:
				return null
			continue
		var t: float = distance / denominator
		if denominator < 0.0:
			if t > t_enter:
				t_enter = t
				enter_normal = plane.normal
		else:
			t_exit = minf(t_exit, t)
		if t_enter > t_exit:
			return null
	if enter_normal == Vector3.ZERO:
		return null  # The ray starts inside.
	var hit: Hit = Hit.new()
	hit.distance = t_enter
	hit.point = origin + direction * t_enter
	hit.normal = basis * enter_normal
	hit.piece_id = piece.id
	return hit
