# 004: Height, part 1: floors, slopes, open climbs and low obstacles

## Goal

The table stops being flat. Models can stand on platforms, walk up ramps, climb
walls up to 3" without a roll, cross low obstacles, hop down small drops, and walk
under bridges. The reach field, move command and indicator all work across heights.

Everything in this brief is roll-free. Anything that needs a roll (sheer climbs,
gap jumps, drops of 3" or more) is simply unreachable here and comes in part 2.

Rules reference: all of `docs/rules/terrain.md`, and `docs/rules/movement.md`
section "Move". Read the "Height", "Terrain marking" and "Stopping vs passing" rows
in `docs/design.md`.

## Build

**Core: terrain data**
- `TerrainPiece` gains a base height and a height, so a box can float (a bridge) or
  sit on another piece. Add a ramp shape: a box whose top slopes from one end to the
  other.
- Each piece has a tag: none, sheer, ladder, impassable.
- The three tunable values from `terrain.md` live in one constants file in `core/`.

**Core: height field**
- `HeightField`, built from the terrain data: a grid over the table (same cell size
  as the reach field). Each cell holds its floors: the table surface and the top
  surface of every piece at that spot, each with its height, its slope and the piece
  it belongs to. Impassable pieces give no floor. A surface steeper than the steep
  angle is a wall, not a floor.
- Two position tests, exactly as in "Where a model can be" in `terrain.md`:
  - **passable:** base centre over the floor, no overlap with higher terrain;
  - **stoppable:** passable, plus at least half the base area over the floor,
    headroom for the model's cylinder height, and no overlap with another base.
  Compute the supported share of the base area in a way that is exact enough to be
  stable at straight edges: a base centred exactly on a straight ledge must count as
  stoppable.

**Core: transitions between floors**

One function decides how a base gets from one floor position to a neighbouring one,
and what it costs. In this brief:

| Transition | Allowed | Cost |
|---|---|---|
| Walk on a continuous surface, slope up to the steep angle | yes | distance along the surface |
| Up a wall of at most the open climb height, piece not tagged sheer | yes | horizontal distance + wall height |
| Up a wall of any height on a piece tagged ladder | yes | horizontal distance + wall height |
| Up a higher wall, or one tagged sheer | no (part 2) | |
| Down a drop of less than 3" | yes | horizontal distance only |
| Down a drop of 3" or more | no (part 2) | |
| Across a gap with no floor | no (part 2) | |

- Going up a wall, the model arrives on top directly above the point where its base
  touched the wall. That arrival point only has to be passable, not stoppable.
- **Low obstacles:** going up onto a piece no higher than the low obstacle height
  costs nothing as a transition. Instead, a destination on top of a low obstacle
  costs its height on top of the path cost, unless the model started the move on
  that same piece. Implement this as a surcharge on stopping, not as a refund along
  the path, so the path search never sees a negative cost.
- Structure this as a table of transition kinds with a cost and a "needs roll" flag,
  so part 2 can add the risky kinds without rewriting the search.

**Core: positions, commands and reach field in 3D**
- A model's position now includes its height, and it always stands on a floor.
  `PlaceModelCommand` requires a stoppable position. `MoveCommand` takes 3D
  waypoints; every point along the path must be passable, every change of floor must
  be an allowed transition, the end must be stoppable, and the total cost including
  any low obstacle surcharge must fit the remaining movement.
- `ReachField` runs over (cell, floor) pairs: it routes through passable positions
  and offers only stoppable ones as destinations. Everything from briefs 002 and 003
  must keep working: friendly pass-through, the 1" rule for enemies (measured in 3D
  between the two cylinders, so a model on a bridge is not blocked by an enemy far
  below), destination snapping, and the guarantee that every path the field returns
  is accepted by `MoveCommand.validate`.
- Any-angle path shortening must stay correct across height: a shortcut is only
  taken when the straight segment is a legal walk on one continuous surface.
- Keep selection responsive, and give the time to build the reach field for the test
  table in your report.

**Game**
- Terrain views for the new shapes, built from the terrain data as before. Tagged
  pieces are tinted so tags are visible while testing.
- Models stand at their floor height. A move plays as one smooth motion: along the
  ground, straight up a wall, onward on top, without pausing.
- The movement indicator follows the surfaces: on a platform it is drawn on the
  platform, on a ramp it lies on the ramp, and under a bridge and on top of it are
  both shown. Outline and fill must stay smooth and must not flicker against the
  terrain.
- The path preview shows the vertical parts of the path and the total cost,
  including a low obstacle surcharge when the destination has one.
- Picking: the cursor chooses the floor it is pointing at (the surface the mouse ray
  hits), so a spot under a bridge and the spot above it can both be targeted by
  moving the camera.
- A test table that exercises everything: a ramp up to a 2" platform; a 2" wall
  (open climb) and a 4" block (top unreachable for now); a 2" wall tagged sheer (not
  climbable for now); a 4" tower with one face tagged ladder; a row of 0.5" sandbags
  to cross; a 1" crate big enough to stand on and a small one too small to stop on;
  a narrow beam that can be crossed but not stopped on; a bridge high enough to walk
  under; a ramp steeper than the steep angle; an impassable piece.

**Tests**
- Height field: floors at a spot with a bridge over it; headroom refuses a tall
  model under a low bridge and allows a short one.
- Passable and stoppable: centred on a straight ledge is stoppable; at an outward
  corner it is passable but not stoppable; on the narrow beam passable, not
  stoppable; overlapping a wall is neither.
- Transitions: each row of the table above, including the sheer and ladder tags and
  the 3" boundaries on both the climb and the drop.
- Cost: a ramp costs the slope distance; an open climb costs its height; crossing
  sandbags costs nothing extra; stopping on the crate costs its height; moving
  around on top of the crate after starting there costs no surcharge.
- Reach field: the platform is reachable by the ramp and by the 2" wall, at different
  costs; the 4" block top is never reachable; the tower top is reachable only by the
  ladder face; a climb through a corner is used as a route but the corner is not a
  destination; a point under the bridge and the point above it are separate
  destinations; the consistency test passes on the test table.
- All existing tests still pass, adapted to 3D positions where needed.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game (checked in screenshots, with the capture script extended as
  needed): a model walks up the ramp, climbs the 2" wall and carries on in one move,
  crosses the sandbags, stops on the crate, hops down from the platform, and reaches
  both levels at the bridge; the indicator lies on each surface.
- `core/` still has no scene-tree access.

## Out of scope

Sheer climbs with rolls, jumping gaps, drops of 3" or more, falling, the orange
risky area, turn order, dice, charge, retreat, line of sight, importing maps or
models.
