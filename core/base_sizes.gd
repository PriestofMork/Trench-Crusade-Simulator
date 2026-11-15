class_name BaseSizes
extends RefCounted
## Base sizes and the cylinder height that goes with each one.
##
## Base diameters are stored in millimetres (as in the data files) and converted
## to inches (1 Godot unit = 1 inch) only here. The heights are the single tunable
## table from docs/rules/line-of-sight.md; nothing else may hard-code them.

const MM_PER_INCH: float = 25.4

## Base diameter in mm -> cylinder height in inches.
const HEIGHT_INCHES_BY_BASE_MM: Dictionary[int, float] = {
	25: 1.7,
	32: 1.9,
	40: 2.2,
	50: 2.6,
	60: 3.0,
}


static func mm_to_inches(mm: float) -> float:
	return mm / MM_PER_INCH


static func is_known(base_mm: int) -> bool:
	return HEIGHT_INCHES_BY_BASE_MM.has(base_mm)


## Height in inches for a base size. An unknown base size is an error:
## it pushes an error and returns -1.0.
static func height_inches(base_mm: int) -> float:
	if not is_known(base_mm):
		push_error("Unknown base size: %d mm" % base_mm)
		return -1.0
	return HEIGHT_INCHES_BY_BASE_MM[base_mm]
