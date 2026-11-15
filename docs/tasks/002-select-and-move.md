# 002: Select and move on flat ground

## Goal

Click a model, see how far it can go, click a destination, and it moves there along a
legal path around terrain and other models. Flat ground only: no climbing, jumping,
falling, dash, charge or retreat yet, and no turn order.

Rules reference: `docs/rules/movement.md`, section "Move" only.

## Build

**Window**
- The game window is far too small. Default to 1600 x 900, resizable, starting
  maximized, with content scaling so the 3D view fills the window.

**Core: terrain as data**
- A `TerrainPiece` data class: an oriented box (centre, size, rotation about the
  vertical axis) and a flag for whether it blocks movement. `GameState` holds the list.
- The main scene's placeholder boxes are now built from this list, not placed by hand.

**Core: move command**
- `ModelState` gains its Movement characteristic (inches) and the movement it has
  left in the current activation.
- `MoveCommand(model_id, waypoints)`: the path is a polyline on the table from the
  model's current position. It is valid only if all of these hold:
  - its total length is no more than the model's remaining movement;
  - at no point along the path does the model's base overlap a blocking terrain
    piece, another model's base, or leave the table;
  - at no point along the path, including the end, does the base come within 1" of
    an enemy model's base (edge to edge).
- Applying it moves the model to the last waypoint and deducts the path length.
- A rejected command says why (too far, blocked, too close to an enemy), so the UI
  can show it.
- Base-versus-shape checks are plain 2D geometry in `core/` (circle against oriented
  rectangle, circle against circle, swept along each segment). No physics engine.
**Core: reach field**
- `ReachField`: given the state and a model, computes everywhere the centre of that
  model's base can legally get to with its remaining movement. Pure geometry in
  `core/`, no navigation server.
- Method: a grid over the table (cell size a constant, start with 0.25"). A cell is
  standable if the base centred there passes the same legality checks as
  `MoveCommand` (terrain, other bases, table edge, 1" from enemies). Run a
  shortest-path search from the model's position over standable cells, with
  16-direction neighbours so distances are close to true straight-line distances,
  stopping at the remaining movement. A step between two cells is only allowed if the
  base swept along it is legal.
- It exposes: whether a point is reachable, the path cost to it, and a path to it as
  waypoints, simplified by removing waypoints wherever the direct segment between
  their neighbours is still legal.
- **Consistency requirement:** every path the reach field returns must be accepted by
  `MoveCommand.validate`. The field may be slightly conservative (a little smaller
  than the true reachable area) but never optimistic. Cover this with a test that
  samples many reachable cells on a table with terrain and validates each path.
- It is recomputed when a model is selected and after any command changes the state.
  Selecting a model must not cause a noticeable hitch; if it does, restrict the grid
  to the square around the model that its remaining movement can reach.

- A temporary `ResetMovementCommand` restores a model's movement to full. It stands
  in for activations until brief 003 and must be marked as temporary in the code.

**Game: selection and movement UI**
- Left-click a model to select it; click empty table or press Escape to deselect.
  The selected model is highlighted.
- **Movement area indicator (the most important part of this brief).** While a model
  is selected, the table shows everywhere the centre of its base can move to, in the
  style of an XCOM movement indicator: a crisp blue outline around the reachable
  area with a faint blue fill inside. It comes from the reach field, so it bends
  around terrain, leaves holes around other models, and stops 1" short of enemies.
  Build the outline from the reachable-cell mask as a smooth contour (for example
  marching squares on the cost field), not as visible grid squares. It sits just
  above the table surface without flickering, and updates after each move to show
  what is left.
- Hovering inside the area shows the path from the model to the cursor, taken from
  the reach field, with its length in inches next to the cursor, and a ghost circle
  of the base at the destination.
- Hovering outside the area shows no path, and the ghost circle turns red.
- Left-click inside the area sends the `MoveCommand` with that path; the model view slides along
  the path to the destination. Input is ignored while it slides.
- Pressing R sends the temporary reset command for the selected model.
- Give the six starting models different base sizes and Movement values so the
  differences can be seen.

**Tests**
- `MoveCommand`: accepts a legal path; rejects too long, through terrain, through
  another model, off the table, ending within 1" of an enemy, passing within 1" of an
  enemy mid-path; allows passing and ending within 1" of a friendly model as long as
  bases do not overlap.
- Remaining movement is deducted by path length, and a second move can use what is left.
- The geometry helpers, including a base that only grazes a rotated box corner.
- `ReachField`: on an empty table the reachable area is close to a disc of the
  remaining movement (within a few percent, never larger); a point behind a wall is
  reachable only if the way around is short enough; no reachable point lies within
  1" of an enemy; and the consistency test described above.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game, selecting a model shows the blue movement area; it visibly
  wraps around a terrain box and stops short of enemy models; you can move the model
  around a box; and the area shrinks to the remaining movement after a move.
- You have looked at the indicator in the running game yourself (a screenshot of the
  window is enough) and it reads as a clean outline, not a blocky grid.
- `core/` still has no scene-tree access, and `game/` never changes a model's
  position except by sending a command.

## Out of scope

Turn order and activations, dash, charge, retreat, climbing, jumping, falling, height
of any kind, line of sight, dice, real miniature models.
