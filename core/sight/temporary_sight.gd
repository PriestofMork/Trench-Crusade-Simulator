class_name TemporarySight
extends Sight
## TEMPORARY (brief 007, ruling 11): line of sight does not exist yet, so
## every model sees every other. Replaced by the real implementation in
## brief 008; nothing else may rely on this answer.


func can_see(_state: GameState, _viewer: ModelState, _target: ModelState) -> bool:
	return true
