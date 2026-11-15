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
- A temporary `ResetMovementCommand` restores a model's movement to full. It stands
  in for activations until brief 003 and must be marked as temporary in the code.

**Game: selection and movement UI**
- Left-click a model to select it; click empty table or press Escape to deselect.
  The selected model is highlighted.
- While a model is selected, hovering the table shows a path from the model to the
  cursor, found with Godot's navigation (a navigation mesh built from the terrain
  data, with the agent radius of the selected model's base). Other models are
  obstacles too.
- The path preview shows its length in inches next to the cursor. It is drawn in one
  colour when `MoveCommand.validate` accepts it and another when it does not, with
  the rejection reason shown.
- A ring around the selected model shows its remaining movement as a radius (the
  straight-line maximum, not the exact reachable area).
- Left-click with a valid path sends the `MoveCommand`; the model view slides along
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

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- In the running game you can select a model, see the path preview change colour
  when it is illegal, move it around a terrain box, and be refused when approaching
  within 1" of an enemy model.
- `core/` still has no scene-tree access, and `game/` never changes a model's
  position except by sending a command.

## Out of scope

Turn order and activations, dash, charge, retreat, climbing, jumping, falling, height
of any kind, line of sight, dice, real miniature models.
