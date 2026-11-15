class_name TerrainRules
extends RefCounted
## The tunable values for moving over terrain, from docs/rules/terrain.md
## ("Tunable values"). Nothing else may hard-code them.

## Low obstacle: the highest thing that is free to cross, inches.
const LOW_OBSTACLE_HEIGHT: float = 1.0
## Open climb: the highest wall climbed without a roll, inches.
const OPEN_CLIMB_HEIGHT: float = 3.0
## Steep slope: a slope steeper than this is a wall, degrees.
const STEEP_SLOPE_DEGREES: float = 70.0

## A drop of less than this is a free hop down; from this height on it counts as
## falling. Not one of the three tunable values in terrain.md: it comes from
## "Going down" there and "Falling" in movement.md, and is kept here so it is
## named in one place too.
const FREE_DROP_HEIGHT: float = 3.0


## Rise per inch of the steepest slope that is still walked.
static func steep_gradient() -> float:
	return tan(deg_to_rad(STEEP_SLOPE_DEGREES))
