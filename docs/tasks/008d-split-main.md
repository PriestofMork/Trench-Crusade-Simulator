# 008d: Split `game/main.gd` into mode controllers

## Goal

`game/main.gd` is about 1,700 lines and holds everything: input, selection, the
move preview and its background reach field, charge mode, Retreat, sight, the
confirm panel, event playback, undo and redo. Shooting and melee attacks (brief
009) would add two more modes to it. Split it now, so each interaction mode is its
own script, as `docs/design.md` ("game/ (presentation)") now requires.

**No behaviour change.** The game must look and play exactly as it does now. This
is a refactor of `game/` only; `core/` is not touched, except where a test helper
needs to move.

## Target structure

A suggestion; change it if you find a better split, and say why in your report.

- `game/main.gd`: builds the scene, owns the `GameState`, wires the parts together,
  routes input to the active mode. Aim for well under 300 lines.
- `game/session/` (or similar): the parts every mode shares.
  - **Command sender:** sends commands, keeps the event queue, plays events back,
    raises pending decisions, handles undo and redo and what follows a restore.
  - **Selection:** the selected model and hover picking under the mouse.
  - **Background jobs:** one place for worker-thread work (reach field, charge
    route) with keys, cancelling and waiting, instead of a hand-written copy per
    job.
  - **Caches** keyed by game state (reach, sight, charge routes), cleared in one
    place when the state changes.
  - **Confirm panel** as one reusable prompt.
- `game/modes/`: one controller per mode, all with the same small interface
  (enter, exit, hover, click, key, refresh):
  - **Move** (including Dash and the Drop / Climb down toggle, the pinned
    destination and the movement indicator);
  - **Charge** (declaration labels, click-to-route, route toggle, contact arc);
  - **Retreat** (free attack list and order, then the move);
  - **Sight** overlays (hover line, overview, debug cylinders), which may be a
    helper used by modes rather than a mode.
  Adding a new mode later must not need changes to the other modes.

## Rules for the refactor

1. The public methods that tests and capture tools call on `main.gd` keep working,
   or the tests and tools are updated in the same commit. Do not leave a tool
   broken.
2. Move code; do not rewrite logic while moving it. Where you find a bug, note it
   in your report and fix it only if it is a one-liner.
3. Small commits, each one leaving the game working and all tests passing.
4. Follow "Compute on demand" in `docs/design.md`; nothing new is computed.

## Also in this brief

- Adapt the three capture tools that still expect hovering to show a charge route
  (`tools/capture_charge.gd`, step 9 of `tools/capture_sight.gd`,
  `tools/capture_charge_008b.gd`) to the click-to-route flow from brief 008c, and
  run them.
- Run every capture tool in `tools/` at the end and report that each passes.

## Tests

- All existing tests pass unchanged in meaning.
- Add a few game-layer tests for the new seams: switching modes calls exit and
  enter; a state change clears every cache; a background job whose key is stale is
  discarded.

## Done when

- The test command in `CLAUDE.md` passes, with the output in your report.
- Every capture tool passes, run with real mouse clicks.
- `main.gd` line count, and the line count of each new script, are in your report.
- `core/` is unchanged apart from test helpers, has no scene-tree access, and the
  only random calls are in the dice service.

## Out of scope

New features, visual changes, attacks, the UI design work.
