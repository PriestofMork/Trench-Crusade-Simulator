class_name ReachGoal
extends RefCounted
## Where a goal-directed reach field is going (brief 008c): a set of points
## the base centre could end at, and a straight-line estimate of the cost
## still to go from any point to the nearest of them.
##
## The estimate is the distance on the table plane to a circle round
## `center` of radius `radius`, never less than 0. Every way of moving costs
## at least the distance covered on the table plane (walks cost their 3D
## length, crossings their horizontal distance plus any height, jumps their
## gap plus any rise), so as long as every goal point lies on or outside that
## circle the estimate never says more than the true cost: the search that
## uses it still finds the cheapest route.
##
## The points are only where the search may stop early: it ends once no
## unexplored position could lead to a goal point more cheaply than the best
## found so far. Which point is best (and the exact route there) is then
## asked of the field as for any destination.

var center: Vector2
var radius: float
## Goal points (base centre positions, on their floors) and their surfaces.
var points: Array[Vector3] = []
var surfaces: PackedInt32Array = PackedInt32Array()


func _init(p_center: Vector2, p_radius: float) -> void:
	center = p_center
	radius = maxf(p_radius, 0.0)


func add(point: Vector3, surface: int) -> void:
	points.append(point)
	surfaces.append(surface)


func is_empty() -> bool:
	return points.is_empty()


## The least the way from p to a goal point can cost (see the class notes).
func estimate(p: Vector2) -> float:
	return maxf(p.distance_to(center) - radius, 0.0)
