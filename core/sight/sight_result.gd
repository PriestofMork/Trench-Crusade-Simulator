class_name SightResult
extends RefCounted
## The answer to one sight check, for the rules and the game layer: whether
## the target is visible and, if it is, the clear segment that was found
## (viewer end first). Kept as an object so later questions (how much of the
## target can be seen, for cover) can add to it.

var visible: bool = false
## A point of the viewer's cylinder and a point of the target's with nothing
## in between. Only meaningful when `visible`.
var from: Vector3 = Vector3.ZERO
var to: Vector3 = Vector3.ZERO


static func blocked() -> SightResult:
	return SightResult.new()


static func clear(p_from: Vector3, p_to: Vector3) -> SightResult:
	var result: SightResult = SightResult.new()
	result.visible = true
	result.from = p_from
	result.to = p_to
	return result
