class_name MoveSegment
extends RefCounted
## One segment of a checked path (see MoveLegality.segments_for()): where it
## runs, how it is taken, what it costs, and the rolls it makes. Plain data,
## never changed once made, so a move under way may share it.

var from: Vector3
var to: Vector3
var kind: Transitions.Kind = Transitions.Kind.NONE
var cost: float = 0.0
## How far the model comes down on this segment (0 going up or level).
var drop: float = 0.0
## How far it goes up (0 going down or level).
var rise: float = 0.0
## Gap jumps: the gap's width, and the point over the middle of the gap (at
## the take-off height) that a failed jump falls from.
var gap_width: float = 0.0
var fall_point: Vector3 = Vector3.ZERO


## Whether a risky success roll is made at `from` before the segment.
func roll_before() -> bool:
	return Transitions.risky_before(kind)


## Whether landing at `to` counts as falling (an injury roll), and from how high.
func injury_drop() -> float:
	if kind == Transitions.Kind.DROP:
		return drop
	if kind == Transitions.Kind.GAP_JUMP and Transitions.is_fall(drop):
		return drop
	return 0.0


func roll_count() -> int:
	return Transitions.roll_count(kind, drop)


## The rolls this segment makes, in order, as plain records for the UI and
## tests: {"kind": &"climb" | &"jump" | &"injury", "label", "at" (Vector3),
## "risky", "fall_inches" (injury)}.
func rolls(fall_dice: Callable = Callable()) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if roll_before():
		var climbing: bool = kind != Transitions.Kind.GAP_JUMP
		var size: float = (rise + drop) if climbing else gap_width + rise
		result.append({
			"kind": &"climb" if climbing else &"jump", "label": "%s %.1f (risky)" % [Transitions.roll_name(kind), size],
			"at": from, "risky": true,
		})
	var fall: float = injury_drop()
	if fall > 0.0:
		var dice: int = int(fall_dice.call(fall)) if fall_dice.is_valid() else floori((fall + Transitions.HEIGHT_SLACK) / TerrainRules.FREE_DROP_HEIGHT)
		result.append({
			"kind": &"injury", "label": "Drop %.1f (injury %+d)" % [fall, dice], "at": to, "risky": false,
			"fall_inches": fall,
		})
	return result
