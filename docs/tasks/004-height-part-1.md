# 004: Height, part 1: floors, slopes and steps

## Goal

The table stops being flat. Models can stand on platforms, walk up ramps and over
low steps, cross trench walls inside trench zones, and walk under bridges. The reach
field, move command and indicator all work across heights.

No rolls yet: anything that needs a climb or a jump is simply unreachable in this
brief and comes in part 2.

Rules reference: `docs/rules/terrain.md` (all of it) and `docs/rules/movement.md`
sections "Move" and "Open terrain". Read the "Height" row in `docs/design.md`.

## Build

**Core: terrain data**
- `TerrainPiece` gains a base height and a height, so a box can float (a bridge) or
  sit on another piece. Add a ramp shape: a box whose top slopes from one end to the
  other.
- Each piece has an override: none, trench wall, impassable, cannot be climbed.
  (Cannot be climbed has no effect until part 2; store it.)
- `TrenchZone`: an oriented rectangle on the table. `GameState` holds a list.
- The three tunable values from `terrain.md` live in one constants file in `core/`.

**Core: height field**
- `HeightField`, built from the terrain data: a grid over the table (same cell size
  as the reach field). Each cell holds its floors: the table surface and the top
  surface of every piece at that spot, each with its height, its slope and the piece
  it belongs to. Impassable pieces give no floor.
- Standing: a query for whether a base of a given diameter and cylinder height can
  stand at a point on a given floor, following "Standing on terrain" in `terrain.md`
  (headroom, centre supported, no overlap with terrain rising more than the open
  step above the floor).
- Stepping: a query for whether a base can pass directly between two nearby floor
  positions by walking. Allowed when the surface between them is continuous and no
  steeper than the steep angle, or the height difference is at most the open step,
  or the wall between them is inside a trench zone (or its piece is marked trench
  wall) and no higher than the trench wall height. Otherwise not, in this brief.
- Cost of a walk: distance along the surface on slopes; horizontal distance only
  across an open step or trench wall.

**Core: positions, commands and reach field in 3D**
- A model's position now includes its height, and it always stands on a floor.
  `PlaceModelCommand` and `MoveCommand` use the height field for legality; a move's
  waypoints are 3D points on floors.
- `ReachField` runs over (cell, floor) pairs using the stepping query and costs
  above. Everything from briefs 002 and 003 must keep working: friendly pass-through,
  the 1" rule for enemies (measure it in 3D between the two cylinders, so a model on
  a bridge is not blocked by an enemy far below), destination snapping, and the
  guarantee that every path the field returns is accepted by `MoveCommand.validate`.
- Any-angle path shortening must stay correct across height: a shortcut is only
  taken when the base can walk the straight segment on the surface.
- Keep selection responsive. Report the time to build the reach field for the test
  table in your report.

**Game**
- Terrain views for the new shapes, built from the terrain data as before. Trench
  zones get a subtle debug overlay that can be toggled with a key.
- Models stand at their floor height.
- The movement indicator follows the surfaces: on a platform it is drawn on the
  platform, on a ramp it lies on the ramp, and under a bridge and on top of it are
  both shown. Outline and fill must stay smooth and must not flicker against the
  terrain.
- Picking: the cursor chooses the floor it is pointing at (the surface the mouse ray
  hits), so a spot under a bridge and the spot above it can both be targeted by
  moving the camera.
- A test table that exercises everything: a ramp up to a 2" platform; a 0.5" raised
  area (open step); a trench formed by 2" banks inside a trench zone; the same 2"
  bank outside any zone (must not be crossable); a 4" block (top unreachable for
  now); a bridge high enough to walk under; a ramp steeper than the steep angle
  (not walkable).

**Tests**
- Height field: floors at a spot with a bridge over it; headroom refuses a tall
  model under a low bridge and allows a short one; a base may overhang a drop but
  not overlap a wall.
- Stepping: open step allowed, 1.5" step refused; walkable ramp allowed and steep
  ramp refused; trench wall allowed inside a zone, refused outside, allowed with the
  per-piece override; 3.5" wall refused even inside a zone.
- Cost: a move up a ramp costs the slope distance; crossing an open step adds nothing.
- Reach field: the platform top is reachable only via the ramp; the 4" block top is
  never reachable; a point under the bridge and the point above it are separate
  destinations; the consistency test passes on the test table.
- All existing tests still pass, adapted to 3D positions where needed.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game (checked in screenshots, with the capture script extended as
  needed): a model walks up the ramp onto the platform, the indicator lies on the
  ramp and platform, the trench is crossable inside its zone, and both levels at the
  bridge can be reached.
- `core/` still has no scene-tree access.

## Out of scope

Climbing, jumping gaps, jumping down, falling, the orange risky area, ladder and
stairs links, turn order, dice, charge, retreat, line of sight, importing maps or
models. A drop larger than the open step is simply not crossable in this brief, in
either direction.
