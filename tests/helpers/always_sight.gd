class_name AlwaysSight
extends Sight
## Test helper: every model sees every other (the stand-in brief 007 used
## before line of sight existed). For tests that are about something else
## and must not depend on what blocks sight.


func check(_state: GameState, viewer: ModelState, target: ModelState) -> SightResult:
	return SightResult.clear(viewer.position, target.position)


func check_between(
	_state: GameState, viewer: SightCylinder, target: SightCylinder, _ignored_ids: PackedInt32Array
) -> SightResult:
	return SightResult.clear(viewer.base, target.base)
