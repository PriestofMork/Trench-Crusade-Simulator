class_name TerrainPiece
extends RefCounted
## One piece of terrain as the rules see it. Plain data; the 3D scene and every
## rules check are built from it.
##
## A piece is a solid over an oriented rectangle on the table (its footprint),
## turned about the vertical axis. Its underside is flat at `base_height`, so it
## can float (a bridge) or sit on another piece. Its top is:
## - BOX: flat at base_height + height;
## - RAMP: a plane rising along the piece's own x axis, from base_height at the
##   -x end to base_height + height at the +x end (a wedge when base_height is
##   the floor it stands on).

enum Shape { BOX, RAMP }
## See docs/rules/terrain.md, "Tags". NONE is open terrain.
enum Tag { NONE, SHEER, LADDER, IMPASSABLE }

var id: int
var shape: Shape
## Footprint centre on the table plane (world x, z), inches.
var footprint_center: Vector2
## Footprint size along the piece's own x and z axes, inches.
var footprint_size: Vector2
## Rotation about the vertical axis, radians, with the same sign as Node3D.rotation.y.
var rotation: float
## Height of the underside above the tabletop, inches.
var base_height: float
## Vertical extent from the underside to the highest point of the top, inches.
var height: float
var tag: Tag


func _init(
	p_id: int,
	p_footprint_center: Vector2,
	p_footprint_size: Vector2,
	p_rotation: float,
	p_base_height: float,
	p_height: float,
	p_tag: Tag = Tag.NONE,
	p_shape: Shape = Shape.BOX
) -> void:
	id = p_id
	footprint_center = p_footprint_center
	footprint_size = p_footprint_size
	rotation = p_rotation
	base_height = p_base_height
	height = p_height
	tag = p_tag
	shape = p_shape


## Half the footprint along the piece's own x and z axes.
func footprint_half_extents() -> Vector2:
	return footprint_size / 2.0


## The piece's own x axis on the table plane (the direction a ramp rises in).
func local_x_axis() -> Vector2:
	return Vector2(cos(rotation), -sin(rotation))


## Height of the top at the footprint centre.
func top_at_center() -> float:
	if shape == Shape.RAMP:
		return base_height + height / 2.0
	return base_height + height


## How the top rises per inch on the table plane (zero for a box).
func top_gradient() -> Vector2:
	if shape == Shape.RAMP:
		return local_x_axis() * (height / footprint_size.x)
	return Vector2.ZERO


## Height of the top's plane at p, extended past the footprint if p is outside it.
func top_plane_at(p: Vector2) -> float:
	return top_at_center() + top_gradient().dot(p - footprint_center)


## Highest point of the top.
func top_max() -> float:
	return base_height + height


## Angle of the top from the horizontal, degrees.
func slope_degrees() -> float:
	if shape == Shape.RAMP:
		return rad_to_deg(atan2(height, footprint_size.x))
	return 0.0


## Whether the top is a floor a model can stand on: not impassable, and not
## steeper than the steep angle (a steeper top is a wall).
func has_floor() -> bool:
	if tag == Tag.IMPASSABLE:
		return false
	return slope_degrees() <= TerrainRules.STEEP_SLOPE_DEGREES + 0.0001


## Centre of the piece's bounding box, for drawing.
func bounds_center() -> Vector3:
	return Vector3(footprint_center.x, base_height + height / 2.0, footprint_center.y)


## Size of the piece's bounding box along its own axes, for drawing.
func bounds_size() -> Vector3:
	return Vector3(footprint_size.x, height, footprint_size.y)
