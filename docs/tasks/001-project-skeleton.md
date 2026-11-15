# 001: Project skeleton

## Goal

A Godot project that opens, shows a table with a few models on it, and has the
core/game split and the test runner in place. Nothing is playable yet; this is the
foundation every later task builds on.

## Build

**Project**
- `project.godot` at the repository root, with the folder layout from `CLAUDE.md`.
- `docs/.gdignore` so Godot does not import the docs folder.
- Add an empty `Godot/.gdignore` so the editor does not scan the executables folder.
- Vendor GUT into `addons/gut/` (the release matching the installed Godot version) and
  enable it.

**Core (`core/`)**
- `GameState`: holds a list of models. Each model has an id, owning player (0 or 1),
  position (`Vector3`, inches), base diameter (stored in mm, exposed in inches) and
  cylinder height (inches).
- A command base class with `validate(state)` and `apply(state)`, and one concrete
  command: `PlaceModelCommand`, which adds a model at a position. It is rejected if the
  new base would overlap an existing base or lie outside the table.
- Table size lives in `GameState` (default 48 x 48 inches), not hard-coded elsewhere.
- A seeded dice service with `roll_d6()` and `roll(count)`. Same seed, same sequence.
- No scene-tree access anywhere in `core/`.

**Game (`game/`)**
- Main scene: a flat table sized from `GameState`, a light, and three or four
  box-shaped terrain placeholders.
- Camera: orbit (right mouse drag), pan (middle mouse drag or WASD), zoom (wheel),
  clamped so it cannot go under the table or lose the table entirely.
- A model view that draws a model as a cylinder of its base diameter and height,
  coloured by owning player. On start, the scene builds a `GameState`, places three
  models per player through `PlaceModelCommand`, and creates the views from the state.

**Tests (`tests/`)**
- Dice: the same seed gives the same sequence; rolls stay within 1 to 6.
- `PlaceModelCommand`: accepts a valid placement; rejects overlap; rejects off-table.
- mm-to-inch conversion of base sizes.

## Done when

- The test command from `CLAUDE.md` passes, and the output is in your report.
- Opening the project and pressing Play shows the table, terrain boxes and six
  cylinders, and the camera controls work.
- `core/` contains no class extending `Node` and no call to `get_tree()`.

## Out of scope

Selecting or moving models, line of sight, real miniature models, UI, any game rule.
