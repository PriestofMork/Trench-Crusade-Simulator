# 003: Edge-based indicator and moving through friendly models

## Goal

Two corrections to brief 002 from play-testing. Still flat ground only.

Rules reference: `docs/rules/movement.md`, section "Move".

## Build

**Moving through friendly models**
- A model may move through friendly models' bases, but may not end its move with its
  base overlapping any base. Enemy bases still block, and the 1" rule for enemies is
  unchanged.
- `MoveCommand` validation: friendly bases are ignored along the path and checked
  only at the final position.
- `ReachField`: positions overlapping a friendly base can be passed through but are
  not valid destinations. Keep the consistency guarantee: every path the field
  returns to a valid destination is accepted by `MoveCommand.validate`.

**Indicator shows where the base edge can reach**
- The outline and fill now cover the area the model's base can touch: the set of
  valid centre positions grown by the base radius. On an empty table a model with
  6" of movement and a 1" wide base shows a disc of radius 6.5", not 6".
- Around obstacles the outline therefore comes right up to walls and to the edge of
  friendly bases, instead of stopping a base radius short.
- The destination under the cursor is the valid centre position closest to the
  cursor, so the whole indicated area is clickable: clicking near the outline places
  the base so that it reaches towards the cursor as far as it legally can. The ghost
  base and the path preview show that snapped position.
- Outside the indicated area the ghost is red and clicking does nothing, as before.
- Keep the outline smooth; growing the area must not bring back visible grid steps.

**Housekeeping**
- `core/movement/` is an empty folder. Either move the movement classes
  (`move_legality.gd`, `reach_field.gd`, `planar_geometry.gd`) into it, with their
  tests mirrored, or remove it. Pick one and keep `core/` tidy.

**Tests**
- `MoveCommand`: a path through a friendly base is accepted; ending on a friendly
  base is rejected; a path through an enemy base is still rejected.
- `ReachField`: a spot behind a line of friendly models that blocked it before is now
  reachable; no valid destination overlaps any base; the consistency test still
  passes with friendly models in the way.
- The snapped destination for a cursor point just outside the centre area is the
  closest valid centre, and is itself a valid destination.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game, a model can walk through a friendly model but not stop on it,
  and the indicator reaches up to walls. Check it in screenshots as in brief 002.

## Out of scope

Height of any kind (slopes, climbing, jumping, falling), orange risky areas, turn
order, dash, charge, retreat. These are later briefs.
