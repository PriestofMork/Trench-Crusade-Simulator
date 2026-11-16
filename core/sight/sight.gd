class_name Sight
extends RefCounted
## The questions about line of sight the rules ask. Everything that needs
## sight (a charge target, later shooting) asks here, through
## GameState.rules.sight. See docs/rules/line-of-sight.md. The standard
## implementation is LineOfSight; this base sees nothing.


## Whether model `viewer` can see model `target`.
func can_see(state: GameState, viewer: ModelState, target: ModelState) -> bool:
	return check(state, viewer, target).visible


## Whether model `viewer` can see model `target` where they stand now, with
## the clear segment found.
func check(_state: GameState, _viewer: ModelState, _target: ModelState) -> SightResult:
	return SightResult.blocked()


## The same question for cylinders given as plain data (a model at a
## position it is not at, say). The models in `ignored_ids` do not block
## (the viewer's and the target's own models, when they are models); the
## cylinders themselves never block each other.
func check_between(
	_state: GameState, _viewer: SightCylinder, _target: SightCylinder, _ignored_ids: PackedInt32Array
) -> SightResult:
	return SightResult.blocked()
