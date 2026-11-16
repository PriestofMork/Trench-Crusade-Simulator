class_name Sight
extends RefCounted
## The one question about line of sight the rules ask: can model `viewer` see
## model `target`? Everything that needs sight (a charge target, ruling 11 of
## brief 007; later shooting) asks it here, through GameState.rules.sight, so
## brief 008 only has to replace the implementation. See
## docs/rules/line-of-sight.md.


func can_see(_state: GameState, _viewer: ModelState, _target: ModelState) -> bool:
	return false
