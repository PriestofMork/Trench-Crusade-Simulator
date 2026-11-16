class_name Transitions
extends RefCounted
## How a base gets from one floor to a neighbouring one, and what it costs.
## See docs/rules/terrain.md and docs/rules/movement.md.
##
## Every change of floor is one of the kinds below. Each kind says whether it
## needs a roll and whether the vertical distance is paid in movement. Where
## several kinds can cross the same wall, the one with the fewest rolls is
## taken, then the cheapest (ruling 8 of brief 006), unless a move asks for a
## particular one (climbing down a sheer surface instead of dropping).
##
## Rolls (brief 006): a sheer climb up or down and a gap jump are risky success
## rolls made before the crossing; a drop of the free drop height or more is
## an injury roll after landing (+1 die per full 3"), and so is landing from a
## gap jump onto a far side that much lower.
##
## Walls are crossed at a touch point: going up, the base walks until it touches
## the wall and arrives on top with its centre directly above that point;
## going down, the centre steps off the edge and lands with the base touching
## the wall below. Either way the centre moves the base radius horizontally,
## which is paid as horizontal distance.

enum Kind {
	## No way across.
	NONE,
	## Along one continuous surface (slope up to the steep angle), or from one
	## surface onto another at the same height.
	WALK,
	## Up onto a low obstacle: free here; stopping on top pays its height.
	STEP_ONTO_LOW_OBSTACLE,
	## Up a wall of at most the open climb height, not tagged sheer.
	OPEN_CLIMB,
	## Up a wall of any height tagged ladder.
	LADDER_UP,
	## Up a higher wall or one tagged sheer: a risky climb roll (part 2).
	SHEER_CLIMB_UP,
	## Down a drop of less than the free drop height.
	HOP_DOWN,
	## Down a wall of any height tagged ladder.
	LADDER_DOWN,
	## Down a sheer surface with a risky climb roll (part 2).
	SHEER_CLIMB_DOWN,
	## Down a drop of the free drop height or more: counts as falling.
	DROP,
	## Across a gap with no floor between two ledges.
	GAP_JUMP,
}

## How a move gets down a drop of the free drop height or more (terrain.md,
## "Going down": the player's descent mode). DROP never climbs down a sheer
## surface; CLIMB_DOWN never drops (nor jumps down onto a far side that much
## lower). Ladders and smaller drops are the same in both.
enum DescentMode { DROP, CLIMB_DOWN }

## Per kind: whether it needs a roll, and whether the vertical distance is paid.
const RULES: Dictionary[Kind, Dictionary] = {
	Kind.WALK: {"roll": false, "pays_height": false},
	Kind.STEP_ONTO_LOW_OBSTACLE: {"roll": false, "pays_height": false},
	Kind.OPEN_CLIMB: {"roll": false, "pays_height": true},
	Kind.LADDER_UP: {"roll": false, "pays_height": true},
	Kind.SHEER_CLIMB_UP: {"roll": true, "pays_height": true},
	Kind.HOP_DOWN: {"roll": false, "pays_height": false},
	Kind.LADDER_DOWN: {"roll": false, "pays_height": true},
	Kind.SHEER_CLIMB_DOWN: {"roll": true, "pays_height": true},
	Kind.DROP: {"roll": true, "pays_height": false},
	Kind.GAP_JUMP: {"roll": true, "pays_height": false},
}

## Slack on the height limits, so a wall of exactly 3" computed as 3.0000001"
## still counts as 3".
const HEIGHT_SLACK: float = 0.0001


static func needs_roll(kind: Kind) -> bool:
	return kind != Kind.NONE and RULES[kind]["roll"]


## Whether this kind can be taken with no roll at all.
static func allowed_without_roll(kind: Kind) -> bool:
	return kind != Kind.NONE and not RULES[kind]["roll"]


## Whether the kind climbs a wall (so the wall must reach down to the lower floor).
static func climbs(kind: Kind) -> bool:
	return kind in [Kind.OPEN_CLIMB, Kind.LADDER_UP, Kind.SHEER_CLIMB_UP, Kind.LADDER_DOWN, Kind.SHEER_CLIMB_DOWN]


## Whether the kind needs a risky success roll before it is made.
static func risky_before(kind: Kind) -> bool:
	return kind in [Kind.SHEER_CLIMB_UP, Kind.SHEER_CLIMB_DOWN, Kind.GAP_JUMP]


## Whether a drop of `drop` inches counts as falling (injury roll).
static func is_fall(drop: float) -> bool:
	return drop >= TerrainRules.FREE_DROP_HEIGHT - HEIGHT_SLACK


## How many rolls crossing this way makes. `drop` is how far the model comes
## down (for a drop, or a gap jump to a lower far side), else 0.
static func roll_count(kind: Kind, drop: float = 0.0) -> int:
	match kind:
		Kind.SHEER_CLIMB_UP, Kind.SHEER_CLIMB_DOWN:
			return 1
		Kind.DROP:
			return 1
		Kind.GAP_JUMP:
			return 2 if is_fall(drop) else 1
	return 0


## Of `options` for one wall, the kind a move takes: `preferred` if it is one
## of them, else the fewest rolls, then the cheapest. Kinds that need a roll
## are left out unless `allow_rolls`. NONE if nothing is left.
static func pick_wall_kind(
	options: Array[Kind], going_up: bool, wall_height: float, allow_rolls: bool = true, preferred: Kind = Kind.NONE
) -> Kind:
	if preferred != Kind.NONE and options.has(preferred) and (allow_rolls or not needs_roll(preferred)):
		return preferred
	var best: Kind = Kind.NONE
	var best_key: Vector2 = Vector2(INF, INF)
	for kind: Kind in options:
		if needs_roll(kind) and not allow_rolls:
			continue
		var key: Vector2 = Vector2(roll_count(kind, 0.0 if going_up else wall_height), wall_cost(kind, 0.0, wall_height))
		if key < best_key:
			best = kind
			best_key = key
	return best


## Every way across a wall, cheapest first. `wall_height` is the vertical
## distance between the two floors (positive), `tag` the tag of the piece whose
## side is the wall (the higher piece), `low_obstacle` whether going up lands on
## a low obstacle.
static func wall_options(
	going_up: bool, wall_height: float, tag: TerrainPiece.Tag, low_obstacle: bool,
	mode: DescentMode = DescentMode.DROP
) -> Array[Kind]:
	if tag == TerrainPiece.Tag.IMPASSABLE:
		return []
	if going_up:
		if tag == TerrainPiece.Tag.SHEER:
			return [Kind.SHEER_CLIMB_UP]
		if low_obstacle and wall_height <= TerrainRules.LOW_OBSTACLE_HEIGHT + HEIGHT_SLACK:
			return [Kind.STEP_ONTO_LOW_OBSTACLE]
		if tag == TerrainPiece.Tag.LADDER:
			return [Kind.LADDER_UP]
		if wall_height <= TerrainRules.OPEN_CLIMB_HEIGHT + HEIGHT_SLACK:
			return [Kind.OPEN_CLIMB]
		return [Kind.SHEER_CLIMB_UP]
	if wall_height < TerrainRules.FREE_DROP_HEIGHT - HEIGHT_SLACK:
		return [Kind.HOP_DOWN]
	var down: Kind = Kind.DROP if mode == DescentMode.DROP else Kind.SHEER_CLIMB_DOWN
	if tag == TerrainPiece.Tag.LADDER:
		return [down, Kind.LADDER_DOWN]
	return [down]


## The cheapest roll-free way across a wall, or NONE.
static func roll_free_wall_kind(
	going_up: bool, wall_height: float, tag: TerrainPiece.Tag, low_obstacle: bool
) -> Kind:
	return pick_wall_kind(wall_options(going_up, wall_height, tag, low_obstacle), going_up, wall_height, false)


## The way across a wall a move takes when rolls are allowed (see pick_wall_kind()).
static func wall_kind(
	going_up: bool, wall_height: float, tag: TerrainPiece.Tag, low_obstacle: bool, preferred: Kind = Kind.NONE,
	mode: DescentMode = DescentMode.DROP
) -> Kind:
	return pick_wall_kind(wall_options(going_up, wall_height, tag, low_obstacle, mode), going_up, wall_height, true, preferred)


## A short name for showing a crossing that needs a roll.
static func roll_name(kind: Kind) -> String:
	match kind:
		Kind.SHEER_CLIMB_UP:
			return "Climb"
		Kind.SHEER_CLIMB_DOWN:
			return "Climb down"
		Kind.GAP_JUMP:
			return "Jump"
		Kind.DROP:
			return "Drop"
	return ""


## Movement a wall crossing costs: the horizontal distance moved, plus the
## height if the kind pays it.
static func wall_cost(kind: Kind, horizontal: float, wall_height: float) -> float:
	if kind == Kind.NONE:
		return INF
	return horizontal + (wall_height if RULES[kind]["pays_height"] else 0.0)
