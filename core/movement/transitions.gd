class_name Transitions
extends RefCounted
## How a base gets from one floor to a neighbouring one, and what it costs.
## See docs/rules/terrain.md and docs/rules/movement.md.
##
## Every change of floor is one of the kinds below. Each kind says whether it
## needs a roll and whether the vertical distance is paid in movement. The
## search and the move command only use kinds that need no roll; brief 006
## (height, part 2) adds the risky ones by letting them through with their
## roll, without changing how they are found.
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
	## Down a drop of the free drop height or more: falling (part 2).
	DROP,
	## Across a gap with no floor (part 2). Nothing produces it yet.
	GAP_JUMP,
}

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


## Whether a move may use this kind in this brief: it exists and needs no roll.
static func allowed_without_roll(kind: Kind) -> bool:
	return kind != Kind.NONE and not RULES[kind]["roll"]


## Every way across a wall, cheapest first. `wall_height` is the vertical
## distance between the two floors (positive), `tag` the tag of the piece whose
## side is the wall (the higher piece), `low_obstacle` whether going up lands on
## a low obstacle.
static func wall_options(
	going_up: bool, wall_height: float, tag: TerrainPiece.Tag, low_obstacle: bool
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
	if tag == TerrainPiece.Tag.LADDER:
		return [Kind.DROP, Kind.LADDER_DOWN]
	return [Kind.DROP, Kind.SHEER_CLIMB_DOWN]


## The cheapest roll-free way across a wall, or NONE.
static func roll_free_wall_kind(
	going_up: bool, wall_height: float, tag: TerrainPiece.Tag, low_obstacle: bool
) -> Kind:
	var best: Kind = Kind.NONE
	var best_cost: float = INF
	for kind: Kind in wall_options(going_up, wall_height, tag, low_obstacle):
		if not allowed_without_roll(kind):
			continue
		var cost: float = wall_cost(kind, 0.0, wall_height)
		if cost < best_cost:
			best = kind
			best_cost = cost
	return best


## Movement a wall crossing costs: the horizontal distance moved, plus the
## height if the kind pays it.
static func wall_cost(kind: Kind, horizontal: float, wall_height: float) -> float:
	if kind == Kind.NONE:
		return INF
	return horizontal + (wall_height if RULES[kind]["pays_height"] else 0.0)
